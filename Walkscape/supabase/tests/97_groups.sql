-- Groups and creation costs, with their own players: gwen owns a group, hugo
-- and iris join, jade can't afford one, kurt is an outsider, lulu fills groups.
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

insert into tests.users values
    ('gwen', '00000000-0000-0000-0000-000000000022'),
    ('hugo', '00000000-0000-0000-0000-000000000023'),
    ('iris', '00000000-0000-0000-0000-000000000024'),
    ('jade', '00000000-0000-0000-0000-000000000025'),
    ('kurt', '00000000-0000-0000-0000-000000000026'),
    ('lulu', '00000000-0000-0000-0000-000000000027');
insert into auth.users (id, email)
select id, name || '@example.com' from tests.users where name in ('gwen', 'hugo', 'iris', 'jade', 'kurt', 'lulu');
update public.profiles set username = (select name from tests.users where id = profiles.id)
where id in (select id from tests.users where name in ('gwen', 'hugo', 'iris', 'jade', 'kurt', 'lulu'));

-- Creating a group --------------------------------------------------------------

select tests.as_user('jade');
select tests.fails($$select public.create_group(gen_random_uuid(), 'Book Club Walks', '', 'boot')$$, 'no_cloud_save',
                   'creating needs a cloud save to pay from');
select tests.give_coins(499);
select tests.fails($$select public.create_group(gen_random_uuid(), 'Book Club Walks', '', 'boot')$$, 'insufficient_coins',
                   'creating a group needs 500 coins');
select tests.ok(tests.coins() = 499, 'a failed creation takes no coins');
select tests.ok(tests.count('select * from public.my_groups()') = 0, 'and creates no group');
reset role;

select tests.as_user('gwen');
select tests.give_coins(1200);
select tests.fails($$select public.create_group(gen_random_uuid(), 'x', '', 'boot')$$, 'invalid_group_name',
                   'group names need 3-40 characters');
select tests.fails($$select public.create_group(gen_random_uuid(), 'Fine Name', repeat('a', 161), 'boot')$$,
                   'invalid_group_description', 'descriptions are at most 160 characters');
select tests.fails($$select public.create_group(gen_random_uuid(), 'Fine Name', '', 'Not An Emblem!')$$,
                   'invalid_group_emblem', 'emblems are sprite ids');
select tests.ok(tests.coins() = 1200, 'invalid requests take no coins');
select public.create_group('00000000-0000-0000-0000-0000000000a1', '  Fit4Less   Windsor ', 'Morning walkers', 'team-badge')
       as gym_id \gset
select tests.ok(tests.coins() = 700, 'creating a group takes exactly 500 coins');
select tests.ok(public.create_group('00000000-0000-0000-0000-0000000000a1', 'Fit4Less Windsor', '', 'boot') = :'gym_id',
                'retrying the same request returns the same group');
select tests.ok(tests.coins() = 700, 'and charges nothing again');
select tests.ok(tests.count('select * from public.my_groups()') = 1, 'one group, not two');
select tests.ok((select name = 'Fit4Less Windsor' and is_owner and member_count = 1 and join_code ~ '^[A-HJ-NP-Z2-9]{6}$'
                 from public.my_groups()), 'names are tidied; the creator owns it and has a six-character code');
