-- Contrails, and a free daily chest.
--
-- Contrails are four legendary trail items (drawn behind the walker) that join
-- the Mystery Box pool (same ids and rarities as ShopCatalog;
-- ServerWalletCatalogTests keeps them in step).
--
-- The daily chest opens once every 24 hours, timed by the server's clock, and
-- the server rolls its coins (15-100, bigger amounts rarer). Each claim is
-- paid as wallet.earned["daily-chest-<claim id>"], and put_player_save now
-- rebuilds those keys from daily_chest_claims, so an edited save can't add or
-- grow one. Safe to run again.

insert into public.mystery_box_prizes (item_id, kind, rarity, festival_start, festival_end) values
    ('rainbow-contrail', 'outfit', 'legendary', null, null),
    ('comet-contrail', 'outfit', 'legendary', null, null),
    ('stardust-contrail', 'outfit', 'legendary', null, null),
    ('bubble-contrail', 'outfit', 'legendary', null, null)
on conflict (item_id) do nothing;

-- When each player last opened their daily chest: one row per player, so the
-- 24-hour check and the claim are one atomic statement.
create table if not exists public.daily_chests (
    user_id uuid primary key references public.profiles (id) on delete cascade,
    last_claimed_at timestamptz not null
);

create table if not exists public.daily_chest_claims (
    id uuid primary key,
    user_id uuid not null references public.profiles (id) on delete cascade,
    coins integer not null check (coins between 15 and 100),
    claimed_at timestamptz not null default now()
);
create index if not exists daily_chest_claims_user on public.daily_chest_claims (user_id);

alter table public.daily_chests enable row level security;
alter table public.daily_chest_claims enable row level security;
revoke all on public.daily_chests, public.daily_chest_claims from public, anon, authenticated;

-- When the caller's daily chest is ready (now() when it already is), and the
-- server's time, so the app's countdown doesn't depend on the phone's clock.
create or replace function public.daily_chest_status()
returns table (ready_at timestamptz, server_now timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    return query
        select greatest(now(), coalesce((select d.last_claimed_at + interval '24 hours'
                                         from public.daily_chests d where d.user_id = auth.uid()), now())),
               now();
end;
$$;

-- Opens the daily chest. `p_request_id` makes retries safe: the same request
-- returns the same claim and pays once. Fails with daily_chest_not_ready
-- until 24 hours after the last claim.
create or replace function public.claim_daily_chest(p_request_id uuid)
returns table (claim_id uuid, coins integer, ready_at timestamptz, server_now timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    roll integer := floor(random() * 100)::integer;
    prize integer;
    claimed timestamptz;
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if p_request_id is null then
        raise exception 'invalid_request' using errcode = '22023';
    end if;
    if exists (select 1 from public.daily_chest_claims d where d.id = p_request_id and d.user_id = me) then
        return query
            select d.id, d.coins, d.claimed_at + interval '24 hours', now()
            from public.daily_chest_claims d where d.id = p_request_id;
        return;
    end if;
    -- Claims only if there was no claim in the last 24 hours. Two claims at
    -- once queue on the row, and the second then finds it too soon.
    insert into public.daily_chests as d (user_id, last_claimed_at) values (me, now())
    on conflict (user_id) do update set last_claimed_at = excluded.last_claimed_at
    where d.last_claimed_at <= now() - interval '24 hours'
    returning d.last_claimed_at into claimed;
    if claimed is null then
        raise exception 'daily_chest_not_ready' using errcode = 'P0001';
    end if;
    -- Weights out of 100, as DailyChest.odds in the app.
    select o.coins into prize
    from (select v.coins, sum(v.weight) over (order by v.coins) as upto
          from (values (15, 30), (20, 22), (25, 15), (30, 10), (40, 8), (50, 6), (60, 4), (75, 3), (100, 2)) as v (coins, weight)) o
    where o.upto > roll
    order by o.upto
    limit 1;
    insert into public.daily_chest_claims (id, user_id, coins, claimed_at) values (p_request_id, me, prize, claimed);
    -- The save gets the coins too, so they show on every phone.
    update public.player_saves s
    set save = jsonb_set(s.save, array['wallet', 'earned', 'daily-chest-' || p_request_id::text], to_jsonb(prize))
    where s.user_id = me and jsonb_typeof(s.save -> 'wallet' -> 'earned') = 'object';
    return query select p_request_id, prize, claimed + interval '24 hours', now();
end;
$$;

revoke all on function public.daily_chest_status(), public.claim_daily_chest(uuid) from public, anon;
grant execute on function public.daily_chest_status(), public.claim_daily_chest(uuid) to authenticated;

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
        -- Daily chests are paid only from the server's records: a save can't
        -- add one, change its coins or drop one.
        doc := jsonb_set(doc, '{wallet,earned}',
            (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
             from jsonb_each(doc -> 'wallet' -> 'earned') e where e.key not like 'daily-chest-%')
            || (select coalesce(jsonb_object_agg('daily-chest-' || d.id::text, d.coins), '{}'::jsonb)
                from public.daily_chest_claims d where d.user_id = me));

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
