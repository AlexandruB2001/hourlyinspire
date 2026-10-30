-- Team ledger and Campfire.
--
-- Before this migration a team's total was summed live from its *current*
-- members, so it went backwards when someone left and expeditions could
-- un-complete. Now every walker's day is credited to one team, once, in
-- team_contributions:
--
-- * primary key (user_id, local_date): a day can only ever count for one
--   team, so switching teams can't count the same walk twice;
-- * only days from the day you joined, only while sharing, capped at 25 km;
-- * when you leave, your past days stay with the team; if the team is
--   deleted the rows keep their (user, day) slot with team_id null.
--
-- team_campsites stores the decorations members placed. The Campfire level
-- itself is derived from the ledger total (see Campfire.swift).

create table public.team_contributions (
    user_id uuid not null references public.profiles (id) on delete cascade,
    local_date date not null,
    team_id uuid references public.teams (id) on delete set null,
    meters integer not null check (meters between 0 and 25000),
    credited_at timestamptz not null default now(),
    primary key (user_id, local_date)
);

create index team_contributions_team_idx on public.team_contributions (team_id);

create table public.team_campsites (
    team_id uuid primary key references public.teams (id) on delete cascade,
    decorations text[] not null default '{}',
    updated_at timestamptz not null default now(),
    constraint team_campsites_size check (cardinality(decorations) <= 8)
);

alter table public.team_contributions enable row level security;
alter table public.team_campsites enable row level security;
revoke all on public.team_contributions, public.team_campsites from anon, authenticated;

-- Credits the caller's team with its members' shared daily totals since each
-- joined. Safe to call on every refresh: a day already credited (to any team)
-- only ever grows, and only for the same team.
create function public.sync_team_contributions()
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
    select d.user_id, d.local_date, team, least(d.distance_meters, 25000)
    from public.team_members m
    join public.profiles p on p.id = m.user_id and p.share_progress
    join public.daily_progress d on d.user_id = m.user_id
        and d.local_date >= (m.joined_at at time zone 'utc')::date
        and d.local_date <= (now() at time zone 'utc')::date + 1
    where m.team_id = team
    on conflict (user_id, local_date) do update
        set meters = greatest(public.team_contributions.meters, excluded.meters), credited_at = now()
        where public.team_contributions.team_id = excluded.team_id
          and excluded.meters > public.team_contributions.meters;
end;
$$;

-- my_team() now reports the ledger total, which never goes down.
create or replace function public.my_team()
returns table (id uuid, name text, join_code text, member_count integer, is_owner boolean,
               created_at timestamptz, total_meters bigint)
language sql
stable
security definer
set search_path = ''
as $$
    select t.id, t.name, t.join_code,
           (select count(*)::integer from public.team_members m where m.team_id = t.id),
           t.owner_id = auth.uid(),
           t.created_at,
           (select coalesce(sum(c.meters), 0) from public.team_contributions c where c.team_id = t.id)::bigint
    from public.teams t
    where t.id = public.caller_team_id();
$$;

-- Everyone who has contributed to the caller's team, including people who
-- have since left, with their total.
create function public.team_contribution_totals()
returns table (user_id uuid, username text, avatar_id text, meters bigint, is_member boolean)
language sql
stable
security definer
set search_path = ''
as $$
    select c.user_id, p.username, p.avatar_id, sum(c.meters)::bigint,
           exists (select 1 from public.team_members m where m.team_id = c.team_id and m.user_id = c.user_id)
    from public.team_contributions c
    join public.profiles p on p.id = c.user_id
    where c.team_id = public.caller_team_id()
    group by c.user_id, p.username, p.avatar_id, c.team_id
    order by 4 desc;
$$;

create function public.my_campsite()
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce((select s.decorations from public.team_campsites s where s.team_id = public.caller_team_id()), '{}');
$$;

-- Places the team's decorations (any member may rearrange them). Which ones
-- are unlocked is decided by the app from the Campfire level.
create function public.set_campsite_decorations(p_decorations text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    team uuid := public.caller_team_id();
begin
    if team is null then
        raise exception 'not_in_team' using errcode = 'P0002';
    end if;
    if exists (select 1 from unnest(p_decorations) d where d !~ '^[a-z0-9-]{1,32}$') then
        raise exception 'invalid_decoration' using errcode = '22023';
    end if;
    insert into public.team_campsites (team_id, decorations) values (team, p_decorations)
    on conflict (team_id) do update set decorations = excluded.decorations, updated_at = now();
end;
$$;

revoke all on function public.sync_team_contributions(), public.team_contribution_totals(), public.my_campsite(),
    public.set_campsite_decorations(text[])
from public, anon;
grant execute on function public.sync_team_contributions(), public.team_contribution_totals(), public.my_campsite(),
    public.set_campsite_decorations(text[])
to authenticated;
