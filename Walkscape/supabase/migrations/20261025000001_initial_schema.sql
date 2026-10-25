-- Walkscape initial schema.
--
-- Principles:
-- * Clients only ever sync daily aggregates (never raw HealthKit samples).
-- * Every table has row level security. Policies are the source of truth for
--   who can see what; functions are conveniences on top of them.
-- * Functions that must cross user boundaries (friend requests, account
--   deletion) are SECURITY DEFINER with an empty search_path and check
--   auth.uid() themselves.
-- * Profiles never contain e-mail addresses.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

create type public.distance_source as enum ('recorded', 'estimatedFromSteps', 'unavailable');
create type public.friendship_status as enum ('pending', 'accepted');

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    username text not null,
    avatar_id text not null default 'fern',
    share_progress boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint profiles_username_format check (username ~ '^[a-z0-9_]{3,20}$'),
    constraint profiles_avatar_id_format check (avatar_id ~ '^[a-z0-9_-]{1,32}$')
);

create unique index profiles_username_key on public.profiles (username);

comment on table public.profiles is 'Public walker profile. Deliberately has no e-mail or other contact details.';

-- ---------------------------------------------------------------------------
-- Friendships and blocks
-- ---------------------------------------------------------------------------

create table public.friendships (
    id uuid primary key default gen_random_uuid(),
    requester_id uuid not null references public.profiles (id) on delete cascade,
    addressee_id uuid not null references public.profiles (id) on delete cascade,
    status public.friendship_status not null default 'pending',
    created_at timestamptz not null default now(),
    responded_at timestamptz,
    constraint friendships_no_self check (requester_id <> addressee_id)
);

-- One row per pair, whichever direction the request went.
create unique index friendships_pair_key
    on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friendships_requester_idx on public.friendships (requester_id, status);
create index friendships_addressee_idx on public.friendships (addressee_id, status);

create table public.blocks (
    blocker_id uuid not null references public.profiles (id) on delete cascade,
    blocked_id uuid not null references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    constraint blocks_no_self check (blocker_id <> blocked_id)
);

create index blocks_blocked_idx on public.blocks (blocked_id);

-- ---------------------------------------------------------------------------
-- Daily progress
-- ---------------------------------------------------------------------------

create table public.daily_progress (
    user_id uuid not null references public.profiles (id) on delete cascade,
    local_date date not null,
    time_zone text not null,
    steps integer not null,
    distance_meters integer not null,
    distance_source public.distance_source not null,
    -- When the client read these totals from HealthKit. Used to ignore
    -- out-of-order uploads.
    client_updated_at timestamptz not null,
    -- When the server last accepted an update. Used for staleness.
    updated_at timestamptz not null default now(),
    primary key (user_id, local_date),
    -- Plausibility limits. Client totals cannot be verified; these only stop
    -- obviously impossible values. See docs/BACKEND.md.
    constraint daily_progress_steps_range check (steps between 0 and 150000),
    constraint daily_progress_distance_range check (distance_meters between 0 and 150000),
    constraint daily_progress_time_zone_length check (char_length(time_zone) between 1 and 64)
);

create index daily_progress_local_date_idx on public.daily_progress (local_date);

-- ---------------------------------------------------------------------------
-- Zones, discoveries and achievements (reference data + per-user unlocks)
-- ---------------------------------------------------------------------------

create table public.zone_definitions (
    id text primary key,
    sort_order integer not null unique,
    name text not null,
    tagline text not null,
    biome text not null,
    start_meters integer not null,
    end_meters integer not null,
    discovery_id text,
    discovery_name text,
    constraint zone_definitions_range check (start_meters >= 0 and end_meters > start_meters)
);

create table public.user_discoveries (
    user_id uuid not null references public.profiles (id) on delete cascade,
    zone_id text not null references public.zone_definitions (id),
    discovered_at timestamptz not null default now(),
    primary key (user_id, zone_id)
);

create table public.achievements (
    id text primary key,
    name text not null,
    description text not null
);

create table public.user_achievements (
    user_id uuid not null references public.profiles (id) on delete cascade,
    achievement_id text not null references public.achievements (id),
    unlocked_at timestamptz not null default now(),
    primary key (user_id, achievement_id)
);

-- ---------------------------------------------------------------------------
-- Helper functions used by policies
-- ---------------------------------------------------------------------------

