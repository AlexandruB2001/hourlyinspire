-- Walkscape database tests. Run with supabase/tests/run.sh.
\set ON_ERROR_STOP on
set client_min_messages = notice;

-- Fixtures: four users. The trigger should give each a profile.
insert into tests.users values
    ('alice', '00000000-0000-0000-0000-00000000000a'),
    ('bob',   '00000000-0000-0000-0000-00000000000b'),
    ('carol', '00000000-0000-0000-0000-00000000000c'),
    ('dave',  '00000000-0000-0000-0000-00000000000d');
insert into auth.users (id, email) select id, name || '@example.com' from tests.users;

select tests.ok((select count(*) from public.profiles) = 4, 'a profile is created for every new user');
update public.profiles set username = (select name from tests.users where id = profiles.id);

-- ---------------------------------------------------------------- anonymous
select tests.as_anon();
select tests.fails('select * from public.profiles', 'permission denied', 'anon cannot read profiles');
select tests.fails('select * from public.daily_progress', 'permission denied', 'anon cannot read progress');
select tests.fails($$select public.send_friend_request('bob')$$, 'permission denied', 'anon cannot call the API');
reset role;

-- ----------------------------------------------------------------- profiles
select tests.as_user('alice');
select tests.ok(tests.count('select * from public.profiles') = 4, 'signed-in users can look up profiles');
select tests.ok(not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name ilike '%mail%'),
    'profiles expose no e-mail column');
select tests.fails('select * from auth.users', 'permission denied', 'users cannot read auth.users (e-mails)');

select tests.ok((public.update_my_profile('Alice_W', 'sky', null)).username = 'alice_w',
                'usernames are trimmed and lower-cased');
select tests.fails($$select public.update_my_profile('bob')$$, 'username_taken', 'usernames are unique');
select tests.fails($$select public.update_my_profile('no spaces!')$$, 'invalid_username', 'username format is enforced');
update public.profiles set username = 'hacked' where id = tests.id('bob');
reset role;
select tests.ok((select username from public.profiles where id = tests.id('bob')) = 'bob',
                'users cannot edit someone else''s profile');
select tests.as_user('alice');
select tests.fails($$update public.profiles set created_at = now() - interval '1 year' where id = auth.uid()$$,
                   'permission denied', 'users can only edit username, avatar and sharing');
select public.update_my_profile('alice');
reset role;

-- ------------------------------------------------------------ friendships
select tests.as_user('alice');
select tests.fails($$select public.send_friend_request('alice')$$, 'cannot_friend_self', 'no self-friendship');
select tests.fails($$select public.send_friend_request('nobody')$$, 'user_not_found', 'unknown usernames are rejected');
select public.send_friend_request('bob');
select tests.fails($$select public.send_friend_request('BOB')$$, 'request_already_pending', 'no duplicate requests');
select tests.fails(
    $$insert into public.friendships (requester_id, addressee_id, status) values (auth.uid(), tests.id('carol'), 'accepted')$$,
    'row-level security', 'requests cannot be inserted as already accepted');
select tests.fails(
    $$insert into public.friendships (requester_id, addressee_id) values (tests.id('bob'), tests.id('carol'))$$,
    'row-level security', 'requests cannot be sent on someone else''s behalf');
select tests.ok(tests.count($$select * from public.pending_friend_requests() where direction = 'outgoing'$$) = 1,
                'sender sees the outgoing request');
select tests.fails(
    format($$select public.respond_to_friend_request(%L, true)$$, (select id from public.friendships limit 1)),
    'request_not_found', 'the sender cannot accept their own request');
reset role;

select tests.as_user('carol');
select tests.ok(tests.count('select * from public.friendships') = 0, 'outsiders cannot see others'' friendships');
select tests.fails($$update public.friendships set status = 'accepted'$$, 'permission denied',
                   'outsiders cannot accept others'' requests');
reset role;

select tests.as_user('bob');
select tests.ok(tests.count($$select * from public.pending_friend_requests() where direction = 'incoming'$$) = 1,
                'recipient sees the incoming request');
