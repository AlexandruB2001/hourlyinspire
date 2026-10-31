-- Server-authoritative spending (wallet phase A).
--
-- * Prices live in coin_prices. Mystery Boxes and companion adoptions are
--   bought through open_mystery_box() and adopt_companion(), which charge
--   through charge_coins() (atomic, idempotent per request) and record what
--   was bought in owned_items, the server's inventory.
-- * The Mystery Box is rolled here, from mystery_box_prizes (the same pool,
--   weights and festival windows as MysteryBox.prizes(on:) in the app; a
--   Swift test keeps the two in step).
-- * Rewarded ads can be verified by AdMob server-side verification: the
--   admob-ssv edge function checks Google's signature and records each ad in
--   ad_rewards (record_ad_reward, service role only).
-- * put_player_save always adds the server's inventory to the saved wallet.
--   Two switches in wallet_settings, both off until every tester runs an app
--   build that buys through the server:
--     enforce_inventory: Mystery-Box-only items the server didn't grant are
--       removed from saves, and a save can't hold more companions than the
--       first pick plus server adoptions. Turn on with
--       select public.start_wallet_enforcement();
--     verify_ad_rewards: ad coins in saves must match a verified ad.
--
-- Still the app's word until phase B: coins earned from walking, chests,
-- quests, levels and referrals, and items from festival and level rewards.

create table public.wallet_settings (
    id boolean primary key default true,
    enforce_inventory boolean not null default false,
    verify_ad_rewards boolean not null default false,
    constraint wallet_settings_single check (id)
);
insert into public.wallet_settings default values;

create table public.coin_prices (
    item text primary key,
    coins integer not null,
    constraint coin_prices_positive check (coins > 0)
);
insert into public.coin_prices (item, coins) values
    ('mystery-box', 150),
    ('companion-adoption', 1000),
    ('rewarded-ad', 15);

-- Everything the Mystery Box can give. Festival accessories (festival_start /
-- festival_end as MMDD, wrapping over New Year) stay out of the box while
-- their festival runs, when they can only be earned.
create table public.mystery_box_prizes (
    item_id text primary key,
    kind text not null,
    rarity text not null,
    festival_start smallint,
    festival_end smallint,
    constraint mystery_box_prizes_kind check (kind in ('outfit', 'accessory')),
    constraint mystery_box_prizes_rarity check (rarity in ('common', 'rare', 'epic', 'legendary')),
    constraint mystery_box_prizes_festival check ((festival_start is null) = (festival_end is null))
);
insert into public.mystery_box_prizes (item_id, kind, rarity, festival_start, festival_end) values
    ('straw-hat', 'outfit', 'common', null, null),
    ('red-beanie', 'outfit', 'common', null, null),
    ('bucket-hat', 'outfit', 'common', null, null),
    ('trail-cap', 'outfit', 'common', null, null),
    ('flower-crown', 'outfit', 'rare', null, null),
    ('top-hat', 'outfit', 'rare', null, null),
    ('explorer-helmet', 'outfit', 'rare', null, null),
    ('wizard-hat', 'outfit', 'epic', null, null),
    ('viking-helmet', 'outfit', 'epic', null, null),
    ('golden-crown', 'outfit', 'legendary', null, null),
    ('beret', 'outfit', 'common', null, null),
    ('cat-beanie', 'outfit', 'rare', null, null),
    ('frog-hat', 'outfit', 'rare', null, null),
    ('halo', 'outfit', 'legendary', null, null),
    ('ski-goggles', 'outfit', 'common', null, null),
    ('monocle', 'outfit', 'rare', null, null),
    ('star-glasses', 'outfit', 'epic', null, null),
    ('round-glasses', 'outfit', 'common', null, null),
    ('sunglasses', 'outfit', 'common', null, null),
    ('heart-glasses', 'outfit', 'rare', null, null),
    ('cherry-scarf', 'outfit', 'common', null, null),
    ('ocean-scarf', 'outfit', 'common', null, null),
    ('mint-scarf', 'outfit', 'common', null, null),
    ('candy-scarf', 'outfit', 'rare', null, null),
    ('sunset-scarf', 'outfit', 'rare', null, null),
    ('rainbow-scarf', 'outfit', 'epic', null, null),
    ('bandana', 'outfit', 'common', null, null),
    ('bow-tie', 'outfit', 'common', null, null),
    ('flower-lei', 'outfit', 'rare', null, null),
    ('aurora-scarf', 'outfit', 'legendary', null, null),
    ('red-sneakers', 'outfit', 'common', null, null),
    ('blue-wellies', 'outfit', 'common', null, null),
    ('white-sneakers', 'outfit', 'common', null, null),
    ('moss-hikers', 'outfit', 'rare', null, null),
    ('cloud-walkers', 'outfit', 'rare', null, null),
    ('yellow-wellies', 'outfit', 'common', null, null),
    ('roller-skates', 'outfit', 'epic', null, null),
    ('golden-boots', 'outfit', 'epic', null, null),
    ('explorer-pack', 'outfit', 'rare', null, null),
    ('bindle', 'outfit', 'common', null, null),
    ('turtle-shell', 'outfit', 'rare', null, null),
    ('guitar', 'outfit', 'epic', null, null),
    ('hero-cape', 'outfit', 'epic', null, null),
    ('fairy-wings', 'outfit', 'epic', null, null),
    ('phoenix-wings', 'outfit', 'legendary', null, null),
    ('pet-straw-hat', 'accessory', 'common', null, null),
    ('pet-beanie', 'accessory', 'common', null, null),
    ('pet-flower-crown', 'accessory', 'rare', null, null),
    ('pet-red-scarf', 'accessory', 'common', null, null),
    ('pet-blue-scarf', 'accessory', 'common', null, null),
    ('pet-backpack', 'accessory', 'rare', null, null),
    ('pet-cape', 'accessory', 'epic', null, null),
    ('pet-pumpkin-hat', 'accessory', 'epic', 1015, 1112),
    ('pet-snow-hat', 'accessory', 'epic', 1215, 112),
    ('pet-petal-crown', 'accessory', 'epic', 320, 417),
    ('pet-sailor-hat', 'accessory', 'epic', 620, 718),
    ('pet-star-cape', 'accessory', 'epic', 805, 825);