-- True when the caller and `other` are accepted friends. SECURITY DEFINER so
-- policies can use it without recursive RLS; it only ever answers about the
-- caller's own relationships.
create function public.is_friend_of_caller(other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.friendships f
        where f.status = 'accepted'
          and ((f.requester_id = auth.uid() and f.addressee_id = other)
            or (f.requester_id = other and f.addressee_id = auth.uid()))
    );
$$;

-- True when either the caller blocked `other` or `other` blocked the caller.
create function public.is_blocked_with_caller(other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = other)
           or (b.blocker_id = other and b.blocked_id = auth.uid())
    );
$$;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.blocks enable row level security;
alter table public.daily_progress enable row level security;
alter table public.zone_definitions enable row level security;
alter table public.user_discoveries enable row level security;
alter table public.achievements enable row level security;
alter table public.user_achievements enable row level security;

-- Start from nothing and grant exactly what clients need.
revoke all on public.profiles, public.friendships, public.blocks, public.daily_progress,
    public.zone_definitions, public.user_discoveries, public.achievements, public.user_achievements
    from anon, authenticated;

-- Profiles: signed-in users can look each other up (to send requests), except
-- across a block in either direction. Users may edit only a few of their own columns.
grant select on public.profiles to authenticated;
grant update (username, avatar_id, share_progress) on public.profiles to authenticated;

create policy "profiles are visible to signed-in users who are not blocked"
    on public.profiles for select to authenticated
    using (id = auth.uid() or not public.is_blocked_with_caller(id));

create policy "users update their own profile"
    on public.profiles for update to authenticated
    using (id = auth.uid())
    with check (id = auth.uid());

-- Friendships: visible to and removable by the two people involved. New rows
-- must be pending requests from the caller. Acceptance goes through
-- respond_to_friend_request() so status can't be forged.
grant select, insert, delete on public.friendships to authenticated;

create policy "participants see their friendships"
    on public.friendships for select to authenticated
    using (auth.uid() in (requester_id, addressee_id));

create policy "users send pending requests as themselves"
    on public.friendships for insert to authenticated
    with check (
        requester_id = auth.uid()
        and status = 'pending'
        and not public.is_blocked_with_caller(addressee_id)
    );

create policy "participants remove their friendships"
    on public.friendships for delete to authenticated
    using (auth.uid() in (requester_id, addressee_id));

-- Blocks: private to the blocker.
grant select, insert, delete on public.blocks to authenticated;

create policy "users manage their own blocks"
    on public.blocks for all to authenticated
    using (blocker_id = auth.uid())
    with check (blocker_id = auth.uid());

-- Daily progress: owners have full control of their rows; accepted friends
-- can read them while the owner shares progress.
grant select, insert, update, delete on public.daily_progress to authenticated;

create policy "owners and sharing friends read daily progress"
    on public.daily_progress for select to authenticated
    using (
        user_id = auth.uid()
        or (
            public.is_friend_of_caller(user_id)
            and exists (select 1 from public.profiles p where p.id = daily_progress.user_id and p.share_progress)
        )
    );

create policy "owners insert their daily progress"
    on public.daily_progress for insert to authenticated
    with check (user_id = auth.uid());

create policy "owners update their daily progress"
    on public.daily_progress for update to authenticated
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

create policy "owners delete their daily progress"
    on public.daily_progress for delete to authenticated
    using (user_id = auth.uid());

-- Reference data: readable by everyone signed in, writable by nobody.
grant select on public.zone_definitions, public.achievements to authenticated;

create policy "zones are public" on public.zone_definitions for select to authenticated using (true);
create policy "achievements are public" on public.achievements for select to authenticated using (true);

-- Per-user unlocks: private to the owner, insert-only (unlocks are permanent).
grant select, insert on public.user_discoveries, public.user_achievements to authenticated;

create policy "owners read their discoveries" on public.user_discoveries
    for select to authenticated using (user_id = auth.uid());
create policy "owners record their discoveries" on public.user_discoveries
    for insert to authenticated with check (user_id = auth.uid());
create policy "owners read their achievements" on public.user_achievements
    for select to authenticated using (user_id = auth.uid());
create policy "owners record their achievements" on public.user_achievements
    for insert to authenticated with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- Every new auth user gets a profile with a generated, unique username
