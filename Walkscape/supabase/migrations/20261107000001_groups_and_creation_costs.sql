-- Community groups, and coin costs for creating groups (500) and teams (25).
--
-- Coins: the app keeps every coin earned or spent under a key
-- (WalletState.earned / .spent), and the cloud save (player_saves) holds that
-- wallet. charge_coins() locks the caller's save, checks the balance from
-- those keys, and records the charge as spent["<key>"] in the same
-- transaction that creates the group or team. Each charge key includes the
-- client's request id, so a retry or double tap finds the key already spent
-- and pays nothing again; the app merges the charge into the phone's wallet on
-- its next sync. The cloud save is still written by the app, so this is only
-- as strong as that save (see docs/BACKEND.md).
--
-- Groups: independent communities where members compare daily and weekly
-- walking. Nothing is pooled. Ownership is a member role; a trigger always
-- leaves exactly one owner (or deletes an empty group), however members go.

-- Coins ----------------------------------------------------------------------

create function public.charge_coins(p_user uuid, p_key text, p_amount integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    save jsonb;
    earned bigint;
    spent bigint;
begin
    select s.save into save from public.player_saves s where s.user_id = p_user for update;
    if save is null then
        raise exception 'no_cloud_save' using errcode = 'P0002';
    end if;
    if coalesce((save ->> 'schema')::integer, 0) < 2 or jsonb_typeof(save -> 'wallet' -> 'earned') is distinct from 'object' then
        raise exception 'update_app' using errcode = '22023';
    end if;
    if coalesce(save -> 'wallet' -> 'spent', '{}'::jsonb) ? p_key then
        return; -- already paid
    end if;
    select coalesce(sum(value::bigint), 0) into earned from jsonb_each_text(save -> 'wallet' -> 'earned');
    select coalesce(sum(value::bigint), 0) into spent from jsonb_each_text(coalesce(save -> 'wallet' -> 'spent', '{}'::jsonb));
    if earned - spent < p_amount then
        raise exception 'insufficient_coins' using errcode = '22023';
    end if;
    save := jsonb_set(save, '{wallet,spent}', coalesce(save -> 'wallet' -> 'spent', '{}'::jsonb) || jsonb_build_object(p_key, p_amount));
    save := jsonb_set(save, '{wallet,coins}', to_jsonb(earned - spent - p_amount));
    update public.player_saves set save = charge_coins.save, version = version + 1, updated_at = now() where user_id = p_user;
end;
$$;

revoke all on function public.charge_coins(uuid, text, integer) from public, anon, authenticated;

-- Teams cost 25 coins to create --------------------------------------------

alter table public.teams add column creation_request_id uuid unique;

drop function public.create_team(text);

create function public.create_team(p_name text, p_request_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    clean text := regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g');
    request uuid := coalesce(p_request_id, gen_random_uuid());
    new_id uuid;
    attempt integer := 0;
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    -- A retry of a creation that already went through returns the same team.
    select t.id into new_id from public.teams t where t.creation_request_id = request and t.owner_id = me;
    if new_id is not null then
        return new_id;
    end if;
    if clean !~ '^[A-Za-z0-9][A-Za-z0-9 _''-]{1,22}[A-Za-z0-9]$' then
        raise exception 'invalid_team_name' using errcode = '22023';
    end if;
    if exists (select 1 from public.team_members where user_id = me) then
        raise exception 'already_in_team' using errcode = '23505';
    end if;
    perform public.charge_coins(me, 'team-' || request::text, 25);
    loop
        begin
            insert into public.teams (name, join_code, owner_id, creation_request_id)
            values (clean, upper(substr(md5(gen_random_uuid()::text), 1, 6)), me, request)
            returning id into new_id;
            exit;
        exception when unique_violation then
            -- A concurrent retry of the same request created it first.
            select t.id into new_id from public.teams t where t.creation_request_id = request;
            if new_id is not null then
                return new_id;
            end if;
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

revoke all on function public.create_team(text, uuid) from public, anon;
grant execute on function public.create_team(text, uuid) to authenticated;

-- Groups ---------------------------------------------------------------------

create table public.groups (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    description text not null default '',
    emblem text not null,
    join_code text not null unique,
    creation_request_id uuid not null unique,
    created_by uuid references public.profiles (id) on delete set null,
    created_at timestamptz not null default now(),
    constraint groups_name check (char_length(name) between 3 and 40),
    constraint groups_description check (char_length(description) <= 160),
    constraint groups_emblem check (emblem ~ '^[a-z0-9-]{1,32}$'),
    constraint groups_join_code check (join_code ~ '^[A-HJ-NP-Z2-9]{6}$')
);

create table public.group_members (
    group_id uuid not null references public.groups (id) on delete cascade,
    user_id uuid not null references public.profiles (id) on delete cascade,
    role text not null default 'member',
    joined_at timestamptz not null default now(),
    primary key (group_id, user_id),
    constraint group_members_role check (role in ('owner', 'member'))
);

create index group_members_user_idx on public.group_members (user_id);
create unique index group_members_one_owner on public.group_members (group_id) where role = 'owner';

alter table public.groups enable row level security;
alter table public.group_members enable row level security;
revoke all on public.groups, public.group_members from anon, authenticated;

-- However a member goes (leaving, removed, account deleted), the group keeps
-- one owner: the longest-standing member takes over, and an empty group closes.
create function public.keep_group_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    heir uuid;
begin
    if old.role <> 'owner' or not exists (select 1 from public.groups g where g.id = old.group_id) then
        return null;
    end if;
    select m.user_id into heir from public.group_members m
    where m.group_id = old.group_id order by m.joined_at, m.user_id limit 1;
    if heir is null then
        delete from public.groups where id = old.group_id;
    else
        update public.group_members set role = 'owner' where group_id = old.group_id and user_id = heir;
    end if;
    return null;
end;
$$;

create trigger group_members_keep_owner after delete on public.group_members
for each row execute function public.keep_group_owner();

create function public.new_group_code()
returns text
language sql
volatile
set search_path = ''
as $$
    select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::integer, 1), '')
    from generate_series(1, 6);
