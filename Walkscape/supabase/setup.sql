-- Walkscape: complete database setup in one file.
-- Generated from migrations/ (run in Supabase SQL Editor on an EMPTY project).

-- ===== migrations/20261025000001_initial_schema.sql =====
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

-- ===== migrations/20261025000002_seed_reference_data.sql =====
-- Reference data mirroring ZoneCatalog.standard and AchievementCatalog.standard
-- in WalkscapeDomain. Keep the two in sync when adding content.

insert into public.zone_definitions
    (id, sort_order, name, tagline, biome, start_meters, end_meters, discovery_id, discovery_name)
values
    ('meadow',        0, 'Sunny Meadow',  'Wildflowers sway where every journey begins.', 'meadow',       0,    1000, 'clover',      'Four-leaf Clover'),
    ('riverside',     1, 'Riverside',     'A lazy river and a creaky wooden bridge.',     'riverside',    1000, 2000, 'river-stone', 'River Stone'),
    ('pine-forest',   2, 'Pine Forest',   'Tall pines hum with birdsong.',                'pineForest',   2000, 3000, 'pinecone',    'Golden Pinecone'),
    ('rolling-hills', 3, 'Rolling Hills', 'Soft green hills roll toward the horizon.',    'rollingHills', 3000, 4000, 'feather',     'Kite Feather'),
    ('lakeside',      4, 'Lakeside',      'A mirror-still lake reflects the clouds.',     'lakeside',     4000, 5000, 'shell',       'Spiral Shell'),
    ('village',       5, 'Hearth Village','Chimney smoke and warm bread.',                'village',      5000, 6000, 'lantern',     'Brass Lantern'),
    ('crystal-caves', 6, 'Crystal Caves', 'Glowing crystals light the way.',              'crystalCaves', 6000, 7000, 'crystal',     'Glow Crystal'),
    ('snowy-ridge',   7, 'Snowy Ridge',   'Crisp air and fresh snow underfoot.',          'snowyRidge',   7000, 8000, 'snowflake',   'Snowflake Charm'),
    ('cloud-forest',  8, 'Cloud Forest',  'Mist drifts between mossy giants.',            'cloudForest',  8000, 9000, 'mushroom',    'Glowcap Mushroom'),
    ('summit',        9, 'The Summit',    'The whole world, all at once.',                'summit',       9000, 10000,'summit-flag', 'Summit Flag');

insert into public.achievements (id, name, description)
values
    ('first-steps',   'First Steps',     'Walk 1 km in a day.'),
    ('trailblazer',   'Trailblazer',     'Reach Hearth Village in a single day (5 km).'),
    ('summiteer',     'Summiteer',       'Reach the Summit in a single day (9 km).'),
    ('beyond',        'Beyond the Map',  'Walk 10 km in a single day.'),
    ('regular',       'Regular Rambler', 'Walk at least 1 km on 3 different days.'),
    ('wanderer',      'Wanderer',        'Walk 25 km in total.'),
    ('marathoner',    'Marathoner',      'Walk a marathon''s distance in total (42.2 km).'),
    ('collector',     'Collector',       'Find 5 discoveries.'),
    ('completionist', 'Cartographer',    'Find all 10 discoveries.');


-- ===== migrations/20261027000001_far_side_zones.sql =====
-- The far side of the Summit: zones 10-19 (10-20 km) and their achievements.
-- Mirrors ZoneCatalog.standard and AchievementCatalog.standard in WalkscapeDomain.

insert into public.zone_definitions
    (id, sort_order, name, tagline, biome, start_meters, end_meters, discovery_id, discovery_name)
