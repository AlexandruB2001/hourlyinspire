-- The daily chest resets at the player's midnight instead of 24 hours after
-- the last one, and holds 25-150 coins.
--
-- The local day comes from the server's clock in the phone's time zone, so
-- changing the phone's clock does nothing. Each claim must be for a later
-- local day than the last, so switching time zones can move one chest earlier
-- but never adds one. Safe to run again.

alter table public.daily_chests add column if not exists last_day date;
alter table public.daily_chest_claims add column if not exists local_day date;

-- New coin range (find the old check by its definition, not its name). Claims
-- already made under the old 15-100 range stay valid.
do $$
declare
    c record;
begin
    for c in select con.conname from pg_constraint con
             where con.conrelid = 'public.daily_chest_claims'::regclass and con.contype = 'c'
               and pg_get_constraintdef(con.oid) like '%coins%'
    loop
        execute format('alter table public.daily_chest_claims drop constraint %I', c.conname);
    end loop;
end $$;
alter table public.daily_chest_claims add constraint daily_chest_claims_coins check (coins between 15 and 150);

drop function if exists public.daily_chest_status();
drop function if exists public.claim_daily_chest(uuid);

-- When the caller's daily chest is ready (now() when it already is: else the
-- next midnight in `p_tz`), and the server's time, so the app's countdown
-- doesn't depend on the phone's clock.
create or replace function public.daily_chest_status(p_tz text)
returns table (ready_at timestamptz, server_now timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    local_today date;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    local_today := (now() at time zone p_tz)::date;
    return query
        select case when exists (select 1 from public.daily_chests d
                                 where d.user_id = auth.uid() and d.last_day >= local_today)
                    then (local_today + 1)::timestamp at time zone p_tz
                    else now() end,
               now();
end;
$$;

-- Opens the daily chest for the caller's local day in `p_tz`. `p_request_id`
-- makes retries safe: the same request returns the same claim and pays once.
-- Fails with daily_chest_not_ready until the next local midnight.
create or replace function public.claim_daily_chest(p_request_id uuid, p_tz text)
returns table (claim_id uuid, coins integer, ready_at timestamptz, server_now timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    roll integer := floor(random() * 100)::integer;
    prize integer;
    local_today date;
    claimed date;
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if p_request_id is null or p_tz is null then
        raise exception 'invalid_request' using errcode = '22023';
    end if;
    local_today := (now() at time zone p_tz)::date;
    if exists (select 1 from public.daily_chest_claims d where d.id = p_request_id and d.user_id = me) then
        return query
            select d.id, d.coins, (coalesce(d.local_day, local_today) + 1)::timestamp at time zone p_tz, now()
            from public.daily_chest_claims d where d.id = p_request_id;
        return;
    end if;
    -- One claim per local day, each for a later day than the last. Two claims
    -- at once queue on the row, and the second then finds the day taken.
    insert into public.daily_chests as d (user_id, last_claimed_at, last_day) values (me, now(), local_today)
    on conflict (user_id) do update set last_claimed_at = excluded.last_claimed_at, last_day = excluded.last_day
    where d.last_day is null or d.last_day < excluded.last_day
    returning d.last_day into claimed;
    if claimed is null then
        raise exception 'daily_chest_not_ready' using errcode = 'P0001';
    end if;
    -- Weights out of 100, as DailyChest.odds in the app.
    select o.coins into prize
    from (select v.coins, sum(v.weight) over (order by v.coins) as upto
          from (values (25, 30), (30, 22), (40, 15), (50, 10), (60, 8), (75, 6), (100, 4), (125, 3), (150, 2)) as v (coins, weight)) o
    where o.upto > roll
    order by o.upto
    limit 1;
    insert into public.daily_chest_claims (id, user_id, coins, claimed_at, local_day)
    values (p_request_id, me, prize, now(), local_today);
    -- The save gets the coins too, so they show on every phone.
    update public.player_saves s
    set save = jsonb_set(s.save, array['wallet', 'earned', 'daily-chest-' || p_request_id::text], to_jsonb(prize))
    where s.user_id = me and jsonb_typeof(s.save -> 'wallet' -> 'earned') = 'object';
    return query select p_request_id, prize, (local_today + 1)::timestamp at time zone p_tz, now();
end;
$$;

revoke all on function public.daily_chest_status(text), public.claim_daily_chest(uuid, text) from public, anon;
grant execute on function public.daily_chest_status(text), public.claim_daily_chest(uuid, text) to authenticated;