select tests.ok((select (save #>> '{wallet,spent,group-00000000-0000-0000-0000-0000000000a1}')::integer = 500
                 from public.get_player_save()), 'the charge is recorded in the cloud save for the app to merge');
select join_code as gym_code from public.my_groups() \gset
reset role;

-- Joining ---------------------------------------------------------------------------

select tests.as_user('hugo');
select tests.ok(tests.count($$select * from public.preview_group('ZZZZZZ')$$) = 0, 'an unknown code shows nothing');
select tests.fails($$select public.join_group('ZZZZZZ')$$, 'group_not_found', 'an unknown code can''t be joined');
select tests.ok((select name = 'Fit4Less Windsor' and member_count = 1 and not is_member
                 from public.preview_group(lower(:'gym_code'))), 'a code previews the group, in any case');
select tests.fails(format('select * from public.group_leaderboard(%L, ''day'', current_date, 10, 0)', :'gym_id'),
                   'group_not_found', 'a preview doesn''t open the leaderboard');
select tests.ok(public.join_group(:'gym_code') = :'gym_id', 'joining with a valid code works');
select tests.ok(public.join_group(:'gym_code') = :'gym_id', 'joining again changes nothing');
select tests.ok(tests.coins() is null, 'joining is free (no save needed)');
select tests.ok((select member_count = 2 from public.my_groups()), 'no duplicate membership');
reset role;

select tests.as_user('iris');
select public.join_group(:'gym_code');
reset role;

-- Leaderboards ------------------------------------------------------------------------

-- Today and earlier this week for everyone; the Sunday before this week's Monday
-- must not count towards the week.
insert into public.daily_progress (user_id, local_date, time_zone, steps, distance_meters, distance_source, client_updated_at)
values (tests.id('gwen'), current_date, 'Europe/London', 6000, 4000, 'recorded', now()),
       (tests.id('hugo'), current_date, 'America/Toronto', 9000, 7000, 'recorded', now()),
       (tests.id('iris'), current_date, 'Asia/Tokyo', 3000, 2000, 'estimatedFromSteps', now()),
       (tests.id('gwen'), current_date - extract(isodow from current_date)::integer, 'Europe/London', 30000, 25000, 'recorded', now());
insert into public.daily_progress (user_id, local_date, time_zone, steps, distance_meters, distance_source, client_updated_at)
select tests.id('iris'), current_date - (extract(isodow from current_date)::integer - 1), 'Asia/Tokyo', 20000, 15000, 'recorded', now()
where extract(isodow from current_date) > 1;

select tests.as_user('gwen');
select tests.ok((select array_agg(username order by rank) = array['hugo', 'gwen', 'iris']
                 from public.group_leaderboard(:'gym_id', 'day', current_date, 10, 0)),
                'the daily board ranks by distance on that day');
select tests.ok((select is_me and rank = 2 and steps = 6000 and distance_meters = 4000
                 from public.group_leaderboard(:'gym_id', 'day', current_date, 10, 0) where username = 'gwen'),
                'it shows steps and distance and marks the caller');
select tests.ok((select estimated from public.group_leaderboard(:'gym_id', 'day', current_date, 10, 0) where username = 'iris'),
                'estimated distance is flagged');
select tests.ok((select distance_meters = 4000 from public.group_leaderboard(:'gym_id', 'week', current_date, 10, 0)
                 where username = 'gwen'), 'the week starts on Monday: last Sunday doesn''t count');
select tests.ok(extract(isodow from current_date) = 1 or
                (select username = 'iris' and rank = 1
                 from public.group_leaderboard(:'gym_id', 'week', current_date, 10, 0) where rank = 1),
                'the weekly board adds up the days since Monday');
select tests.fails(format('select * from public.group_leaderboard(%L, ''day'', current_date - 3, 10, 0)', :'gym_id'),
                   'invalid_day', 'a board can only be read for today');
select tests.ok((select total = 3 from public.group_leaderboard(:'gym_id', 'day', current_date, 1, 0) limit 1),
                'every row carries the member count');
select tests.ok(tests.count(format('select * from public.group_leaderboard(%L, ''day'', current_date, 1, 0)', :'gym_id')) = 2,
                'a page of one still includes the caller''s own row');
select tests.ok((select array_agg(username order by rank) = array['gwen', 'iris']
                 from public.group_leaderboard(:'gym_id', 'day', current_date, 1, 2)),
                'later pages work, with the caller pinned');
select tests.ok(tests.count(format('select * from public.group_member_list(%L, 2, 0)', :'gym_id')) = 2
                and tests.count(format('select * from public.group_member_list(%L, 2, 2)', :'gym_id')) = 1,
                'the member list pages');
reset role;

update public.profiles set share_progress = false where id = tests.id('iris');
select tests.as_user('gwen');
select tests.ok((select not sharing and distance_meters is null and rank = 3
                 from public.group_leaderboard(:'gym_id', 'day', current_date, 10, 0) where username = 'iris'),
                'members who don''t share are listed without numbers');
reset role;
update public.profiles set share_progress = true where id = tests.id('iris');

-- Privacy -----------------------------------------------------------------------------

select tests.as_user('kurt');
select tests.fails(format('select * from public.group_leaderboard(%L, ''day'', current_date, 10, 0)', :'gym_id'),
                   'group_not_found', 'outsiders can''t read the leaderboard');
select tests.fails(format('select * from public.group_member_list(%L, 10, 0)', :'gym_id'), 'group_not_found',
                   'or the member list');
select tests.fails($$select * from public.groups$$, 'permission denied', 'groups are never read directly');
select tests.fails($$select * from public.group_members$$, 'permission denied', 'nor memberships');
select tests.fails(format('insert into public.group_members (group_id, user_id) values (%L, auth.uid())', :'gym_id'),
                   'permission denied', 'no joining around the rules');
select tests.fails(format('select public.regenerate_group_code(%L)', :'gym_id'), 'group_not_found',
                   'outsiders can''t manage a group');
reset role;
select tests.as_anon();
select tests.fails($$select * from public.my_groups()$$, 'permission denied', 'anon can''t call group functions');
reset role;

-- Management ----------------------------------------------------------------------------

select tests.as_user('hugo');
select tests.fails(format('select public.remove_group_member(%L, %L)', :'gym_id', tests.id('iris')), 'not_group_owner',
                   'members can''t remove members');
select tests.fails(format('select public.update_group(%L, ''Hijacked'', '''', ''boot'')', :'gym_id'), 'not_group_owner',
                   'or edit the group');
reset role;

select tests.as_user('gwen');
select public.update_group(:'gym_id', 'Fit4Less Windsor West', 'Mornings at 7', 'compass');
select tests.ok((select name = 'Fit4Less Windsor West' and emblem = 'compass' from public.my_groups()), 'the owner can edit');
select public.regenerate_group_code(:'gym_id') as new_code \gset
select tests.ok(:'new_code' <> :'gym_code' and :'new_code' ~ '^[A-HJ-NP-Z2-9]{6}$', 'the owner can get a new code');
select tests.ok(tests.count(format('select * from public.preview_group(%L)', :'gym_code')) = 0, 'the old code stops working');
select public.remove_group_member(:'gym_id', tests.id('iris'));
select tests.ok((select member_count = 2 from public.my_groups()), 'the owner can remove a member');
reset role;

select tests.as_user('iris');
select tests.fails(format('select * from public.group_leaderboard(%L, ''day'', current_date, 10, 0)', :'gym_id'),
                   'group_not_found', 'a removed member loses access');
reset role;

-- The owner leaving hands the group to the longest-standing member.
select tests.as_user('gwen');
select public.leave_group(:'gym_id');
select tests.ok(tests.count('select * from public.my_groups()') = 0, 'leaving works');
reset role;
select tests.as_user('hugo');
select tests.ok((select is_owner and member_count = 1 from public.my_groups()), 'ownership moves to the next member');
select public.leave_group(:'gym_id');
reset role;
select tests.ok(not exists (select 1 from public.groups where id = :'gym_id'), 'an empty group closes');

-- Five groups at most ----------------------------------------------------------------------

select tests.as_user('lulu');
select tests.give_coins(3000);
select public.create_group(gen_random_uuid(), 'Group ' || n, '', 'boot') from generate_series(1, 5) n;
select tests.ok(tests.count('select * from public.my_groups()') = 5, 'five groups');
select tests.fails($$select public.create_group(gen_random_uuid(), 'Group Six', '', 'boot')$$, 'group_limit',
                   'a sixth can''t be created');
select tests.ok(tests.coins() = 500, 'and isn''t charged');
select join_code as lulu_code from public.my_groups() limit 1 \gset
reset role;
select tests.as_user('kurt');
select public.join_group(:'lulu_code');
reset role;
select tests.as_user('lulu');
select tests.ok(tests.count('select distinct join_code from public.my_groups()') = 5, 'every group has its own code');
reset role;

-- Teams cost 25 -------------------------------------------------------------------------------

insert into tests.users values ('mona', '00000000-0000-0000-0000-000000000028'), ('ned', '00000000-0000-0000-0000-000000000029');
insert into auth.users (id, email) values (tests.id('mona'), 'mona@example.com'), (tests.id('ned'), 'ned@example.com');

select tests.as_user('mona');
select tests.give_coins(24);
select tests.fails($$select public.create_team('Mona Team', gen_random_uuid())$$, 'insufficient_coins',
                   'creating a team needs 25 coins');
select tests.ok(tests.coins() = 24 and tests.count('select * from public.my_team()') = 0, 'and a failed creation takes nothing');
select tests.give_coins(26);
select public.create_team('Mona Team', '00000000-0000-0000-0000-0000000000b1');
select tests.ok(tests.coins() = 25, 'creating a team takes exactly 25 coins');
select tests.ok(public.create_team('Mona Team', '00000000-0000-0000-0000-0000000000b1') =
                (select id from public.my_team()), 'retrying the same request returns the same team');
select tests.ok(tests.coins() = 25, 'and charges nothing again');
select join_code as mona_code from public.my_team() \gset
reset role;

select tests.as_user('ned');
select public.join_team(:'mona_code');
select tests.ok((select member_count = 2 from public.my_team()) and tests.coins() is null, 'joining a team is free');
reset role;
