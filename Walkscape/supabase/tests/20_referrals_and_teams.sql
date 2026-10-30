-- Referral and team tests. Runs after 10_rls_and_api.sql (alice, bob and dave exist; carol was deleted).
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

insert into tests.users values
    ('erin',  '00000000-0000-0000-0000-00000000000e'),
    ('frank', '00000000-0000-0000-0000-00000000000f'),
    ('gina',  '00000000-0000-0000-0000-000000000010');
insert into auth.users (id, email) select id, name || '@example.com' from tests.users where name in ('erin', 'frank', 'gina');
update public.profiles set username = (select name from tests.users where id = profiles.id)
where id in (tests.id('erin'), tests.id('frank'), tests.id('gina'));

select tests.ok((select count(*) from public.profiles where referral_code ~ '^[0-9A-F]{8}$') = (select count(*) from public.profiles),
                'every profile gets an 8-character referral code');
select tests.ok((select count(distinct referral_code) from public.profiles) = (select count(*) from public.profiles),
                'referral codes are unique');
select referral_code as alice_code from public.profiles where id = tests.id('alice') \gset
select referral_code as erin_code from public.profiles where id = tests.id('erin') \gset

-- ---------------------------------------------------------------- referrals
select tests.as_user('erin');
select tests.fails(format('select public.redeem_referral_code(%L)', :'erin_code'), 'own_code', 'you cannot use your own code');
select tests.fails($$select public.redeem_referral_code('NOPE1234')$$, 'code_not_found', 'unknown codes are rejected');
select public.redeem_referral_code(lower(substr(:'alice_code', 1, 4)) || ' ' || substr(:'alice_code', 5));
select tests.ok((select has_redeemed from public.my_referral_status()), 'codes are accepted in any case and spacing');
select tests.fails(format('select public.redeem_referral_code(%L)', :'alice_code'), 'already_redeemed', 'a code can only be used once');
select tests.fails($$insert into public.referrals (referrer_id, referred_id) values (tests.id('erin'), tests.id('bob'))$$,
                   'permission denied', 'referrals can only be created through redeem_referral_code');
reset role;

select tests.as_user('alice');
select tests.fails(format('select public.redeem_referral_code(%L)', :'erin_code'), 'circular_referral',
                   'you cannot use the code of someone you invited');
reset role;

update public.profiles set created_at = now() - interval '30 days' where id = tests.id('frank');
select tests.as_user('frank');
select tests.fails(format('select public.redeem_referral_code(%L)', :'alice_code'), 'account_too_old',
                   'only new accounts can use a referral code');
select tests.ok(not (select can_redeem from public.my_referral_status()), 'old accounts are told they cannot redeem');
reset role;

select tests.as_user('alice');
select tests.ok(tests.count('select * from public.ready_referral_chests()') = 0, 'no chest before the invitee walks');
select tests.ok((select progress from public.my_referral_invitees()) = 0, 'invitee progress starts at zero');
reset role;

-- The invitee walks 3 km today: one day isn't enough.
select tests.as_user('erin');
select public.upsert_daily_progress(current_date, 'UTC', 4000, 3000, 'recorded', now());
reset role;
select tests.as_user('alice');
select tests.ok(tests.count('select * from public.ready_referral_chests()') = 0, 'walking on one day does not qualify');
reset role;

-- ...and 2.5 km yesterday: 5.5 km over two days qualifies.
update public.referrals set created_at = now() - interval '3 days' where referred_id = tests.id('erin');
select tests.as_user('erin');
select public.upsert_daily_progress(current_date - 1, 'UTC', 3300, 2500, 'recorded', now());
reset role;
select tests.as_user('alice');
select reward_coins as first_reward from public.ready_referral_chests() \gset
select tests.ok(:first_reward between 25 and 100, 'a qualified referral gives a 25-100 coin chest');
select tests.ok((select reward_coins from public.ready_referral_chests()) = :first_reward,
                'the reward is decided once and returned unchanged');
select tests.ok((select qualified from public.my_referral_invitees()), 'the invitee shows as qualified');
reset role;

select tests.as_user('bob');
select tests.ok(tests.count('select * from public.referrals') = 0, 'others cannot see your referrals');
select tests.ok(tests.count('select * from public.ready_referral_chests()') = 0, 'others get no chest');
reset role;

select tests.as_user('erin');
select public.mark_referral_chest_opened((select id from public.referrals where referred_id = tests.id('erin')));
reset role;
select tests.ok((select opened_at from public.referrals where referred_id = tests.id('erin')) is null,
                'only the referrer can open their chest');
select tests.as_user('alice');
select public.mark_referral_chest_opened((select id from public.ready_referral_chests() limit 1));
select tests.ok(tests.count('select * from public.ready_referral_chests()') = 0, 'an opened chest is never offered again');
reset role;

-- --------------------------------------------------------------------- teams
select tests.as_user('bob');
select tests.fails($$select public.create_team('x')$$, 'invalid_team_name', 'team names need 3-24 characters');
reset role;

select tests.as_user('alice');
select public.create_team('  Trail   Blazers ');
select tests.ok((select name from public.my_team()) = 'Trail Blazers', 'team names are tidied');
select tests.ok((select is_owner and member_count = 1 from public.my_team()), 'the creator owns a one-person team');
select tests.fails($$select public.create_team('Second Team')$$, 'already_in_team', 'a walker can be in one team at a time');
select join_code as team_code from public.my_team() \gset
reset role;

select tests.as_user('bob');
select public.join_team(lower(:'team_code'));
select tests.ok((select member_count from public.my_team()) = 2, 'join codes work in any case');
select tests.fails(format('select public.join_team(%L)', :'team_code'), 'already_in_team', 'joining twice is rejected');
reset role;