-- ("walker_" + 10 hex characters), retried on the rare collision. Users can
-- change it later.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    attempt integer := 0;
begin
    loop
        begin
            insert into public.profiles (id, username)
            values (new.id, 'walker_' || substr(md5(new.id::text || attempt::text), 1, 10));
            return new;
        exception when unique_violation then
            attempt := attempt + 1;
            if attempt >= 20 then
                raise;
            end if;
        end;
    end loop;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

create function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create trigger profiles_touch_updated_at
    before update on public.profiles
    for each row execute function public.touch_updated_at();

-- Rejects progress for dates far from "now" and timestamps from the future.
-- local_date may be up to a day ahead of UTC (UTC+14) and a week behind
-- (late syncs after being offline).
create function public.validate_daily_progress()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.local_date > (now() at time zone 'utc')::date + 1
       or new.local_date < (now() at time zone 'utc')::date - 7 then
        raise exception 'local_date_out_of_range' using errcode = '22023';
    end if;
    if new.client_updated_at > now() + interval '10 minutes' then
        raise exception 'client_timestamp_in_future' using errcode = '22023';
    end if;
    new.updated_at := now();
    return new;
end;
$$;

create trigger daily_progress_validate
    before insert or update on public.daily_progress
    for each row execute function public.validate_daily_progress();

-- ---------------------------------------------------------------------------
-- API functions (called via PostgREST /rest/v1/rpc/<name>)
-- ---------------------------------------------------------------------------

-- Idempotent upsert of the caller's totals for one day. Re-sending the same
-- values changes nothing; an upload older than the stored one is ignored.
create function public.upsert_daily_progress(
    p_local_date date,
    p_time_zone text,
    p_steps integer,
    p_distance_meters integer,
    p_distance_source public.distance_source,
    p_client_updated_at timestamptz
)
returns public.daily_progress
language plpgsql
security invoker
set search_path = ''
as $$
declare
    result public.daily_progress;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;

    insert into public.daily_progress as d
        (user_id, local_date, time_zone, steps, distance_meters, distance_source, client_updated_at)
    values
        (auth.uid(), p_local_date, p_time_zone, p_steps, p_distance_meters, p_distance_source, p_client_updated_at)
    on conflict (user_id, local_date) do update
        set time_zone = excluded.time_zone,
            steps = excluded.steps,
            distance_meters = excluded.distance_meters,
            distance_source = excluded.distance_source,
            client_updated_at = excluded.client_updated_at
        where d.client_updated_at < excluded.client_updated_at
    returning * into result;

    if result is null then
        select * into result from public.daily_progress
        where user_id = auth.uid() and local_date = p_local_date;
    end if;
    return result;
end;
$$;

create function public.get_my_profile()
returns public.profiles
language sql
stable
security invoker
set search_path = ''
as $$
    select * from public.profiles where id = auth.uid();
$$;

create function public.update_my_profile(
    p_username text default null,
    p_avatar_id text default null,
    p_share_progress boolean default null
)
returns public.profiles
language plpgsql
security invoker
set search_path = ''
as $$
declare
    result public.profiles;
    clean_username text := lower(trim(p_username));
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if p_username is not null and clean_username !~ '^[a-z0-9_]{3,20}$' then
        raise exception 'invalid_username' using errcode = '22023';
    end if;

    begin
        update public.profiles
        set username = coalesce(clean_username, username),
            avatar_id = coalesce(p_avatar_id, avatar_id),
            share_progress = coalesce(p_share_progress, share_progress)
        where id = auth.uid()
        returning * into result;
    exception when unique_violation then
        raise exception 'username_taken' using errcode = '23505';
    end;
    return result;
end;
$$;

-- Sends a request to `p_username`. If they already asked the caller, this
-- accepts their request instead. Blocked users look like unknown users.
create function public.send_friend_request(p_username text)
returns public.friendships
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    target uuid;
    existing public.friendships;
    result public.friendships;
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;

    select id into target from public.profiles where username = lower(trim(p_username));
    if target is null then
        raise exception 'user_not_found' using errcode = 'P0002';
    end if;
    if target = me then
        raise exception 'cannot_friend_self' using errcode = '22023';
    end if;
    if exists (select 1 from public.blocks b
               where (b.blocker_id = me and b.blocked_id = target)
                  or (b.blocker_id = target and b.blocked_id = me)) then
        raise exception 'user_not_found' using errcode = 'P0002';
    end if;

    select * into existing from public.friendships f
    where least(f.requester_id, f.addressee_id) = least(me, target)
      and greatest(f.requester_id, f.addressee_id) = greatest(me, target);

    if existing.id is not null then
        if existing.status = 'accepted' then
            raise exception 'already_friends' using errcode = '23505';
        elsif existing.requester_id = me then
            raise exception 'request_already_pending' using errcode = '23505';
        end if;
        update public.friendships
        set status = 'accepted', responded_at = now()
        where id = existing.id
        returning * into result;
        return result;
    end if;

    insert into public.friendships (requester_id, addressee_id)
    values (me, target)
    returning * into result;
    return result;
