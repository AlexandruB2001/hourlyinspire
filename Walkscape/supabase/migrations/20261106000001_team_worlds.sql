-- Team worlds: the server records when a team reaches each zone.
--
-- The zones' team distances mirror TeamWorlds.swift (a Swift test checks the
-- two stay in sync): the first world opens at 100 km of team walking, after
-- the Summit Relay expedition, and each world follows the one before.
-- Progress comes only from the team ledger, so it never goes backwards and a
-- zone is recorded once per team, with the time it was first reached.

create table public.team_world_zones (
    zone_id text primary key,
    world_id text not null,
    team_meters bigint not null check (team_meters >= 0)
);

insert into public.team_world_zones (zone_id, world_id, team_meters) values
    ('ef-gate', 'enchanted-forest', 100000),
    ('ef-glade', 'enchanted-forest', 200000),
    ('ef-brook', 'enchanted-forest', 350000),
    ('ef-hollow', 'enchanted-forest', 550000),
    ('ef-heart', 'enchanted-forest', 800000),
    ('ck-steps', 'crystal-kingdom', 800000),
    ('ck-caverns', 'crystal-kingdom', 950000),
    ('ck-lake', 'crystal-kingdom', 1150000),
    ('ck-throne', 'crystal-kingdom', 1400000),
    ('fd-oasis', 'forgotten-desert', 1400000),
    ('fd-mesa', 'forgotten-desert', 1550000),
    ('fd-ruins', 'forgotten-desert', 1800000),
    ('fd-tomb', 'forgotten-desert', 2100000),
    ('fi-dock', 'floating-isles', 2100000),
    ('fi-meadow', 'floating-isles', 2300000),
    ('fi-falls', 'floating-isles', 2550000),
    ('fi-spire', 'floating-isles', 2850000),
    ('ak-road', 'ancient-kingdom', 2850000),
    ('ak-gardens', 'ancient-kingdom', 3050000),
    ('ak-bridge', 'ancient-kingdom', 3300000),
    ('ak-castle', 'ancient-kingdom', 3650000);

create table public.team_world_unlocks (
    team_id uuid not null references public.teams (id) on delete cascade,
    zone_id text not null references public.team_world_zones (zone_id),
    unlocked_at timestamptz not null default now(),
    primary key (team_id, zone_id)
);

alter table public.team_world_zones enable row level security;
alter table public.team_world_unlocks enable row level security;
revoke all on public.team_world_zones, public.team_world_unlocks from anon, authenticated;

-- Records every zone the caller's team has walked far enough to reach and
-- returns all of the team's unlocks. Safe to call on every refresh.
create function public.record_team_world_unlocks()
returns table (zone_id text, unlocked_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
    team uuid := public.caller_team_id();
    walked bigint;
begin
    if team is null then
        return;
    end if;
    select coalesce(sum(c.meters), 0) into walked from public.team_contributions c where c.team_id = team;
    insert into public.team_world_unlocks (team_id, zone_id)
    select team, z.zone_id from public.team_world_zones z where z.team_meters <= walked
    on conflict do nothing;
    return query
        select u.zone_id, u.unlocked_at from public.team_world_unlocks u where u.team_id = team order by u.unlocked_at, u.zone_id;
end;
$$;

revoke all on function public.record_team_world_unlocks() from public, anon;
grant execute on function public.record_team_world_unlocks() to authenticated;