values
    ('starlight-pass',   10, 'Starlight Pass',   'Ribbons of light dance over the pass.',      'starlightPass',   10000, 11000, 'fallen-star',    'Fallen Star'),
    ('hot-springs',      11, 'Hot Springs',      'Steam curls from turquoise pools.',          'hotSprings',      11000, 12000, 'spring-egg',     'Spring Egg'),
    ('maple-woods',      12, 'Maple Woods',      'Every tree is on fire with colour.',         'autumnWoods',     12000, 13000, 'maple-leaf',     'Maple Leaf'),
    ('bamboo-grove',     13, 'Bamboo Grove',     'Tall stalks creak softly in the wind.',      'bambooGrove',     13000, 14000, 'bamboo-flute',   'Bamboo Flute'),
    ('blossom-orchard',  14, 'Blossom Orchard',  'Pink petals drift on the breeze.',           'blossomOrchard',  14000, 15000, 'cherries',       'Twin Cherries'),
    ('lavender-fields',  15, 'Lavender Fields',  'Purple rows roll out to an old windmill.',   'lavenderFields',  15000, 16000, 'lavender',       'Lavender Sprig'),
    ('red-canyon',       16, 'Red Rock Canyon',  'Sun-baked mesas glow orange.',               'redCanyon',       16000, 17000, 'canyon-agate',   'Canyon Agate'),
    ('firefly-marsh',    17, 'Firefly Marsh',    'Dusk falls and the fireflies wake.',         'fireflyMarsh',    17000, 18000, 'firefly-jar',    'Firefly Jar'),
    ('sandy-shore',      18, 'Sandy Shore',      'Salt air and the sound of waves.',           'sandyShore',      18000, 19000, 'message-bottle', 'Message in a Bottle'),
    ('lighthouse-point', 19, 'Lighthouse Point', 'The end of the land, the start of the sea.', 'lighthousePoint', 19000, 20000, 'spyglass',       'Keeper''s Spyglass');

insert into public.achievements (id, name, description)
values
    ('lightkeeper', 'Lightkeeper', 'Reach Lighthouse Point in a single day (19 km).'),
    ('off-the-map', 'Off the Map', 'Walk 20 km in a single day.'),
    ('curator',     'Curator',     'Find all 20 discoveries.');

-- The map no longer ends at 10 km.
update public.achievements set name = 'Double Digits' where id = 'beyond';
update public.achievements set description = 'Find 10 discoveries.' where id = 'completionist';

-- ===== migrations/20261028000001_referrals_and_teams.sql =====
-- Referrals and walking teams.
--
-- Same principles as the initial schema: RLS on every table, writes only
-- through functions that check auth.uid(), and only aggregates of other
-- people's walking ever leave the database.

-- ---------------------------------------------------------------------------
-- Referral codes
-- ---------------------------------------------------------------------------

alter table public.profiles add column referral_code text;
update public.profiles set referral_code = upper(substr(md5(id::text || 'walkscape-referral'), 1, 8));
alter table public.profiles alter column referral_code set not null;
alter table public.profiles add constraint profiles_referral_code_format check (referral_code ~ '^[0-9A-F]{8}$');
create unique index profiles_referral_code_key on public.profiles (referral_code);

-- New users also get a referral code; a collision on either unique column retries.
create or replace function public.handle_new_user()
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
            insert into public.profiles (id, username, referral_code)
            values (new.id,
                    'walker_' || substr(md5(new.id::text || attempt::text), 1, 10),
                    upper(substr(md5(new.id::text || 'walkscape-referral' || attempt::text), 1, 8)));
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

-- ---------------------------------------------------------------------------
-- Referrals
-- ---------------------------------------------------------------------------

create table public.referrals (
    id uuid primary key default gen_random_uuid(),
    referrer_id uuid not null references public.profiles (id) on delete cascade,
    -- Kept (as null) when the invited account is deleted, so deleting and
    -- re-creating an account can't be used to farm a second reward.
    referred_id uuid unique references public.profiles (id) on delete set null,
    created_at timestamptz not null default now(),
    qualified_at timestamptz,
    reward_coins integer,
    opened_at timestamptz,
    constraint referrals_no_self check (referrer_id <> referred_id),
    constraint referrals_reward_range check (reward_coins is null or reward_coins between 25 and 100),
    constraint referrals_reward_when_qualified check ((qualified_at is null) = (reward_coins is null))
);

