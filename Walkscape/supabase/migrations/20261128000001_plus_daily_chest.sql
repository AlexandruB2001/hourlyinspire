-- Walkscape Plus members get a second daily chest each day.
--
-- The free chest works as before: one per local day. A member with an active
-- Plus subscription (a verified, unrefunded purchase in public.purchases that
-- hasn't expired) can open one more on the same day. The server checks the
-- subscription itself, so the app can't claim an extra chest it isn't owed.
-- Both chests pay into the same claims table, so a save can't make one up.
-- Safe to run again.

alter table public.daily_chests add column if not exists bonus_day date;

-- Whether the caller has Walkscape Plus right now.
create or replace function public.caller_has_plus()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (select 1 from public.purchases p
                   where p.user_id = auth.uid() and p.product_id like 'com.alexandrub.walkscape.plus.%'
                     and p.revoked_at is null and p.expires_at > now());
$$;

revoke all on function public.caller_has_plus() from public, anon, authenticated;

-- When the caller's next chest is ready: now() if the free one, or (for Plus)
-- the bonus one, is still unopened today; else the next midnight in `p_tz`.
create or replace function public.daily_chest_status(p_tz text)
returns table (ready_at timestamptz, server_now timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    local_today date;
    free_used boolean;
    bonus_used boolean;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    local_today := (now() at time zone p_tz)::date;
    select coalesce(d.last_day >= local_today, false), coalesce(d.bonus_day >= local_today, false)
    into free_used, bonus_used
    from public.daily_chests d where d.user_id = auth.uid();
    free_used := coalesce(free_used, false);
    bonus_used := coalesce(bonus_used, false);
    return query
        select case when not free_used or (not bonus_used and public.caller_has_plus())
                    then now()
                    else (local_today + 1)::timestamp at time zone p_tz end,
               now();
end;
$$;

-- Opens the caller's next chest for their local day in `p_tz`: the free one
-- first, then (for Plus members) the bonus one. `p_request_id` makes retries
-- safe. Fails with daily_chest_not_ready when nothing is left today.
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
    next_ready timestamptz;
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
    -- The free chest: one per local day, each for a later day than the last.
    -- Two claims at once queue on the row, and the second finds the day taken.
    insert into public.daily_chests as d (user_id, last_claimed_at, last_day) values (me, now(), local_today)
    on conflict (user_id) do update set last_claimed_at = excluded.last_claimed_at, last_day = excluded.last_day
    where d.last_day is null or d.last_day < excluded.last_day
    returning d.last_day into claimed;
    -- Plus: the bonus chest, once the free one is open.
    if claimed is null and public.caller_has_plus() then
        update public.daily_chests d set last_claimed_at = now(), bonus_day = local_today
        where d.user_id = me and (d.bonus_day is null or d.bonus_day < local_today)
        returning d.bonus_day into claimed;
    end if;
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
    select st.ready_at into next_ready from public.daily_chest_status(p_tz) st;
    return query select p_request_id, prize, next_ready, now();
end;
$$;

revoke all on function public.daily_chest_status(text), public.claim_daily_chest(uuid, text) from public, anon;
grant execute on function public.daily_chest_status(text), public.claim_daily_chest(uuid, text) to authenticated;
