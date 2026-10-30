-- Social: shared discoveries, friend milestones and reactions.
--
-- * discoveries: special finds (world events and rare+ wildlife sightings)
--   per day. Everyone gets the same events and sightings on the same day, so
--   when two friends both have the same discovery on the same date it's a
--   shared discovery (worked out on read; nothing extra is stored).
-- * friend_milestones: personal milestones a player chose to share (first
--   10 km, companion evolutions, first expedition, levels...).
-- * milestone_reactions: one cheer per friend per milestone.
--
-- Discoveries and milestones are reported by the app (like daily totals);
-- the server limits them to the caller, recent dates and simple ids.

create table public.discoveries (
    user_id uuid not null references public.profiles (id) on delete cascade,
    discovery_id text not null,
    local_date date not null,
    created_at timestamptz not null default now(),
    primary key (user_id, discovery_id, local_date),
    constraint discoveries_id_format check (discovery_id ~ '^[a-z0-9-]{1,48}$')
);

create index discoveries_lookup_idx on public.discoveries (discovery_id, local_date);

create table public.friend_milestones (
    user_id uuid not null references public.profiles (id) on delete cascade,
    milestone_id text not null,
    achieved_on date not null,
    created_at timestamptz not null default now(),
    primary key (user_id, milestone_id),
    constraint friend_milestones_id_format check (milestone_id ~ '^[a-z0-9-]{1,48}$')
);

create table public.milestone_reactions (
    owner_id uuid not null,
    milestone_id text not null,
    reactor_id uuid not null references public.profiles (id) on delete cascade,
    reaction text not null check (reaction in ('cheer', 'clap', 'star', 'heart')),
    created_at timestamptz not null default now(),
    primary key (owner_id, milestone_id, reactor_id),
    foreign key (owner_id, milestone_id) references public.friend_milestones (user_id, milestone_id) on delete cascade,
    constraint milestone_reactions_no_self check (owner_id <> reactor_id)
);

alter table public.discoveries enable row level security;
alter table public.friend_milestones enable row level security;
alter table public.milestone_reactions enable row level security;
revoke all on public.discoveries, public.friend_milestones, public.milestone_reactions from anon, authenticated;

-- Records the caller's discoveries. Each item is {"id": text, "date": "YYYY-MM-DD"};
-- dates must be within a day of today (time zones), at most 30 per call.
create function public.record_discoveries(p_items jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not_signed_in' using errcode = '42501';
    end if;
    if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 30 then
        raise exception 'too_many_items' using errcode = '22023';
    end if;
    insert into public.discoveries (user_id, discovery_id, local_date)
    select auth.uid(), item->>'id', (item->>'date')::date
    from jsonb_array_elements(p_items) item
    where (item->>'date')::date between current_date - 1 and current_date + 1
    on conflict do nothing;
end;
$$;

-- Discoveries the caller shares with a friend: same id, same date, since p_since.
create function public.my_shared_discoveries(p_since date)
returns table (discovery_id text, local_date date, friend_id uuid, friend_username text)
language sql
stable
security definer
set search_path = ''
as $$
    select mine.discovery_id, mine.local_date, theirs.user_id, p.username
    from public.discoveries mine
    join public.discoveries theirs
        on theirs.discovery_id = mine.discovery_id and theirs.local_date = mine.local_date
       and theirs.user_id <> mine.user_id
    join public.profiles p on p.id = theirs.user_id
    where mine.user_id = auth.uid()
      and mine.local_date >= p_since
      and public.is_friend_of_caller(theirs.user_id)
    order by mine.local_date desc, p.username;
$$;

-- Shares the caller's milestones. Items are {"id": text, "date": "YYYY-MM-DD"}.
create function public.record_milestones(p_items jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not_signed_in' using errcode = '42501';
    end if;
    if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 50 then
        raise exception 'too_many_items' using errcode = '22023';
    end if;
    insert into public.friend_milestones (user_id, milestone_id, achieved_on)
    select auth.uid(), item->>'id', least((item->>'date')::date, current_date + 1)
    from jsonb_array_elements(p_items) item
    on conflict do nothing;
end;
$$;

-- Friends' milestones since p_since, with reaction counts and the caller's own reaction.
create function public.friend_milestone_feed(p_since date)
returns table (user_id uuid, username text, avatar_id text, milestone_id text, achieved_on date,
               reactions integer, my_reaction text)
language sql
stable
security definer
set search_path = ''
as $$
    select m.user_id, p.username, p.avatar_id, m.milestone_id, m.achieved_on,
           (select count(*)::integer from public.milestone_reactions r
            where r.owner_id = m.user_id and r.milestone_id = m.milestone_id),
           (select r.reaction from public.milestone_reactions r
            where r.owner_id = m.user_id and r.milestone_id = m.milestone_id and r.reactor_id = auth.uid())
    from public.friend_milestones m
    join public.profiles p on p.id = m.user_id
    where m.achieved_on >= p_since
      and public.is_friend_of_caller(m.user_id)
    order by m.achieved_on desc, m.created_at desc
    limit 50;
$$;

-- Cheers a friend's milestone (or changes the cheer).
create function public.react_to_milestone(p_owner_id uuid, p_milestone_id text, p_reaction text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not public.is_friend_of_caller(p_owner_id) then
        raise exception 'not_friends' using errcode = '22023';
    end if;
    insert into public.milestone_reactions (owner_id, milestone_id, reactor_id, reaction)
    values (p_owner_id, p_milestone_id, auth.uid(), p_reaction)
    on conflict (owner_id, milestone_id, reactor_id) do update set reaction = excluded.reaction, created_at = now();
end;
$$;

-- Cheers the caller received since p_since.
create function public.my_milestone_reactions(p_since timestamptz)
returns table (milestone_id text, reactor_username text, reaction text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
    select r.milestone_id, p.username, r.reaction, r.created_at
    from public.milestone_reactions r
    join public.profiles p on p.id = r.reactor_id
    where r.owner_id = auth.uid() and r.created_at >= p_since
    order by r.created_at desc
    limit 50;
$$;

-- Distance the caller and each friend have walked since becoming friends
-- (both sides only while sharing).
create function public.walked_together()
returns table (friend_id uuid, username text, meters bigint)
language sql
stable
security definer
set search_path = ''
as $$
    select p.id, p.username,
           (coalesce(public.shared_meters(auth.uid(), f.created_at::date, current_date + 1), 0)
            + coalesce(public.shared_meters(p.id, f.created_at::date, current_date + 1), 0))::bigint
    from public.friendships f
    join public.profiles p
        on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
    where f.status = 'accepted' and auth.uid() in (f.requester_id, f.addressee_id);
$$;

revoke all on function public.record_discoveries(jsonb), public.my_shared_discoveries(date),
    public.record_milestones(jsonb), public.friend_milestone_feed(date),
    public.react_to_milestone(uuid, text, text), public.my_milestone_reactions(timestamptz),
    public.walked_together()
from public, anon;
grant execute on function public.record_discoveries(jsonb), public.my_shared_discoveries(date),
    public.record_milestones(jsonb), public.friend_milestone_feed(date),
    public.react_to_milestone(uuid, text, text), public.my_milestone_reactions(timestamptz),
    public.walked_together()
to authenticated;