create index referrals_referrer_idx on public.referrals (referrer_id);

alter table public.referrals enable row level security;
revoke all on public.referrals from anon, authenticated;
grant select on public.referrals to authenticated;

create policy "participants see their referrals"
    on public.referrals for select to authenticated
    using (auth.uid() in (referrer_id, referred_id));

-- Walking an invited player has done in their qualifying window.
create function public.referral_activity(p_referral public.referrals)
returns table (meters bigint, active_days bigint)
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(sum(d.distance_meters), 0), count(*) filter (where d.distance_meters > 0)
    from public.daily_progress d
    where d.user_id = p_referral.referred_id
      and d.local_date between (p_referral.created_at at time zone 'utc')::date - 1
                           and (p_referral.created_at at time zone 'utc')::date + 30;
$$;

-- Uses someone's code. Only new accounts can do this, once, and never for
-- themselves or for someone they invited.
create function public.redeem_referral_code(p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    target uuid;
    clean text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    select id into target from public.profiles where referral_code = clean;
    if target is null or exists (select 1 from public.blocks b
                                 where (b.blocker_id = me and b.blocked_id = target)
                                    or (b.blocker_id = target and b.blocked_id = me)) then
        raise exception 'code_not_found' using errcode = 'P0002';
    end if;
    if target = me then
        raise exception 'own_code' using errcode = '22023';
    end if;
    if exists (select 1 from public.referrals where referred_id = me) then
        raise exception 'already_redeemed' using errcode = '23505';
    end if;
    if (select created_at from public.profiles where id = me) < now() - interval '14 days' then
        raise exception 'account_too_old' using errcode = '22023';
    end if;
    if exists (select 1 from public.referrals where referrer_id = me and referred_id = target) then
        raise exception 'circular_referral' using errcode = '22023';
    end if;
    insert into public.referrals (referrer_id, referred_id) values (target, me);
end;
$$;

-- The caller's code and whether they can still use someone else's.
create function public.my_referral_status()
returns table (referral_code text, has_redeemed boolean, can_redeem boolean)
language sql
stable
security definer
set search_path = ''
as $$
    select p.referral_code,
           exists (select 1 from public.referrals r where r.referred_id = p.id),
           p.created_at >= now() - interval '14 days'
    from public.profiles p
    where p.id = auth.uid();
$$;

-- People the caller invited, with progress toward the requirement (a
-- fraction only; no daily totals are revealed).
create function public.my_referral_invitees()
returns table (id uuid, username text, qualified boolean, progress double precision)
language sql
stable
security definer
set search_path = ''
as $$
    select r.id,
           coalesce(p.username, 'deleted account'),
           r.qualified_at is not null,
           case when r.qualified_at is not null then 1.0
                else least(1.0, least(a.meters::double precision / 5000, a.active_days::double precision / 2))
           end
    from public.referrals r
    left join public.profiles p on p.id = r.referred_id
    cross join lateral public.referral_activity(r) a
    where r.referrer_id = auth.uid()
    order by r.created_at desc;
$$;

-- Marks newly qualified referrals (deciding each reward exactly once) and
-- returns the caller's unopened chests. At most 20 referral rewards per walker.
create function public.ready_referral_chests()
returns table (id uuid, reward_coins integer)
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

    update public.referrals r
    set qualified_at = now(),
        reward_coins = 25 + floor(random() * 76)::integer
    where r.referrer_id = me
      and r.qualified_at is null
      and r.referred_id is not null
      and r.created_at > now() - interval '31 days'
      and (select count(*) from public.referrals q where q.referrer_id = me and q.qualified_at is not null) < 20
      and exists (select 1 from public.referral_activity(r) a where a.meters >= 5000 and a.active_days >= 2);

    return query
        select r.id, r.reward_coins from public.referrals r
        where r.referrer_id = me and r.qualified_at is not null and r.opened_at is null
        order by r.qualified_at;
end;
$$;

create function public.mark_referral_chest_opened(p_referral_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
    update public.referrals set opened_at = now()
    where id = p_referral_id and referrer_id = auth.uid() and qualified_at is not null and opened_at is null;
$$;

-- ---------------------------------------------------------------------------
-- Teams
-- ---------------------------------------------------------------------------

create table public.teams (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    join_code text not null,
    owner_id uuid references public.profiles (id) on delete set null,
    created_at timestamptz not null default now(),
    constraint teams_name_format check (name ~ '^[A-Za-z0-9][A-Za-z0-9 _''-]{1,22}[A-Za-z0-9]$'),
    constraint teams_join_code_format check (join_code ~ '^[0-9A-F]{6}$')
);

create unique index teams_join_code_key on public.teams (join_code);

-- One team per walker.
create table public.team_members (
    team_id uuid not null references public.teams (id) on delete cascade,
    user_id uuid not null references public.profiles (id) on delete cascade,
    joined_at timestamptz not null default now(),
    primary key (team_id, user_id)
);

create unique index team_members_user_key on public.team_members (user_id);

create table public.team_invites (
    id uuid primary key default gen_random_uuid(),
    team_id uuid not null references public.teams (id) on delete cascade,
    inviter_id uuid not null references public.profiles (id) on delete cascade,
    invitee_id uuid not null references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    constraint team_invites_no_self check (inviter_id <> invitee_id)
);

create unique index team_invites_pair_key on public.team_invites (team_id, invitee_id);

-- The caller's team id, or null.
create function public.caller_team_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select team_id from public.team_members where user_id = auth.uid();
$$;

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.team_invites enable row level security;
revoke all on public.teams, public.team_members, public.team_invites from anon, authenticated;
grant select on public.teams, public.team_members, public.team_invites to authenticated;

create policy "members see their team" on public.teams
    for select to authenticated using (id = public.caller_team_id());
create policy "members see their teammates" on public.team_members
    for select to authenticated using (team_id = public.caller_team_id());
create policy "invite participants see invites" on public.team_invites
    for select to authenticated using (auth.uid() in (inviter_id, invitee_id));

-- Distance a member may show to their team: nothing while sharing is off.
create function public.shared_meters(p_user_id uuid, p_from date, p_to date)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
    select case when p.share_progress or p.id = auth.uid()
                then (select coalesce(sum(d.distance_meters), 0) from public.daily_progress d
                      where d.user_id = p.id and d.local_date between p_from and p_to)
           end
    from public.profiles p
    where p.id = p_user_id;
$$;

create function public.add_caller_to_team(p_team_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if exists (select 1 from public.team_members where user_id = auth.uid()) then
        raise exception 'already_in_team' using errcode = '23505';
    end if;
    if (select count(*) from public.team_members where team_id = p_team_id) >= 12 then
        raise exception 'team_full' using errcode = '22023';
    end if;
    insert into public.team_members (team_id, user_id) values (p_team_id, auth.uid());
    delete from public.team_invites where invitee_id = auth.uid();
end;
$$;

create function public.create_team(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    clean text := regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g');
    new_id uuid;
    attempt integer := 0;
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if clean !~ '^[A-Za-z0-9][A-Za-z0-9 _''-]{1,22}[A-Za-z0-9]$' then
        raise exception 'invalid_team_name' using errcode = '22023';
    end if;
    if exists (select 1 from public.team_members where user_id = me) then
        raise exception 'already_in_team' using errcode = '23505';
    end if;
    loop
        begin
            insert into public.teams (name, join_code, owner_id)
            values (clean, upper(substr(md5(gen_random_uuid()::text), 1, 6)), me)
            returning id into new_id;
            exit;
        exception when unique_violation then
            attempt := attempt + 1;
            if attempt >= 20 then
                raise;
            end if;
        end;
    end loop;
    perform public.add_caller_to_team(new_id);
    return new_id;
end;
$$;

create function public.join_team(p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    target uuid;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    select id into target from public.teams
    where join_code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
    if target is null then
        raise exception 'team_not_found' using errcode = 'P0002';
    end if;
    perform public.add_caller_to_team(target);
end;
$$;

-- Leaves the caller's team. The longest-standing member becomes owner if
-- the owner leaves; an empty team is deleted.
create function public.leave_team()
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
    delete from public.team_members where team_id = team and user_id = auth.uid();
    if not exists (select 1 from public.team_members where team_id = team) then
        delete from public.teams where id = team;
    elsif (select owner_id from public.teams where id = team) is distinct from null
          and (select owner_id from public.teams where id = team) = auth.uid() then
        update public.teams
        set owner_id = (select user_id from public.team_members where team_id = team order by joined_at, user_id limit 1)
        where id = team;
    end if;
end;
$$;

create function public.invite_friend_to_team(p_friend_id uuid)
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
    if not public.is_friend_of_caller(p_friend_id) then
        raise exception 'not_friends' using errcode = '22023';
    end if;
    insert into public.team_invites (team_id, inviter_id, invitee_id)
    values (team, auth.uid(), p_friend_id)
    on conflict do nothing;
end;
$$;

create function public.my_team_invites()
returns table (id uuid, team_name text, from_username text)
language sql
stable
security definer
set search_path = ''
as $$
    select i.id, t.name, p.username
    from public.team_invites i
    join public.teams t on t.id = i.team_id
    join public.profiles p on p.id = i.inviter_id
    where i.invitee_id = auth.uid()
    order by i.created_at desc;
$$;

create function public.respond_to_team_invite(p_invite_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    invite public.team_invites;
begin
    select * into invite from public.team_invites where id = p_invite_id and invitee_id = auth.uid();
    if invite.id is null then
        raise exception 'invite_not_found' using errcode = 'P0002';
    end if;
    if p_accept then
        perform public.add_caller_to_team(invite.team_id);
    else
        delete from public.team_invites where id = invite.id;
    end if;
end;
$$;

-- The caller's team, with the distance sharing members have walked since joining.
create function public.my_team()
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
           (select coalesce(sum(public.shared_meters(m.user_id, (m.joined_at at time zone 'utc')::date - 1,
                                                     (now() at time zone 'utc')::date + 1)), 0)
            from public.team_members m where m.team_id = t.id)::bigint
    from public.teams t
    where t.id = public.caller_team_id();
$$;

-- Teammates' totals for a day and its week. Null while a member isn't sharing.
create function public.team_member_days(p_local_date date, p_week_start date)
returns table (user_id uuid, username text, avatar_id text, is_owner boolean,
               day_steps integer, day_meters integer, week_meters bigint, updated_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
    select p.id, p.username, p.avatar_id, t.owner_id = p.id,
           case when p.share_progress or p.id = auth.uid() then d.steps end,
           case when p.share_progress or p.id = auth.uid() then d.distance_meters end,
           public.shared_meters(p.id, p_week_start, p_week_start + 6),
           case when p.share_progress or p.id = auth.uid() then d.updated_at end
    from public.team_members m
    join public.teams t on t.id = m.team_id
    join public.profiles p on p.id = m.user_id
    left join public.daily_progress d on d.user_id = p.id and d.local_date = p_local_date
    where m.team_id = public.caller_team_id()
    order by p.username;
$$;

-- This week's competition: the top 20 teams plus the caller's. Only team
-- names, sizes and combined distance are visible.
create function public.team_week_standings(p_week_start date)
returns table (team_id uuid, name text, member_count integer, week_meters bigint, rank bigint)
language sql
stable
security definer
set search_path = ''
as $$
    with totals as (
        select t.id, t.name,
               (select count(*)::integer from public.team_members m where m.team_id = t.id) as members,
               (select coalesce(sum(public.shared_meters(m.user_id, p_week_start, p_week_start + 6)), 0)
                from public.team_members m where m.team_id = t.id)::bigint as meters
        from public.teams t
    ), ranked as (
        select *, rank() over (order by meters desc, name) as place from totals
    )
    select id, name, members, meters, place from ranked
    where place <= 20 or id = public.caller_team_id()
    order by place;
$$;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------

revoke execute on function
    public.referral_activity(public.referrals),
    public.redeem_referral_code(text),
    public.my_referral_status(),
    public.my_referral_invitees(),
    public.ready_referral_chests(),
    public.mark_referral_chest_opened(uuid),
    public.caller_team_id(),
    public.shared_meters(uuid, date, date),
    public.add_caller_to_team(uuid),
    public.create_team(text),
    public.join_team(text),
    public.leave_team(),
    public.invite_friend_to_team(uuid),
    public.my_team_invites(),
    public.respond_to_team_invite(uuid, boolean),
    public.my_team(),
    public.team_member_days(date, date),
    public.team_week_standings(date)
from public, anon, authenticated;

grant execute on function
    public.caller_team_id(),
    public.redeem_referral_code(text),
    public.my_referral_status(),
    public.my_referral_invitees(),
    public.ready_referral_chests(),
    public.mark_referral_chest_opened(uuid),
    public.create_team(text),
    public.join_team(text),
    public.leave_team(),
    public.invite_friend_to_team(uuid),
    public.my_team_invites(),
    public.respond_to_team_invite(uuid, boolean),
    public.my_team(),
    public.team_member_days(date, date),
    public.team_week_standings(date)
to authenticated;

-- ===== migrations/20261030000001_push_notifications.sql =====
-- Push notification device tokens.
--
-- The app registers its APNs token here after the player allows
-- notifications. The send-push Edge Function (supabase/functions/send-push)
-- reads tokens with the service role when a friend request or team invite is
-- created, so the recipient hears about it even with the app closed.
--
-- Tokens are private: clients can only add or remove their own, through the
-- functions below, and can never read any token back.

create table public.push_tokens (
    token text primary key,
    user_id uuid not null references public.profiles (id) on delete cascade,
    environment text not null check (environment in ('sandbox', 'production')),
    -- Mirrors the in-app "Friends & teams" notification switch.
    social boolean not null default true,
    updated_at timestamptz not null default now(),
    constraint push_tokens_token_format check (token ~ '^[0-9a-f]{64,200}$')
);

create index push_tokens_user_idx on public.push_tokens (user_id);

alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon, authenticated;

-- Registers (or moves) a device token to the caller. A token belongs to one
-- device, so if someone else signed in on this phone before, it moves over.
create function public.register_push_token(p_token text, p_environment text, p_social boolean default true)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not_signed_in' using errcode = '42501';
    end if;
    insert into public.push_tokens (token, user_id, environment, social, updated_at)
    values (lower(p_token), auth.uid(), p_environment, p_social, now())
    on conflict (token) do update
        set user_id = excluded.user_id, environment = excluded.environment,
            social = excluded.social, updated_at = now();
end;
$$;

-- Removes one of the caller's tokens (signing out, or notifications turned off).
create function public.unregister_push_token(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
    delete from public.push_tokens where token = lower(p_token) and user_id = auth.uid();
$$;

revoke all on function public.register_push_token(text, text, boolean), public.unregister_push_token(text)
from public, anon;
grant execute on function public.register_push_token(text, text, boolean), public.unregister_push_token(text)
to authenticated;

-- ===== migrations/20261031000001_player_saves.sql =====
-- Cloud save: one private row per player holding their Apple Health
-- progression, wallet, journal, reward ledger and companion (see
-- CloudSave.swift), so a new phone can restore everything.
--
-- The app always merges before writing (nothing earned on either device is
-- lost), and writes are guarded by a version number so two phones saving at
-- once can't overwrite each other: a stale write fails with save_conflict and
-- the app fetches, merges and retries.

create table public.player_saves (
    user_id uuid primary key references public.profiles (id) on delete cascade,
    save jsonb not null,
    version integer not null default 1,
    updated_at timestamptz not null default now(),
    constraint player_saves_is_object check (jsonb_typeof(save) = 'object'),
    constraint player_saves_size check (octet_length(save::text) <= 1048576)
);

alter table public.player_saves enable row level security;
revoke all on public.player_saves from anon, authenticated;

-- The caller's save, or no row if they have none yet.
create function public.get_player_save()
returns table (save jsonb, version integer, updated_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
    select s.save, s.version, s.updated_at from public.player_saves s where s.user_id = auth.uid();
$$;

-- Stores the caller's save if `p_base_version` is the version they last read
-- (0 when they had none). Returns the new version.
create function public.put_player_save(p_save jsonb, p_base_version integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    new_version integer;
begin
    if auth.uid() is null then
        raise exception 'not_signed_in' using errcode = '42501';
    end if;
    if p_base_version = 0 then
        insert into public.player_saves (user_id, save) values (auth.uid(), p_save)
        on conflict (user_id) do nothing
        returning version into new_version;
    else
        update public.player_saves
        set save = p_save, version = version + 1, updated_at = now()
        where user_id = auth.uid() and version = p_base_version
        returning version into new_version;
    end if;
    if new_version is null then
        raise exception 'save_conflict' using errcode = '40001';
    end if;
    return new_version;
end;
$$;

revoke all on function public.get_player_save(), public.put_player_save(jsonb, integer) from public, anon;
grant execute on function public.get_player_save(), public.put_player_save(jsonb, integer) to authenticated;

-- ===== migrations/20261101000001_profile_showcase.sql =====
-- Profile showcase: the title, frame and favourite zone friends and
-- teammates see. Ids are checked for format only; which ones a player has
-- unlocked is decided by the app (see Titles.swift), like the rest of the
-- client-reported progress described in docs/BACKEND.md.

alter table public.profiles
    add column title_id text,
    add column frame_id text,
    add column favorite_zone_id text,
    add constraint profiles_title_id_format check (title_id ~ '^[a-z0-9-]{1,32}$'),
    add constraint profiles_frame_id_format check (frame_id ~ '^[a-z0-9-]{1,32}$'),
    add constraint profiles_favorite_zone_id_format check (favorite_zone_id ~ '^[a-z0-9-]{1,32}$');

grant update (title_id, frame_id, favorite_zone_id) on public.profiles to authenticated;

-- Sets the caller's showcase. Null clears a field.
create function public.set_my_showcase(p_title_id text, p_frame_id text, p_favorite_zone_id text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    update public.profiles
    set title_id = p_title_id, frame_id = p_frame_id, favorite_zone_id = p_favorite_zone_id
    where id = auth.uid();
end;
$$;

-- Showcases of the caller's friends and teammates (and the caller).
create function public.friend_showcases()
returns table (user_id uuid, title_id text, frame_id text, favorite_zone_id text)
language sql
stable
security definer
set search_path = ''
as $$
    select p.id, p.title_id, p.frame_id, p.favorite_zone_id
    from public.profiles p
    where p.id = auth.uid()
       or public.is_friend_of_caller(p.id)
       or (public.caller_team_id() is not null
           and exists (select 1 from public.team_members m
                       where m.user_id = p.id and m.team_id = public.caller_team_id()));
$$;

revoke all on function public.set_my_showcase(text, text, text), public.friend_showcases() from public, anon;
grant execute on function public.set_my_showcase(text, text, text), public.friend_showcases() to authenticated;
