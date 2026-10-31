-- Repair: 20261110000001 was applied before 20261109000001, and a run of
-- 20261109000001 was partly applied. Safe to run whatever is already there:
-- applies 20261109000001 (fixed), then restores 20261110000001's put_player_save.

-- Fair distance and a server ledger for coin charges.
--
-- Distance: no daily ceiling on legitimate walking.
-- * The 25 km per-day cap on team contributions and community goals is gone.
--   A marathon, an ultra or a long hike counts in full for Teams, Groups and
--   community events, as it already did for the Journey.
-- * The hard limits on a day become physical ones: 350 km and 300,000 steps,
--   above the 24-hour running world record (about 320 km). Anything over that
--   is malformed and rejected; nothing legitimate is.
-- * Instead of truncating, every day is checked for plausibility when it is
--   uploaded (progress_review_reason). A day that couldn't have been walked
--   (more than 2.5 m a step, or faster than 25 km/h on average since local
--   midnight when it was uploaded) is held out of competitive totals (team
--   ledger, team week standings, group leaderboards, community goals) until a
--   later upload is plausible. It is never changed or deleted, and it still
--   counts on the player's own Journey. Held and very long days are logged in
--   progress_flags for review.
--
-- Coins: charges for creating teams and groups are recorded in coin_charges,
-- which only the server writes. charge_coins() takes idempotency and the
-- spent total from it, and put_player_save() writes every recorded charge back
-- into the saved wallet, so a client can't refund a fee by editing its save.
-- Saved wallets must be well formed. The earned side of the wallet is still
-- computed by the app (see docs/BACKEND.md, "Wallet").

-- Distance -------------------------------------------------------------------

