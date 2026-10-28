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