select tests.as_user('dave');
select tests.fails($$select public.join_team('ZZZZZZ')$$, 'team_not_found', 'unknown join codes are rejected');
select tests.ok(tests.count('select * from public.teams') = 0, 'outsiders cannot see teams');
select tests.ok(tests.count('select * from public.team_member_days(current_date, current_date)') = 0,
                'outsiders cannot see team members');
select tests.fails($$insert into public.team_members (team_id, user_id) select id, auth.uid() from public.teams$$,
                   'permission denied', 'memberships can only change through the API');
reset role;

-- Invites go to friends only.
insert into public.friendships (requester_id, addressee_id, status)
values (tests.id('alice'), tests.id('frank'), 'accepted'), (tests.id('alice'), tests.id('gina'), 'accepted');
select tests.as_user('alice');
select tests.fails(format('select public.invite_friend_to_team(%L)', tests.id('erin')), 'not_friends', 'only friends can be invited');
select public.invite_friend_to_team(tests.id('frank'));
select public.invite_friend_to_team(tests.id('frank'));
select public.invite_friend_to_team(tests.id('gina'));
reset role;
select tests.ok((select count(*) from public.team_invites where invitee_id = tests.id('frank')) = 1, 'invites are not duplicated');

select tests.as_user('gina');
select public.respond_to_team_invite((select id from public.my_team_invites()), false);
select tests.ok(tests.count('select * from public.my_team_invites()') = 0, 'declined invites disappear');
select tests.ok(tests.count('select * from public.my_team()') = 0, 'declining does not join');
reset role;

select tests.as_user('frank');
select tests.ok((select team_name from public.my_team_invites()) = 'Trail Blazers', 'invitees see the team name');
select public.respond_to_team_invite((select id from public.my_team_invites()), true);
select tests.ok((select member_count from public.my_team()) = 3, 'accepting an invite joins the team');
reset role;

-- Shared totals respect each member's sharing setting.
update public.profiles set share_progress = false where id = tests.id('frank');
select tests.as_user('bob');
select public.upsert_daily_progress(current_date, 'UTC', 5300, 4000, 'recorded', now());
reset role;
select tests.as_user('frank');
select public.upsert_daily_progress(current_date, 'UTC', 8000, 6000, 'recorded', now());
select tests.ok((select day_meters from public.team_member_days(current_date, date_trunc('week', current_date)::date)
                 where user_id = tests.id('frank')) = 6000, 'members always see their own totals');
reset role;

select tests.as_user('alice');
select tests.ok((select day_meters from public.team_member_days(current_date, date_trunc('week', current_date)::date)
                 where user_id = tests.id('bob')) = 4000, 'teammates see each other''s daily distance');
select tests.ok((select week_meters from public.team_member_days(current_date, date_trunc('week', current_date)::date)
                 where user_id = tests.id('bob')) >= 4000, 'teammates see weekly distance');
select tests.ok((select day_meters is null and week_meters is null
                 from public.team_member_days(current_date, date_trunc('week', current_date)::date)
                 where user_id = tests.id('frank')), 'members who stopped sharing show no totals');
select public.sync_team_contributions();
select total_meters as alice_team_total from public.my_team() \gset
reset role;
select coalesce(sum(least(d.distance_meters, 25000)), 0) as expected_total
from public.team_members m
join public.profiles p on p.id = m.user_id
join public.daily_progress d on d.user_id = m.user_id
where m.team_id = (select id from public.teams where name = 'Trail Blazers')
  and p.share_progress
  and d.local_date between (m.joined_at at time zone 'utc')::date and current_date + 1 \gset
select tests.ok(:alice_team_total = :expected_total, 'expedition distance adds up members who share (team ledger)');

select coalesce(sum(d.distance_meters), 0) as expected_week
from public.team_members m
join public.profiles p on p.id = m.user_id
join public.daily_progress d on d.user_id = m.user_id
where m.team_id = (select id from public.teams where name = 'Trail Blazers')
  and p.share_progress
  and d.local_date between date_trunc('week', current_date)::date and date_trunc('week', current_date)::date + 6 \gset
select tests.ok(:expected_week >= 4000, 'fixture: the team walked this week');

select tests.as_user('dave');
select tests.ok((select week_meters from public.team_week_standings(date_trunc('week', current_date)::date)
                 where name = 'Trail Blazers') = :expected_week,
                'standings show combined weekly distance of sharing members only');
reset role;

-- Leaving hands ownership on; the last one out deletes the team.
select tests.as_user('alice');
select public.leave_team();
reset role;
select tests.ok((select owner_id from public.teams where name = 'Trail Blazers') = tests.id('bob'),
                'the longest-standing member becomes owner');
select tests.as_user('bob');
select public.leave_team();
reset role;
select tests.as_user('frank');
select public.leave_team();
select tests.fails($$select public.leave_team()$$, 'not_in_team', 'you cannot leave a team you are not in');
reset role;
select tests.ok(not exists (select 1 from public.teams where name = 'Trail Blazers'), 'an empty team is deleted');

-- ------------------------------------------------------------- privileges
select tests.ok(not has_function_privilege('authenticated', 'public.shared_meters(uuid, date, date)', 'execute'),
                'internal helpers are not callable');
select tests.ok(not has_function_privilege('anon', 'public.create_team(text)', 'execute'), 'anon cannot create teams');
select tests.ok(not has_function_privilege('anon', 'public.redeem_referral_code(text)', 'execute'), 'anon cannot redeem codes');