-- The server's inventory: items and companions bought through it (or carried
-- over from saves when enforcement starts). Companions are 'companion:<id>'.
create table public.owned_items (
    user_id uuid not null references public.profiles (id) on delete cascade,
    item_id text not null,
    source text not null,
    acquired_at timestamptz not null default now(),
    primary key (user_id, item_id),
    constraint owned_items_source check (source in ('mystery-box', 'adoption', 'legacy'))
);

create table public.mystery_box_opens (
    user_id uuid not null references public.profiles (id) on delete cascade,
    request_id uuid not null,
    item_id text not null,
    charge_key text not null,
    opened_at timestamptz not null default now(),
    primary key (user_id, request_id)
);

create table public.ad_rewards (
    transaction_id text primary key,
    user_id uuid not null references public.profiles (id) on delete cascade,
    reward_id text not null,
    coins integer not null,
    ad_unit text not null,
    rewarded_at timestamptz not null default now(),
    unique (user_id, reward_id)
);

alter table public.wallet_settings enable row level security;
alter table public.coin_prices enable row level security;
alter table public.mystery_box_prizes enable row level security;
alter table public.owned_items enable row level security;
alter table public.mystery_box_opens enable row level security;
alter table public.ad_rewards enable row level security;
revoke all on public.wallet_settings, public.coin_prices, public.mystery_box_prizes, public.owned_items,
    public.mystery_box_opens, public.ad_rewards from anon, authenticated;

-- Mystery Box ---------------------------------------------------------------

-- Prizes `p_user` can still win on a day (`p_md` = month * 100 + day):
-- not owned on the server or in their save, and not in a running festival.
create function public.mystery_box_candidates(p_user uuid, p_md integer, p_save_items jsonb)
returns setof public.mystery_box_prizes
language sql
stable
security definer
set search_path = ''
as $$
    select z.*
    from public.mystery_box_prizes z
    where not exists (select 1 from public.owned_items o where o.user_id = p_user and o.item_id = z.item_id)
      and not coalesce(p_save_items, '[]'::jsonb) ? z.item_id
      and not (z.festival_start is not null
               and case when z.festival_start <= z.festival_end then p_md between z.festival_start and z.festival_end
                        else p_md >= z.festival_start or p_md <= z.festival_end end);