select tests.fails($$update public.friendships set status = 'accepted'$$, 'permission denied',
                   'status cannot be changed directly');
select public.respond_to_friend_request((select id from public.friendships limit 1), true);
select tests.ok(tests.count('select * from public.friend_daily_summaries(current_date)') = 1,
                'accepting creates the friendship');
select tests.fails($$select public.send_friend_request('alice')$$, 'already_friends', 'no duplicate friendships');
reset role;

-- A crossed request is accepted automatically.
select tests.as_user('carol');
select public.send_friend_request('alice');
reset role;
select tests.as_user('alice');
select public.send_friend_request('carol');
select tests.ok(tests.count('select * from public.friend_daily_summaries(current_date)') = 2,
                'requesting someone who already asked you accepts their request');
reset role;

-- ---------------------------------------------------------- daily progress
select tests.as_user('bob');
select public.upsert_daily_progress(current_date, 'Europe/London', 3690, 2800, 'recorded', now() - interval '1 minute');
select tests.ok((select distance_meters from public.friend_daily_summaries(current_date) where username = 'alice') is null,
                'friends without data today have null totals');
-- Same upload again: idempotent.
select public.upsert_daily_progress(current_date, 'Europe/London', 3690, 2800, 'recorded', now() - interval '1 minute');
select tests.ok(tests.count('select * from public.daily_progress where user_id = auth.uid()') = 1,
                'repeated uploads do not create duplicates');
-- An older upload arriving late is ignored.
select public.upsert_daily_progress(current_date, 'Europe/London', 100, 80, 'recorded', now() - interval '1 hour');
select tests.ok((select distance_meters from public.daily_progress where user_id = auth.uid()) = 2800,
                'out-of-order uploads do not overwrite newer totals');
select public.upsert_daily_progress(current_date, 'Europe/London', 4000, 3050, 'recorded', now());
select tests.ok((select distance_meters from public.daily_progress where user_id = auth.uid()) = 3050,
                'newer uploads replace the totals');

select tests.fails($$select public.upsert_daily_progress(current_date, 'UTC', 10, 999999, 'recorded', now())$$,
                   'daily_progress_distance_range', 'implausible distances are rejected');
select tests.fails($$select public.upsert_daily_progress(current_date - 30, 'UTC', 10, 10, 'recorded', now())$$,
                   'local_date_out_of_range', 'old dates are rejected');
select tests.fails($$select public.upsert_daily_progress(current_date + 5, 'UTC', 10, 10, 'recorded', now())$$,
                   'local_date_out_of_range', 'future dates are rejected');
select tests.fails($$select public.upsert_daily_progress(current_date, 'UTC', 10, 10, 'recorded', now() + interval '1 day')$$,
                   'client_timestamp_in_future', 'future timestamps are rejected');
select tests.fails(
    $$insert into public.daily_progress (user_id, local_date, time_zone, steps, distance_meters, distance_source, client_updated_at)
      values (tests.id('alice'), current_date, 'UTC', 1, 1, 'recorded', now())$$,
    'row-level security', 'users cannot write someone else''s progress');
reset role;

select tests.as_user('alice');
select tests.ok((select distance_meters from public.friend_daily_summaries(current_date) where username = 'bob') = 3050,
                'friends can read each other''s daily totals');
update public.daily_progress set distance_meters = 1 where user_id = tests.id('bob');
delete from public.daily_progress where user_id = tests.id('bob');
reset role;
-- (RLS filters these to zero rows rather than raising.)
select tests.ok((select distance_meters from public.daily_progress where user_id = tests.id('bob')) = 3050,
                'friends cannot modify or delete each other''s progress');

select tests.as_user('dave');
select tests.ok(tests.count('select * from public.daily_progress') = 0, 'non-friends cannot read progress');
select tests.ok(tests.count('select * from public.friend_daily_summaries(current_date)') = 0, 'non-friends get no summaries');
reset role;

