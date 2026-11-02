-- Save conflicts must not use SQLSTATE 40001 (serialization_failure): the
-- Data API (PostgREST) retries transactions that fail with it automatically and
-- without limit, so one conflicting save looped for hours (93 million retries,
-- the CPU at 95%). The app recognises a conflict by its message
-- ("save_conflict"), so a plain error code changes nothing for any build.
-- Otherwise identical to 20261110000001. Safe to run again.

create or replace function public.put_player_save(p_save jsonb, p_base_version integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    doc jsonb := p_save;
    settings public.wallet_settings;
    charges jsonb;
    items jsonb;
    species integer;
    new_version integer;
begin
    if me is null then
        raise exception 'not_signed_in' using errcode = '42501';
    end if;
    if jsonb_typeof(doc) = 'object' and not public.valid_wallet(doc) then
        raise exception 'invalid_wallet' using errcode = '22023';
    end if;
    select * into settings from public.wallet_settings;
    if jsonb_typeof(doc -> 'wallet' -> 'earned') = 'object' then
        select coalesce(jsonb_object_agg(c.key, c.amount), '{}'::jsonb) into charges
        from public.coin_charges c
        where c.user_id = me
          and coalesce((doc -> 'wallet' -> 'spent' ->> c.key)::numeric, 0) < c.amount;
        doc := jsonb_set(doc, '{wallet,spent}', coalesce(doc -> 'wallet' -> 'spent', '{}'::jsonb) || charges);

        if settings.verify_ad_rewards then
            doc := jsonb_set(doc, '{wallet,earned}',
                (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
                 from jsonb_each(doc -> 'wallet' -> 'earned') e where e.key not like 'ad-%')
                || (select coalesce(jsonb_object_agg('ad-' || a.reward_id, a.coins), '{}'::jsonb)
                    from public.ad_rewards a where a.user_id = me));
        end if;
    end if;

    if jsonb_typeof(doc -> 'wallet' -> 'ownedItemIDs') = 'array' then
        select coalesce(jsonb_agg(distinct i), '[]'::jsonb) into items
        from (
            select v.value as i
            from jsonb_array_elements_text(doc -> 'wallet' -> 'ownedItemIDs') v
            where not settings.enforce_inventory
               or not exists (select 1 from public.mystery_box_prizes z where z.item_id = v.value and z.festival_start is null)
               or exists (select 1 from public.owned_items o where o.user_id = me and o.item_id = v.value)
            union
            select o.item_id from public.owned_items o where o.user_id = me and o.item_id not like 'companion:%'
        ) owned;
        doc := jsonb_set(doc, '{wallet,ownedItemIDs}', items);
        if jsonb_typeof(doc -> 'wallet' -> 'equipped') = 'object' then
            doc := jsonb_set(doc, '{wallet,equipped}',
                (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
                 from jsonb_each_text(doc -> 'wallet' -> 'equipped') e where items ? e.value));
        end if;
    end if;

    if settings.enforce_inventory then
        select count(distinct s) into species
        from (select doc -> 'companion' ->> 'speciesID' as s
              union all
              select r -> 'state' ->> 'speciesID'
              from jsonb_array_elements(case when jsonb_typeof(doc -> 'companionRoster' -> 'resting') = 'array'
                                             then doc -> 'companionRoster' -> 'resting' else '[]'::jsonb end) r) c
        where s is not null;
        if species > 1 + (select count(*) from public.owned_items o where o.user_id = me and o.item_id like 'companion:%') then
            raise exception 'invalid_companions' using errcode = '22023';
        end if;
    end if;

    if p_base_version = 0 then
        insert into public.player_saves (user_id, save) values (me, doc)
        on conflict (user_id) do nothing
        returning version into new_version;
    else
        update public.player_saves
        set save = doc, version = version + 1, updated_at = now()
        where user_id = me and version = p_base_version
        returning version into new_version;
    end if;
    if new_version is null then
        raise exception 'save_conflict' using errcode = 'P0001';
    end if;
    return new_version;
end;
$$;

revoke all on function public.put_player_save(jsonb, integer) from public, anon;
grant execute on function public.put_player_save(jsonb, integer) to authenticated;