$$;

-- Buys and opens a Mystery Box. `p_request_id` makes retries safe: the same
-- request returns the same prize and charges once. `p_day` is the player's
-- local day (festivals).
create function public.open_mystery_box(p_request_id uuid, p_day date)
returns table (item_id text, kind text, rarity text, charge_key text, coins integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    price integer;
    doc jsonb;
    md integer;
    roll double precision := random();
    picked_rarity text;
    prize text;
    key text := 'box-' || p_request_id::text;
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if p_request_id is null or p_day is null
       or p_day > (now() at time zone 'utc')::date + 1 or p_day < (now() at time zone 'utc')::date - 1 then
        raise exception 'invalid_request' using errcode = '22023';
    end if;
    select c.coins into price from public.coin_prices c where c.item = 'mystery-box';
    -- One purchase at a time per player: the save row is the lock.
    select s.save into doc from public.player_saves s where s.user_id = me for update;
    if exists (select 1 from public.mystery_box_opens o where o.user_id = me and o.request_id = p_request_id) then
        return query
            select o.item_id, z.kind, z.rarity, o.charge_key, price
            from public.mystery_box_opens o join public.mystery_box_prizes z on z.item_id = o.item_id
            where o.user_id = me and o.request_id = p_request_id;
        return;
    end if;
    if doc is null then
        raise exception 'no_cloud_save' using errcode = 'P0002';
    end if;
    md := extract(month from p_day)::integer * 100 + extract(day from p_day)::integer;
    -- A rarity by weight (among rarities with prizes left), then a prize evenly.
    with weights as (
        select c.rarity,
               case c.rarity when 'common' then 60 when 'rare' then 28 when 'epic' then 10 else 2 end as weight
        from public.mystery_box_candidates(me, md, doc -> 'wallet' -> 'ownedItemIDs') c
        group by c.rarity
    ), ladder as (
        select w.rarity, sum(w.weight) over (order by w.weight desc, w.rarity) as upto, sum(w.weight) over () as total
        from weights w
    )
    select l.rarity into picked_rarity from ladder l where l.upto > roll * l.total order by l.upto limit 1;
    if picked_rarity is null then
        raise exception 'sold_out' using errcode = 'P0002';
    end if;
    select c.item_id into prize
    from public.mystery_box_candidates(me, md, doc -> 'wallet' -> 'ownedItemIDs') c
    where c.rarity = picked_rarity
    order by random()
    limit 1;
    perform public.charge_coins(me, key, price);
    insert into public.owned_items (user_id, item_id, source) values (me, prize, 'mystery-box');
    insert into public.mystery_box_opens (user_id, request_id, item_id, charge_key) values (me, p_request_id, prize, key);
    -- The save gets the prize too, so it shows on every phone.
    update public.player_saves s
    set save = jsonb_set(s.save, '{wallet,ownedItemIDs}',
                         coalesce(s.save -> 'wallet' -> 'ownedItemIDs', '[]'::jsonb) || to_jsonb(prize))
    where s.user_id = me and jsonb_typeof(s.save -> 'wallet') = 'object';
    return query select z.item_id, z.kind, z.rarity, key, price from public.mystery_box_prizes z where z.item_id = prize;
end;
$$;

-- Companions ----------------------------------------------------------------

-- Adopts another companion species. Charged once per species, ever.
create function public.adopt_companion(p_species text)
returns table (charge_key text, coins integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    price integer;
    key text := 'companion-' || coalesce(p_species, '');
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    -- CompanionCatalog.starters in the app.
    if p_species is null or p_species not in ('mossling', 'emberfox', 'moonmoth') then
        raise exception 'unknown_companion' using errcode = '22023';
    end if;
    select c.coins into price from public.coin_prices c where c.item = 'companion-adoption';
    perform public.charge_coins(me, key, price);
    insert into public.owned_items (user_id, item_id, source) values (me, 'companion:' || p_species, 'adoption')
    on conflict do nothing;
    return query select key, price;
end;
$$;

-- Rewarded ads --------------------------------------------------------------

-- Records one verified rewarded ad (called by the admob-ssv edge function with
-- the service role). At most 6 a UTC day per player, twice the app's daily
-- limit so local midnights never lose a legitimate ad.
create function public.record_ad_reward(p_user uuid, p_transaction_id text, p_reward_id text, p_ad_unit text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    coins integer;
begin
    if p_transaction_id is null or p_transaction_id !~ '^[A-Za-z0-9_-]{1,128}$'
       or p_reward_id is null or p_reward_id !~ '^[A-Za-z0-9-]{1,64}$' then
        return 'invalid';
    end if;
    if not exists (select 1 from public.profiles p where p.id = p_user) then
        return 'unknown_user';
    end if;
    if exists (select 1 from public.ad_rewards a where a.transaction_id = p_transaction_id) then
        return 'duplicate';
    end if;
    perform pg_advisory_xact_lock(hashtext('ad-rewards-' || p_user::text));
    if (select count(*) from public.ad_rewards a
        where a.user_id = p_user and a.rewarded_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc') >= 6 then
        return 'daily_limit';
    end if;
    select c.coins into coins from public.coin_prices c where c.item = 'rewarded-ad';
    insert into public.ad_rewards (transaction_id, user_id, reward_id, coins, ad_unit)
    values (p_transaction_id, p_user, p_reward_id, coins, left(coalesce(p_ad_unit, ''), 128))
    on conflict do nothing;
    return 'recorded';
end;
$$;

-- Saves ---------------------------------------------------------------------

-- Stores the caller's save if `p_base_version` is the version they last read
-- (0 when they had none). Recorded charges and the server's inventory are
-- written into the wallet; with enforcement on, items and ad coins the server
-- can't account for are removed. Returns the new version.
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
        raise exception 'save_conflict' using errcode = '40001';
    end if;
    return new_version;
end;
$$;

-- Turns on inventory enforcement once every tester runs a build that buys
-- through the server. Carries over what saves already hold: Mystery Box items
-- and companions adopted on the phone (their 'companion-<id>' spent keys).
-- Run it in the SQL editor; nobody signed in can call it.
create function public.start_wallet_enforcement()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.owned_items (user_id, item_id, source)
    select s.user_id, v.value, 'legacy'
    from public.player_saves s
    cross join lateral jsonb_array_elements_text(
        case when jsonb_typeof(s.save -> 'wallet' -> 'ownedItemIDs') = 'array'
             then s.save -> 'wallet' -> 'ownedItemIDs' else '[]'::jsonb end) v
    where exists (select 1 from public.mystery_box_prizes z where z.item_id = v.value)
    on conflict do nothing;
    insert into public.owned_items (user_id, item_id, source)
    select s.user_id, 'companion:' || substr(e.key, 11), 'legacy'
    from public.player_saves s
    cross join lateral jsonb_each(case when jsonb_typeof(s.save -> 'wallet' -> 'spent') = 'object'
                                       then s.save -> 'wallet' -> 'spent' else '{}'::jsonb end) e
    where e.key in ('companion-mossling', 'companion-emberfox', 'companion-moonmoth')
    on conflict do nothing;
    update public.wallet_settings set enforce_inventory = true;
end;
$$;

revoke all on function public.mystery_box_candidates(uuid, integer, jsonb), public.record_ad_reward(uuid, text, text, text),
    public.start_wallet_enforcement()
from public, anon, authenticated;
revoke all on function public.open_mystery_box(uuid, date), public.adopt_companion(text) from public, anon;
grant execute on function public.open_mystery_box(uuid, date), public.adopt_companion(text) to authenticated;
revoke all on function public.put_player_save(jsonb, integer) from public, anon;
grant execute on function public.put_player_save(jsonb, integer) to authenticated;
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant execute on function public.record_ad_reward(uuid, text, text, text) to service_role;
    end if;
end $$;