-- Old limits are found by what they check, in case their names differ on the
-- live project (as the team ledger's did).
do $$
declare
    old_check text;
begin
    for old_check in
        select c.conname from pg_constraint c
        where c.conrelid = 'public.daily_progress'::regclass and c.contype = 'c'
          and (pg_get_constraintdef(c.oid) like '%steps%' or pg_get_constraintdef(c.oid) like '%distance_meters%')
    loop
        execute format('alter table public.daily_progress drop constraint %I', old_check);
    end loop;
end $$;

alter table public.daily_progress
    add constraint daily_progress_steps_range check (steps between 0 and 300000),
    add constraint daily_progress_distance_range check (distance_meters between 0 and 350000);

-- The old 25 km check is found by what it checks: its name differs between
-- the live project and a fresh database.
do $$
declare
    old_check text;
begin
    for old_check in
        select c.conname from pg_constraint c
        where c.conrelid = 'public.team_contributions'::regclass and c.contype = 'c'
          and pg_get_constraintdef(c.oid) like '%meters%'
    loop
        execute format('alter table public.team_contributions drop constraint %I', old_check);
    end loop;
end $$;

alter table public.team_contributions
    add constraint team_contributions_meters_range check (meters between 0 and 350000);

-- Why a day can't count towards competitive totals yet, or null when it can.
-- Short days (under 15 km) are never held. `p_at` is when the day was
-- uploaded (daily_progress.updated_at, set by the server).
create or replace function public.progress_review_reason(p_local_date date, p_time_zone text, p_steps integer,
                                              p_meters integer, p_at timestamptz)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
    local_midnight timestamptz;
begin
    if p_meters < 15000 then
        return null;
    end if;
    -- The longest human strides are about 2.5 m (sprinting).
    if p_meters > p_steps::numeric * 2.5 then
        return 'stride';
    end if;
    begin
        local_midnight := p_local_date::timestamp at time zone p_time_zone;
    exception when others then
        -- Unknown zone: assume the earliest midnight (UTC+14), the most lenient.
        local_midnight := p_local_date::timestamp at time zone 'Pacific/Kiritimati';
    end;
    -- Faster than 25 km/h on average since midnight (elite marathon pace is
    -- about 21 km/h), with 5 km of slack for clock and time zone edges.
    if p_meters > 25000 * greatest(extract(epoch from p_at - local_midnight) / 3600, 0) + 5000 then
        return 'too_fast';
    end if;
    return null;
end;
$$;

-- Held and very long days, for review. Private: nobody signed in can read it.
create table if not exists public.progress_flags (
    user_id uuid not null references public.profiles (id) on delete cascade,
    local_date date not null,
    reason text not null,
    steps integer not null,
    distance_meters integer not null,
    flagged_at timestamptz not null default now(),
    primary key (user_id, local_date, reason),
    constraint progress_flags_reason check (reason in ('stride', 'too_fast', 'very_long'))
);

alter table public.progress_flags enable row level security;
revoke all on public.progress_flags from anon, authenticated;

create or replace function public.log_progress_flags()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    why text := public.progress_review_reason(new.local_date, new.time_zone, new.steps, new.distance_meters, new.updated_at);
begin
    if why is null and new.distance_meters >= 100000 then
        why := 'very_long'; -- legitimate, counted in full, but worth a look
    end if;
    if why is not null then
        insert into public.progress_flags (user_id, local_date, reason, steps, distance_meters)
        values (new.user_id, new.local_date, why, new.steps, new.distance_meters)
        on conflict (user_id, local_date, reason) do update
            set steps = excluded.steps, distance_meters = excluded.distance_meters, flagged_at = now();
    end if;
    return null;
end;
$$;

drop trigger if exists daily_progress_flags on public.daily_progress;
create trigger daily_progress_flags
    after insert or update on public.daily_progress
    for each row execute function public.log_progress_flags();

revoke all on function public.log_progress_flags() from public, anon, authenticated;
revoke all on function public.progress_review_reason(date, text, integer, integer, timestamptz) from public, anon;
grant execute on function public.progress_review_reason(date, text, integer, integer, timestamptz) to authenticated;

-- Team ledger: full days, plausible days only (a held day is credited once a
-- later upload of it is plausible).
create or replace function public.sync_team_contributions()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    team uuid := public.caller_team_id();
begin
    if team is null then
        return;
    end if;
    insert into public.team_contributions (user_id, local_date, team_id, meters)
    select d.user_id, d.local_date, team, d.distance_meters
    from public.team_members m
    join public.profiles p on p.id = m.user_id and p.share_progress
    join public.daily_progress d on d.user_id = m.user_id
        and d.local_date >= (m.joined_at at time zone 'utc')::date
        and d.local_date <= (now() at time zone 'utc')::date + 1
    where m.team_id = team
      and public.progress_review_reason(d.local_date, d.time_zone, d.steps, d.distance_meters, d.updated_at) is null
    on conflict (user_id, local_date) do update
        set meters = greatest(public.team_contributions.meters, excluded.meters), credited_at = now()
        where public.team_contributions.team_id = excluded.team_id
          and excluded.meters > public.team_contributions.meters;
end;
$$;

-- Distance a member may show to their team (week totals and team standings):
-- nothing while sharing is off; held days don't count.
create or replace function public.shared_meters(p_user_id uuid, p_from date, p_to date)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
    select case when p.share_progress or p.id = auth.uid()
                then (select coalesce(sum(d.distance_meters), 0) from public.daily_progress d
                      where d.user_id = p.id and d.local_date between p_from and p_to
                        and public.progress_review_reason(d.local_date, d.time_zone, d.steps, d.distance_meters,
                                                          d.updated_at) is null)
           end
    from public.profiles p
    where p.id = p_user_id;
$$;

-- Community goals: everyone's full, plausible days.
create or replace function public.community_distance(p_start date, p_end date)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(sum(d.distance_meters), 0)::bigint
    from public.daily_progress d
    where d.local_date between p_start and least(p_end, p_start + 62)
      and public.progress_review_reason(d.local_date, d.time_zone, d.steps, d.distance_meters, d.updated_at) is null;
$$;

-- Group leaderboards: full days, plausible days only. `under_review` tells the
-- caller (only about themselves) that one of their days is held.
drop function if exists public.group_leaderboard(uuid, text, date, integer, integer);

create function public.group_leaderboard(p_group_id uuid, p_period text, p_day date, p_limit integer, p_offset integer)
returns table (user_id uuid, username text, avatar_id text, rank integer, steps integer, distance_meters integer,
               estimated boolean, sharing boolean, updated_at timestamptz, is_me boolean, total integer,
               under_review boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    first_day date;
    page_size integer := least(greatest(coalesce(p_limit, 10), 1), 100);
    skip integer := greatest(coalesce(p_offset, 0), 0);
begin
    perform public.require_group_role(p_group_id, false);
    if p_day is null or p_day > (now() at time zone 'utc')::date + 1 or p_day < (now() at time zone 'utc')::date - 1 then
        raise exception 'invalid_day' using errcode = '22023';
    end if;
    if p_period = 'day' then
        first_day := p_day;
    elsif p_period = 'week' then
        first_day := p_day - (extract(isodow from p_day)::integer - 1);
    else
        raise exception 'invalid_period' using errcode = '22023';
    end if;
    return query
        with days as (
            select d.user_id, d.steps, d.distance_meters, d.distance_source, d.updated_at,
                   public.progress_review_reason(d.local_date, d.time_zone, d.steps, d.distance_meters,
                                                 d.updated_at) is not null as held
            from public.group_members m
            join public.daily_progress d on d.user_id = m.user_id and d.local_date between first_day and p_day
            where m.group_id = p_group_id
        ), totals as (
            select m.user_id, p.username, p.avatar_id, p.share_progress as sharing,
                   (sum(d.steps) filter (where not d.held))::integer as steps,
                   (sum(d.distance_meters) filter (where not d.held))::integer as meters,
                   coalesce(bool_or(d.distance_source = 'estimatedFromSteps' and not d.held), false) as estimated,
                   coalesce(bool_or(d.held), false) as held,
                   max(d.updated_at) as updated_at
            from public.group_members m
            join public.profiles p on p.id = m.user_id
            left join days d on d.user_id = m.user_id and p.share_progress
            where m.group_id = p_group_id
            group by m.user_id, p.username, p.avatar_id, p.share_progress
        ), ranked as (
            select t.*,
                   (rank() over (order by t.meters desc nulls last, t.steps desc nulls last))::integer as place,
                   row_number() over (order by t.meters desc nulls last, t.steps desc nulls last, t.username) as position,
                   (count(*) over ())::integer as members
            from totals t
        )
        select r.user_id, r.username, r.avatar_id, r.place,
               case when r.sharing then coalesce(r.steps, 0) end, case when r.sharing then coalesce(r.meters, 0) end,
               r.estimated, r.sharing, r.updated_at, r.user_id = auth.uid(), r.members,
               r.user_id = auth.uid() and r.held
        from ranked r
        where (r.position > skip and r.position <= skip + page_size) or r.user_id = auth.uid()
        order by r.position;
end;
$$;

revoke all on function public.group_leaderboard(uuid, text, date, integer, integer) from public, anon;
grant execute on function public.group_leaderboard(uuid, text, date, integer, integer) to authenticated;

-- Coins ----------------------------------------------------------------------

create table if not exists public.coin_charges (
    user_id uuid not null references public.profiles (id) on delete cascade,
    key text not null,
    amount integer not null,
    charged_at timestamptz not null default now(),
    primary key (user_id, key),
    constraint coin_charges_amount check (amount > 0)
);

alter table public.coin_charges enable row level security;
revoke all on public.coin_charges from anon, authenticated;

-- Charges made before this migration live only in the saves.
insert into public.coin_charges (user_id, key, amount)
select s.user_id, e.key, e.value::integer
from public.player_saves s
cross join lateral jsonb_each_text(coalesce(s.save -> 'wallet' -> 'spent', '{}'::jsonb)) e
where jsonb_typeof(s.save -> 'wallet' -> 'spent') = 'object'
  and e.key ~ '^(team|group)-[0-9a-f-]{36}$' and e.value ~ '^[0-9]{1,9}$' and e.value::integer > 0
on conflict do nothing;

-- A saved wallet's earned and spent maps hold whole, non-negative amounts
-- (each well under what any single reward or purchase could be).
create or replace function public.valid_wallet(p_save jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select jsonb_typeof(p_save -> 'wallet') is null
        or (jsonb_typeof(p_save -> 'wallet') = 'object'
            and not exists (
                select 1
                from (values (p_save -> 'wallet' -> 'earned'), (p_save -> 'wallet' -> 'spent')) as maps (m)
                where m is not null
                  and (jsonb_typeof(m) <> 'object'
                       or exists (select 1 from jsonb_each(m) e
                                  where jsonb_typeof(e.value) <> 'number'
                                     or e.value::numeric < 0
                                     or e.value::numeric > 100000
                                     or e.value::numeric <> trunc(e.value::numeric)))));
$$;

-- Charges `p_amount` once per `p_key`: records it in coin_charges and in the
-- cloud save's wallet, in the caller's transaction (with the team or group it
-- pays for). The balance is the save's earned total minus everything spent,
-- counting each recorded charge at least at its recorded amount.
create or replace function public.charge_coins(p_user uuid, p_key text, p_amount integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    doc jsonb;
    earned bigint;
    spent bigint;
begin
    select s.save into doc from public.player_saves s where s.user_id = p_user for update;
    if doc is null then
        raise exception 'no_cloud_save' using errcode = 'P0002';
    end if;
    if coalesce((doc ->> 'schema')::integer, 0) < 2 or jsonb_typeof(doc -> 'wallet' -> 'earned') is distinct from 'object' then
        raise exception 'update_app' using errcode = '22023';
    end if;
    if exists (select 1 from public.coin_charges c where c.user_id = p_user and c.key = p_key)
       or coalesce(doc -> 'wallet' -> 'spent', '{}'::jsonb) ? p_key then
        return; -- already paid
    end if;
    select coalesce(sum(value::bigint), 0) into earned from jsonb_each_text(doc -> 'wallet' -> 'earned');
    select coalesce(sum(greatest(coalesce(s.value::bigint, 0), coalesce(c.amount, 0))), 0) into spent
    from jsonb_each_text(coalesce(doc -> 'wallet' -> 'spent', '{}'::jsonb)) s
    full join (select c.key, c.amount from public.coin_charges c where c.user_id = p_user) c on c.key = s.key;
    if earned - spent < p_amount then
        raise exception 'insufficient_coins' using errcode = '22023';
    end if;
    insert into public.coin_charges (user_id, key, amount) values (p_user, p_key, p_amount);
    doc := jsonb_set(doc, '{wallet,spent}', coalesce(doc -> 'wallet' -> 'spent', '{}'::jsonb) || jsonb_build_object(p_key, p_amount));
    doc := jsonb_set(doc, '{wallet,coins}', to_jsonb(earned - spent - p_amount));
    update public.player_saves set save = doc, version = version + 1, updated_at = now() where user_id = p_user;
end;
$$;

revoke all on function public.valid_wallet(jsonb), public.charge_coins(uuid, text, integer) from public, anon, authenticated;


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

revoke all on function public.put_player_save(jsonb, integer) from public, anon;
grant execute on function public.put_player_save(jsonb, integer) to authenticated;