-- Turning sharing off hides totals from friends but not from yourself.
select tests.as_user('bob');
select public.update_my_profile(p_share_progress => false);
select tests.ok(tests.count('select * from public.daily_progress') = 1, 'owners always see their own progress');
reset role;
select tests.as_user('alice');
select tests.ok((select distance_meters from public.friend_daily_summaries(current_date) where username = 'bob') is null,
                'friends cannot read progress when sharing is off');
reset role;
select tests.as_user('bob');
select public.update_my_profile(p_share_progress => true);
reset role;

-- -------------------------------------------------- removing and blocking
select tests.as_user('alice');
select public.remove_friend(tests.id('carol'));
select tests.ok(tests.count('select * from public.friend_daily_summaries(current_date)') = 1, 'friends can be removed');
reset role;

select tests.as_user('bob');
select public.block_user(tests.id('alice'));
select tests.ok(tests.count('select * from public.friend_daily_summaries(current_date)') = 0, 'blocking removes the friendship');
reset role;
select tests.as_user('alice');
select tests.ok(tests.count($$select * from public.profiles where username = 'bob'$$) = 0,
                'blocked users cannot see the blocker''s profile');
select tests.fails($$select public.send_friend_request('bob')$$, 'user_not_found',
                   'blocked users cannot send requests (and the block is not revealed)');
select tests.fails($$insert into public.friendships (requester_id, addressee_id) values (auth.uid(), tests.id('bob'))$$,
                   'row-level security', 'blocked users cannot bypass the API to send requests');
select tests.ok(tests.count('select * from public.blocks') = 0, 'blocks are private to the blocker');
select tests.ok(tests.count('select * from public.daily_progress where user_id = tests.id(''bob'')') = 0,
                'ex-friends lose access to progress');
reset role;
select tests.as_user('bob');
select public.unblock_user(tests.id('alice'));
reset role;

-- Requests can be cancelled or declined.
select tests.as_user('dave');
select public.send_friend_request('carol');
select public.delete_friend_request((select id from public.pending_friend_requests() limit 1));
select tests.ok(tests.count('select * from public.pending_friend_requests()') = 0, 'outgoing requests can be cancelled');
select public.send_friend_request('carol');
reset role;
select tests.as_user('carol');
select public.respond_to_friend_request((select id from public.pending_friend_requests() limit 1), false);
select tests.ok(tests.count('select * from public.pending_friend_requests()') = 0, 'incoming requests can be declined');
reset role;

-- ------------------------------------------------- reference data & unlocks
select tests.as_user('dave');
select tests.ok(tests.count('select * from public.zone_definitions') = 10, 'zones are readable');
select tests.fails($$insert into public.zone_definitions values ('x', 99, 'x', 'x', 'x', 0, 1, null, null)$$,
                   'permission denied', 'zones are read-only');
insert into public.user_discoveries (user_id, zone_id) values (auth.uid(), 'meadow');
select tests.fails($$insert into public.user_discoveries (user_id, zone_id) values (tests.id('alice'), 'meadow')$$,
                   'row-level security', 'users cannot record discoveries for others');
reset role;
select tests.as_user('alice');
select tests.ok(tests.count('select * from public.user_discoveries') = 0, 'discoveries are private');
reset role;

-- --------------------------------------------------------- account deletion
select tests.as_user('carol');
select public.delete_account();
reset role;
select tests.ok(not exists (select 1 from auth.users where id = tests.id('carol')), 'account deletion removes the auth user');
select tests.ok(not exists (select 1 from public.profiles where id = tests.id('carol')), 'account deletion removes the profile');
select tests.ok(not exists (select 1 from public.friendships where tests.id('carol') in (requester_id, addressee_id)),
                'account deletion removes friendships');
select tests.ok((select count(*) from auth.users) = 3, 'account deletion only deletes the caller');

-- ------------------------------------------------------------- privileges
select tests.ok(not has_function_privilege('authenticated', 'public.handle_new_user()', 'execute'),
                'internal trigger functions are not callable');
select tests.ok(not has_function_privilege('anon', 'public.delete_account()', 'execute'),
                'anon cannot call account deletion');
