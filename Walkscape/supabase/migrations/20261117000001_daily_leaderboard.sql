-- A Daily Leaderboard across every player: the top walkers for a calendar day
-- plus the caller's own position.
--
-- A player appears to others only while both share_progress and
-- show_on_leaderboard are on. Blocked players (either way) never see each
-- other. Held days and distances estimated from steps aren't ranked. The caller
-- always gets their own row, even when hidden or not ranked yet. Safe to run again.

alter table public.profiles
    add column if not exists show_on_leaderboard boolean not null default true;

create or replace function public.set_show_on_leaderboard(p_show boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    update public.profiles set show_on_leaderboard = coalesce(p_show, true) where id = me;
    return coalesce(p_show, true);
end;
$$;

revoke all on function public.set_show_on_leaderboard(boolean) from public, anon;
grant execute on function public.set_show_on_leaderboard(boolean) to authenticated;

drop function if exists public.daily_leaderboard(date, integer);

create function public.daily_leaderboard(p_day date, p_limit integer)
returns table (user_id uuid, username text, avatar_id text, outfit text[], rank integer, distance_meters integer,
               is_me boolean, total integer, under_review boolean, shown boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    page_size integer := least(greatest(coalesce(p_limit, 3), 1), 100);
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if p_day is null or p_day > (now() at time zone 'utc')::date + 1 or p_day < (now() at time zone 'utc')::date - 1 then
        raise exception 'invalid_day' using errcode = '22023';
    end if;
    return query
        with eligible as (
            select p.id, p.username as name, p.avatar_id as avatar, p.outfit as worn,
                   d.distance_meters as meters, d.updated_at as at
            from public.daily_progress d
            join public.profiles p on p.id = d.user_id
            where d.local_date = p_day
              and d.distance_meters > 0
              and d.distance_source = 'recorded'
              and public.progress_review_reason(d.local_date, d.time_zone, d.steps, d.distance_meters, d.updated_at) is null
              and (p.id = me or (p.share_progress and p.show_on_leaderboard
                                 and not exists (select 1 from public.blocks b
                                                 where (b.blocker_id = me and b.blocked_id = p.id)
                                                    or (b.blocker_id = p.id and b.blocked_id = me))))
        ), ranked as (
            select e.*,
                   (rank() over (order by e.meters desc))::integer as place,
                   row_number() over (order by e.meters desc, e.at, e.name) as position,
                   (count(*) over ())::integer as players
            from eligible e
        ), everyone as (
            select count(*)::integer as players from ranked
        )
        select r.id, r.name, r.avatar, r.worn, r.place, r.meters, r.id = me, r.players, false,
               case when r.id = me then (select p.show_on_leaderboard from public.profiles p where p.id = me) else true end
        from ranked r
        where r.position <= page_size or r.id = me
        union all
        select p.id, p.username, p.avatar_id, p.outfit, null::integer, coalesce(d.distance_meters, 0), true,
               (select e.players from everyone e),
               coalesce(public.progress_review_reason(d.local_date, d.time_zone, d.steps, d.distance_meters,
                                                      d.updated_at) is not null, false),
               p.show_on_leaderboard
        from public.profiles p
        left join public.daily_progress d on d.user_id = p.id and d.local_date = p_day
        where p.id = me and not exists (select 1 from ranked r where r.id = me)
        order by 5 nulls last, 6 desc, 2;
end;
$$;

revoke all on function public.daily_leaderboard(date, integer) from public, anon;
grant execute on function public.daily_leaderboard(date, integer) to authenticated;