end;
$$;

-- Accepts or declines a pending request addressed to the caller.
create function public.respond_to_friend_request(p_request_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    request public.friendships;
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;

    select * into request from public.friendships
    where id = p_request_id and addressee_id = me and status = 'pending'
    for update;
    if request.id is null then
        raise exception 'request_not_found' using errcode = 'P0002';
    end if;

    if p_accept then
        update public.friendships set status = 'accepted', responded_at = now() where id = request.id;
    else
        delete from public.friendships where id = request.id;
    end if;
end;
$$;

-- Cancels an outgoing request or declines an incoming one.
create function public.delete_friend_request(p_request_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
    delete from public.friendships
    where id = p_request_id and status = 'pending' and auth.uid() in (requester_id, addressee_id);
$$;

create function public.remove_friend(p_friend_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
    delete from public.friendships
    where (requester_id = auth.uid() and addressee_id = p_friend_id)
       or (requester_id = p_friend_id and addressee_id = auth.uid());
$$;

-- Blocks a user: removes any friendship or request and hides the caller's
-- profile from them.
create function public.block_user(p_user_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    insert into public.blocks (blocker_id, blocked_id) values (auth.uid(), p_user_id)
    on conflict do nothing;
    delete from public.friendships
    where (requester_id = auth.uid() and addressee_id = p_user_id)
       or (requester_id = p_user_id and addressee_id = auth.uid());
end;
$$;

create function public.unblock_user(p_user_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
    delete from public.blocks where blocker_id = auth.uid() and blocked_id = p_user_id;
$$;

-- Accepted friends with their totals for `p_local_date`. Friends with no row
-- that day, or who stopped sharing, are returned with null totals.
create function public.friend_daily_summaries(p_local_date date)
returns table (
    user_id uuid,
    username text,
    avatar_id text,
    local_date date,
    steps integer,
    distance_meters integer,
    distance_source public.distance_source,
    updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
    select p.id, p.username, p.avatar_id, d.local_date, d.steps, d.distance_meters, d.distance_source, d.updated_at
    from public.friendships f
    join public.profiles p
        on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
    left join public.daily_progress d
        on d.user_id = p.id and d.local_date = p_local_date
    where f.status = 'accepted'
      and auth.uid() in (f.requester_id, f.addressee_id)
    order by p.username;
$$;

create function public.pending_friend_requests()
returns table (
    id uuid,
    user_id uuid,
    username text,
    avatar_id text,
    direction text,
    created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
    select f.id,
           p.id,
           p.username,
           p.avatar_id,
           case when f.addressee_id = auth.uid() then 'incoming' else 'outgoing' end,
           f.created_at
    from public.friendships f
    join public.profiles p
        on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
    where f.status = 'pending'
      and auth.uid() in (f.requester_id, f.addressee_id)
    order by f.created_at desc;
$$;

-- Permanently deletes the caller's account. Cascades remove the profile,
-- friendships, blocks, progress and unlocks.
create function public.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    delete from auth.users where id = auth.uid();
end;
$$;

-- Postgres grants EXECUTE to PUBLIC by default; only signed-in users may call
-- the API, and policy helpers are not part of the API at all.
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function
    public.is_friend_of_caller(uuid),
    public.is_blocked_with_caller(uuid),
    public.upsert_daily_progress(date, text, integer, integer, public.distance_source, timestamptz),
    public.get_my_profile(),
    public.update_my_profile(text, text, boolean),
    public.send_friend_request(text),
    public.respond_to_friend_request(uuid, boolean),
    public.delete_friend_request(uuid),
    public.remove_friend(uuid),
    public.block_user(uuid),
    public.unblock_user(uuid),
    public.friend_daily_summaries(date),
    public.pending_friend_requests(),
    public.delete_account()
to authenticated;