$$;

create function public.clean_group_name(p_name text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
    clean text := regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g');
begin
    if char_length(clean) not between 3 and 40 or clean !~ '^[[:alnum:]][[:alnum:] &.,''!()_-]*$' then
        raise exception 'invalid_group_name' using errcode = '22023';
    end if;
    return clean;
end;
$$;

create function public.clean_group_description(p_description text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
    clean text := trim(regexp_replace(coalesce(p_description, ''), '[[:cntrl:]]+', ' ', 'g'));
begin
    if char_length(clean) > 160 then
        raise exception 'invalid_group_description' using errcode = '22023';
    end if;
    return clean;
end;
$$;

create function public.require_group_role(p_group_id uuid, p_owner boolean)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    if not exists (select 1 from public.group_members m
                   where m.group_id = p_group_id and m.user_id = auth.uid() and (not p_owner or m.role = 'owner')) then
        if p_owner and exists (select 1 from public.group_members m where m.group_id = p_group_id and m.user_id = auth.uid()) then
            raise exception 'not_group_owner' using errcode = '42501';
        end if;
        raise exception 'group_not_found' using errcode = 'P0002';
    end if;
end;
$$;

-- The caller's groups.
create function public.my_groups()
returns table (id uuid, name text, description text, emblem text, join_code text, member_count integer,
               is_owner boolean, joined_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
    select g.id, g.name, g.description, g.emblem, g.join_code,
           (select count(*)::integer from public.group_members x where x.group_id = g.id),
           m.role = 'owner', m.joined_at
    from public.group_members m
    join public.groups g on g.id = m.group_id
    where m.user_id = auth.uid()
    order by m.joined_at;
$$;

-- Creates a group for 500 coins. `p_request_id` is fixed per attempt in the
-- app, so a retry returns the same group without charging again.
create function public.create_group(p_request_id uuid, p_name text, p_description text, p_emblem text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    clean_name text;
    clean_description text;
    new_id uuid;
    attempt integer := 0;
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if p_request_id is null then
        raise exception 'missing_request_id' using errcode = '22023';
    end if;
    select g.id into new_id from public.groups g where g.creation_request_id = p_request_id and g.created_by = me;
    if new_id is not null then
        return new_id;
    end if;
    clean_name := public.clean_group_name(p_name);
    clean_description := public.clean_group_description(p_description);
    if coalesce(p_emblem, '') !~ '^[a-z0-9-]{1,32}$' then
        raise exception 'invalid_group_emblem' using errcode = '22023';
    end if;
    -- One membership change at a time per player, so the limit holds.
    perform pg_advisory_xact_lock(hashtextextended('groups:' || me::text, 0));
    if (select count(*) from public.group_members where user_id = me) >= 5 then
        raise exception 'group_limit' using errcode = '23514';
    end if;
    perform public.charge_coins(me, 'group-' || p_request_id::text, 500);
    loop
        begin
            insert into public.groups (name, description, emblem, join_code, creation_request_id, created_by)
            values (clean_name, clean_description, p_emblem, public.new_group_code(), p_request_id, me)
            returning id into new_id;
            exit;
        exception when unique_violation then
            select g.id into new_id from public.groups g where g.creation_request_id = p_request_id;
            if new_id is not null then
                return new_id;
            end if;
            attempt := attempt + 1;
            if attempt >= 20 then
                raise;
            end if;
        end;
    end loop;
    insert into public.group_members (group_id, user_id, role) values (new_id, me, 'owner');
    return new_id;
end;
$$;

-- What a code leads to, before joining. Only an exact code reveals a group.
create function public.preview_group(p_code text)
returns table (id uuid, name text, description text, emblem text, member_count integer, is_member boolean)
language sql
stable
security definer
set search_path = ''
as $$
    select g.id, g.name, g.description, g.emblem,
           (select count(*)::integer from public.group_members x where x.group_id = g.id),
           exists (select 1 from public.group_members x where x.group_id = g.id and x.user_id = auth.uid())
    from public.groups g
    where auth.uid() is not null and g.join_code = upper(trim(coalesce(p_code, '')));
$$;

-- Joining is free. Joining a group you're already in changes nothing.
create function public.join_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    target uuid;
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    select g.id into target from public.groups g where g.join_code = upper(trim(coalesce(p_code, '')));
    if target is null then
        raise exception 'group_not_found' using errcode = 'P0002';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('groups:' || me::text, 0));
    if exists (select 1 from public.group_members where group_id = target and user_id = me) then
        return target;
    end if;
    if (select count(*) from public.group_members where user_id = me) >= 5 then
        raise exception 'group_limit' using errcode = '23514';
    end if;
    if (select count(*) from public.group_members where group_id = target) >= 5000 then
        raise exception 'group_full' using errcode = '23514';
    end if;
    insert into public.group_members (group_id, user_id) values (target, me);
    return target;
end;
$$;

create function public.leave_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.require_group_role(p_group_id, false);
    delete from public.group_members where group_id = p_group_id and user_id = auth.uid();
end;
$$;

create function public.remove_group_member(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.require_group_role(p_group_id, true);
    if p_user_id = auth.uid() then
        raise exception 'use_leave_group' using errcode = '22023';
    end if;
    delete from public.group_members where group_id = p_group_id and user_id = p_user_id;
end;
$$;

create function public.update_group(p_group_id uuid, p_name text, p_description text, p_emblem text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.require_group_role(p_group_id, true);
    if coalesce(p_emblem, '') !~ '^[a-z0-9-]{1,32}$' then
        raise exception 'invalid_group_emblem' using errcode = '22023';
    end if;
    update public.groups
    set name = public.clean_group_name(p_name), description = public.clean_group_description(p_description), emblem = p_emblem
    where id = p_group_id;
end;
$$;

-- A new code; the old one stops working straight away.
create function public.regenerate_group_code(p_group_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    code text;
    attempt integer := 0;
begin
    perform public.require_group_role(p_group_id, true);
    loop
        begin
            update public.groups set join_code = public.new_group_code() where id = p_group_id returning join_code into code;
            return code;
        exception when unique_violation then
            attempt := attempt + 1;
            if attempt >= 20 then
                raise;
            end if;
        end;
    end loop;
end;
$$;

-- Members, oldest first, a page at a time. Members only.
create function public.group_member_list(p_group_id uuid, p_limit integer, p_offset integer)
returns table (user_id uuid, username text, avatar_id text, is_owner boolean, joined_at timestamptz, total integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    perform public.require_group_role(p_group_id, false);
    return query
        select m.user_id, p.username, p.avatar_id, m.role = 'owner', m.joined_at, (count(*) over ())::integer
        from public.group_members m
        join public.profiles p on p.id = m.user_id
        where m.group_id = p_group_id
        order by m.joined_at, m.user_id
        limit least(greatest(coalesce(p_limit, 50), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

-- Daily or weekly standings, members only. Periods are calendar days: each
-- member's walking on the local dates from `p_day` (daily) or from the Monday
-- of `p_day`'s week through `p_day` (weekly), the same dates for everyone and
-- the same local days the app and Apple Health use. Ranked by distance, then
-- steps. Members who don't share their progress are listed without numbers.
-- Returns one page plus the caller's own row wherever they rank.
create function public.group_leaderboard(p_group_id uuid, p_period text, p_day date, p_limit integer, p_offset integer)
returns table (user_id uuid, username text, avatar_id text, rank integer, steps integer, distance_meters integer,
               estimated boolean, sharing boolean, updated_at timestamptz, is_me boolean, total integer)
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
        with totals as (
            select m.user_id, p.username, p.avatar_id, p.share_progress as sharing,
                   sum(d.steps)::integer as steps, sum(d.distance_meters)::integer as meters,
                   coalesce(bool_or(d.distance_source = 'estimatedFromSteps'), false) as estimated,
                   max(d.updated_at) as updated_at
            from public.group_members m
            join public.profiles p on p.id = m.user_id
            left join public.daily_progress d
                on d.user_id = m.user_id and p.share_progress and d.local_date between first_day and p_day
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
               r.estimated, r.sharing, r.updated_at, r.user_id = auth.uid(), r.members
        from ranked r
        where (r.position > skip and r.position <= skip + page_size) or r.user_id = auth.uid()
        order by r.position;
end;
$$;

revoke all on function
    public.keep_group_owner(), public.new_group_code(), public.clean_group_name(text),
    public.clean_group_description(text), public.require_group_role(uuid, boolean)
from public, anon, authenticated;

revoke all on function
    public.my_groups(), public.create_group(uuid, text, text, text), public.preview_group(text), public.join_group(text),
    public.leave_group(uuid), public.remove_group_member(uuid, uuid), public.update_group(uuid, text, text, text),
    public.regenerate_group_code(uuid), public.group_member_list(uuid, integer, integer),
    public.group_leaderboard(uuid, text, date, integer, integer)
from public, anon;

grant execute on function
    public.my_groups(), public.create_group(uuid, text, text, text), public.preview_group(text), public.join_group(text),
    public.leave_group(uuid), public.remove_group_member(uuid, uuid), public.update_group(uuid, text, text, text),
    public.regenerate_group_code(uuid), public.group_member_list(uuid, integer, integer),
    public.group_leaderboard(uuid, text, date, integer, integer)
to authenticated;
