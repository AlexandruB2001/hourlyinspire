-- Community goals for seasonal events: everyone's combined distance between
-- two dates. Only the total is returned, never anyone's individual numbers.
-- Days are capped at 25 km like the team ledger.

create function public.community_distance(p_start date, p_end date)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(sum(least(d.distance_meters, 25000)), 0)::bigint
    from public.daily_progress d
    where d.local_date between p_start and least(p_end, p_start + 62);
$$;

revoke all on function public.community_distance(date, date) from public, anon;
grant execute on function public.community_distance(date, date) to authenticated;
