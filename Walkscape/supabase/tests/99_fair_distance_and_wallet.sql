-- No daily distance cap, plausibility checks, and wallet tampering, with their
-- own players: five walkers of 5, 25, 42.2, 60 and 100 km today, `weekly`
-- (two days this week), `stridey` (an impossible day) and `purse` (wallet).
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

insert into tests.users values
    ('walk5',   '00000000-0000-0000-0000-000000000040'),
    ('walk25',  '00000000-0000-0000-0000-000000000041'),
    ('walk42',  '00000000-0000-0000-0000-000000000042'),
    ('walk60',  '00000000-0000-0000-0000-000000000043'),
    ('walk100', '00000000-0000-0000-0000-000000000044'),
    ('weekly',  '00000000-0000-0000-0000-000000000045'),
    ('stridey', '00000000-0000-0000-0000-000000000046'),
    ('purse',   '00000000-0000-0000-0000-000000000047'),
    ('ultra',   '00000000-0000-0000-0000-000000000048');
insert into auth.users (id, email)
select id, name || '@example.com' from tests.users
where name in ('walk5', 'walk25', 'walk42', 'walk60', 'walk100', 'weekly', 'stridey', 'purse', 'ultra');
update public.profiles set username = (select name from tests.users where id = profiles.id)
where id in (select id from tests.users
             where name in ('walk5', 'walk25', 'walk42', 'walk60', 'walk100', 'weekly', 'stridey', 'purse', 'ultra'));

-- Plausibility rules (fixed clock) --------------------------------------------

select tests.ok(public.progress_review_reason('2026-11-10', 'UTC', 18000, 14000, '2026-11-10 00:30+00') is null,
                'days under 15 km are never held');
select tests.ok(public.progress_review_reason('2026-11-10', 'UTC', 56000, 42195, '2026-11-10 04:00+00') is null,
                'a marathon by 4 am is plausible');
select tests.ok(public.progress_review_reason('2026-11-10', 'UTC', 140000, 100000, '2026-11-10 20:00+00') is null,
                '100 km by the evening is plausible');
select tests.ok(public.progress_review_reason('2026-11-10', 'UTC', 215000, 160934, '2026-11-10 23:30+00') is null,
                'a 100-mile ultra in a day is plausible');
select tests.ok(public.progress_review_reason('2026-11-10', 'UTC', 290000, 300000, '2026-11-11 10:00+00') is null,
                'a 300 km day uploaded afterwards is plausible');
select tests.ok(public.progress_review_reason('2026-11-10', 'UTC', 140000, 100000, '2026-11-10 03:00+00') = 'too_fast',
                '100 km by 3 am is held');
select tests.ok(public.progress_review_reason('2026-11-10', 'Pacific/Kiritimati', 140000, 100000, '2026-11-10 03:00+00') is null,
                'local midnight comes from the day''s time zone');
select tests.ok(public.progress_review_reason('2026-11-10', 'UTC', 4000, 60000, '2026-11-10 22:00+00') = 'stride',
                '60 km in 4,000 steps is held');
select tests.ok(public.progress_review_reason('2026-11-10', 'UTC', 0, 20000, '2026-11-10 22:00+00') = 'stride',
                'long distance with no steps is held');
select tests.ok(public.progress_review_reason('2026-11-10', 'Mars/Olympus', 140000, 100000, '2026-11-10 20:00+00') is null,
                'an unknown time zone is treated leniently');

-- Submissions -----------------------------------------------------------------

select tests.as_user('ultra');
select tests.fails($$select public.upsert_daily_progress(current_date - 1, 'UTC', 10000, 350001, 'recorded', now())$$,
                   'daily_progress_distance_range', 'over 350 km a day is rejected as malformed');
select tests.fails($$select public.upsert_daily_progress(current_date - 1, 'UTC', 300001, 1000, 'recorded', now())$$,
                   'daily_progress_steps_range', 'over 300,000 steps a day is rejected as malformed');
select tests.fails($$select public.upsert_daily_progress(current_date - 1, 'UTC', 100, -5, 'recorded', now())$$,
                   'daily_progress_distance_range', 'negative distance is rejected');
select public.upsert_daily_progress(current_date - 1, 'UTC', 215000, 160934, 'recorded', now());
select tests.ok((select distance_meters from public.daily_progress where user_id = auth.uid() and local_date = current_date - 1)
                = 160934, 'a 100-mile ultra (over the old 150 km limit) is accepted in full');
select public.upsert_daily_progress(current_date - 2, 'UTC', 299000, 350000, 'recorded', now());
select tests.ok((select distance_meters from public.daily_progress where user_id = auth.uid() and local_date = current_date - 2)
                = 350000, 'a 350 km day is accepted, not truncated');
reset role;

-- One group, everyone competing -----------------------------------------------

select tests.as_user('walk100');
select tests.give_coins(600);
select public.create_group(gen_random_uuid(), 'Long Haul', '', 'boot') as haul_id \gset
select join_code as haul_code from public.my_groups() \gset
select public.create_team('Distance Club');
select join_code as club_code from public.my_team() \gset
reset role;

select tests.as_user('walk5');   select public.join_group(:'haul_code'); reset role;
select tests.as_user('walk25');  select public.join_group(:'haul_code'); reset role;
select tests.as_user('walk42');  select public.join_group(:'haul_code'); reset role;
select tests.as_user('walk60');  select public.join_group(:'haul_code'); select public.join_team(:'club_code'); reset role;
select tests.as_user('weekly');  select public.join_group(:'haul_code'); reset role;
select tests.as_user('stridey'); select public.join_group(:'haul_code'); select public.join_team(:'club_code'); reset role;

-- Today in UTC+14, so "since local midnight" is at least 14 hours whatever the
-- time of the test run. Strides are a realistic 0.75 m.
insert into public.daily_progress (user_id, local_date, time_zone, steps, distance_meters, distance_source, client_updated_at)
select tests.id(name), current_date, 'Pacific/Kiritimati', meters * 4 / 3, meters, 'recorded', now()
from (values ('walk5', 5000), ('walk25', 25000), ('walk42', 42195), ('walk60', 60000), ('walk100', 100000)) v (name, meters);
insert into public.daily_progress (user_id, local_date, time_zone, steps, distance_meters, distance_source, client_updated_at)
values (tests.id('stridey'), current_date, 'Pacific/Kiritimati', 4000, 60000, 'recorded', now());

-- `weekly` walks two days of one Monday-to-Sunday week (last week's Saturday
-- and Sunday when today is Monday).
select case when extract(isodow from current_date) = 1 then current_date - 1 else current_date end as week_day \gset
insert into public.daily_progress (user_id, local_date, time_zone, steps, distance_meters, distance_source, client_updated_at)
values (tests.id('weekly'), :'week_day'::date, 'Pacific/Kiritimati', 5300, 4000, 'recorded', now()),
       (tests.id('weekly'), :'week_day'::date - 1, 'Pacific/Kiritimati', 66000, 50000, 'recorded', now());

select tests.as_user('walk5');
select tests.ok((select array_agg(username order by rank)
                 from public.group_leaderboard(:'haul_id', 'day', current_date, 100, 0) where distance_meters >= 5000)
                = array['walk100', 'walk60', 'walk42', 'walk25', 'walk5'], 'the daily board ranks by full distance');
select tests.ok((select array_agg(distance_meters order by rank)
                 from public.group_leaderboard(:'haul_id', 'day', current_date, 100, 0) where distance_meters >= 5000)
                = array[100000, 60000, 42195, 25000, 5000], 'no daily cap: 25, 42.2, 60 and 100 km count in full');
select tests.ok((select distance_meters = 0 and not under_review
                 from public.group_leaderboard(:'haul_id', 'day', current_date, 100, 0) where username = 'stridey'),
                'an impossible day is held off the board, and others aren''t told why');
select tests.ok((select l.rank = (select max(rank) from public.group_leaderboard(:'haul_id', 'day', current_date, 100, 0))
                        and l.total = 7
                 from public.group_leaderboard(:'haul_id', 'day', current_date, 100, 0) l where l.username = 'stridey'),
                'a held walker ranks after everyone with distance');
select tests.ok((select distance_meters = 54000
                 from public.group_leaderboard(:'haul_id', 'week', :'week_day'::date, 100, 0) where username = 'weekly'),
                'the weekly board adds up full days');
select tests.ok((select sum(distance_meters) from public.group_leaderboard(:'haul_id', 'week', :'week_day'::date, 100, 0))
                = (select sum(d.distance_meters) from public.daily_progress d
                   join public.group_members m on m.user_id = d.user_id and m.group_id = :'haul_id'
                   where d.local_date between :'week_day'::date - (extract(isodow from :'week_day'::date)::integer - 1)
                                         and :'week_day'::date
                     and public.progress_review_reason(d.local_date, d.time_zone, d.steps, d.distance_meters,
                                                       d.updated_at) is null),
                'weekly totals are exactly the sum of plausible days');

-- Pagination: pages of two give the same order as one long page, and the
-- caller is pinned on every page.
select tests.ok((select array_agg(username order by rank, username)
                 from public.group_leaderboard(:'haul_id', 'day', current_date, 2, 2))
                = array['walk42', 'walk25', 'walk5'], 'page 2 shows ranks 3-4 with the caller pinned');
select tests.ok((select array_agg(l.username order by o, l.rank, l.username)
                 from generate_series(0, 6, 2) o
                 cross join lateral public.group_leaderboard(:'haul_id', 'day', current_date, 2, o) l
                 where not l.is_me)
                = (select array_agg(username order by rank, username)
                   from public.group_leaderboard(:'haul_id', 'day', current_date, 100, 0) where not is_me),
                'paging through the board gives the same order as one long page');
reset role;

select tests.as_user('stridey');
select tests.ok((select under_review from public.group_leaderboard(:'haul_id', 'day', current_date, 100, 0) where is_me),
                'the walker whose day is held is told it is under review');
reset role;
select tests.ok((select distance_meters from public.daily_progress where user_id = tests.id('stridey') and local_date = current_date)
                = 60000, 'a held day is kept unchanged');
select tests.ok(exists (select 1 from public.progress_flags where user_id = tests.id('stridey') and reason = 'stride'),
                'held days are logged for review');
select tests.ok(exists (select 1 from public.progress_flags where user_id = tests.id('walk100') and reason = 'very_long'),
                'very long days are logged for a look, but still count');

-- Teams: full days, held days not credited until plausible.
select tests.as_user('walk100');
select public.sync_team_contributions();
select tests.ok((select total_meters from public.my_team()) = 160000,
                'the team ledger credits 100 km and 60 km days in full');
select tests.ok((select week_meters from public.team_week_standings(date_trunc('week', current_date)::date)
                 where name = 'Distance Club') = 160000, 'team week standings use full days');
reset role;
select tests.ok(not exists (select 1 from public.team_contributions where user_id = tests.id('stridey')),
                'a held day isn''t credited to the team');
update public.daily_progress set steps = 80000 where user_id = tests.id('stridey') and local_date = current_date;
select tests.as_user('walk100');
select public.sync_team_contributions();
select tests.ok((select total_meters from public.my_team()) = 220000, 'once a later upload is plausible, it counts in full');
reset role;

-- Community goals count full days.
select tests.ok(public.community_distance(current_date, current_date)
                >= 100000 + 60000 + 60000 + 42195 + 25000 + 5000, 'community goals count full days');

-- Wallet -------------------------------------------------------------------------

select tests.as_user('purse');
select tests.give_coins(600);
select public.create_team('Coin Purse', '00000000-0000-0000-0000-0000000000c1');
select tests.ok(tests.coins() = 575, 'creating a team takes 25 coins');
select public.create_team('Coin Purse', '00000000-0000-0000-0000-0000000000c1');
select tests.ok(tests.coins() = 575, 'retrying the same creation charges nothing again');

-- Erasing the charge from the save doesn't refund it.
select save as purse_save, version as purse_version from public.get_player_save() \gset
select public.put_player_save((:'purse_save')::jsonb #- '{wallet,spent}', :purse_version);
select tests.ok((select (save #>> '{wallet,spent,team-00000000-0000-0000-0000-0000000000c1}')::integer = 25
                 from public.get_player_save()), 'a save without the fee gets the fee written back');
select tests.ok(tests.coins() = 575, 'so the client can''t refund a team fee');
select save as purse_save, version as purse_version from public.get_player_save() \gset
select public.put_player_save(jsonb_set((:'purse_save')::jsonb, '{wallet,spent,team-00000000-0000-0000-0000-0000000000c1}', '1'),
                              :purse_version);
select tests.ok(tests.coins() = 575, 'or lower it');
reset role;
select tests.as_user('purse');
select public.leave_team();
select public.create_group('00000000-0000-0000-0000-0000000000c2', 'Purse Strings', '', 'boot');
select tests.ok(tests.coins() = 75, 'creating a group takes 500 coins');
select save as purse_save, version as purse_version from public.get_player_save() \gset
select public.put_player_save((:'purse_save')::jsonb #- '{wallet,spent}', :purse_version);
select tests.fails($$select public.create_group(gen_random_uuid(), 'Second Group', '', 'boot')$$, 'insufficient_coins',
                   'erasing fees from the save doesn''t pay for another group');

-- Malformed wallets are rejected.
select save as purse_save, version as purse_version from public.get_player_save() \gset
select tests.fails(format('select public.put_player_save(%L::jsonb, %s)',
                          jsonb_set((:'purse_save')::jsonb, '{wallet,earned,cheat}', '-5'), :purse_version),
                   'invalid_wallet', 'negative amounts are rejected');
select tests.fails(format('select public.put_player_save(%L::jsonb, %s)',
                          jsonb_set((:'purse_save')::jsonb, '{wallet,earned,cheat}', '"lots"'), :purse_version),
                   'invalid_wallet', 'non-numeric amounts are rejected');
select tests.fails(format('select public.put_player_save(%L::jsonb, %s)',
                          jsonb_set((:'purse_save')::jsonb, '{wallet,earned,cheat}', '1000000000'), :purse_version),
                   'invalid_wallet', 'absurd amounts are rejected');
select tests.fails(format('select public.put_player_save(%L::jsonb, %s)',
                          jsonb_set((:'purse_save')::jsonb, '{wallet,earned}', '[1]'), :purse_version),
                   'invalid_wallet', 'earned must be a map');
select tests.ok(tests.coins() = 75, 'rejected saves change nothing');

-- KNOWN GAPS until the wallet is server-authoritative (docs/BACKEND.md,
-- "Wallet"): the earned side and inventory are still the app's word. These
-- tests document today's behaviour and should flip when that work lands.
select public.put_player_save(jsonb_set((:'purse_save')::jsonb, '{wallet,earned,walk-2026-11-01}', '5000'), :purse_version);
select tests.ok(tests.coins() = 5075, 'KNOWN GAP: a modified client can still add plausible earned entries');
select save as purse_save, version as purse_version from public.get_player_save() \gset
select public.put_player_save(jsonb_set((:'purse_save')::jsonb, '{wallet,ownedItemIDs}', '["golden-crown"]'), :purse_version);
select tests.ok((select save #> '{wallet,ownedItemIDs}' ? 'golden-crown' from public.get_player_save()),
                'KNOWN GAP: a modified client can still add items to its inventory');
reset role;

select tests.ok(not has_table_privilege('authenticated', 'public.coin_charges', 'select')
                and not has_table_privilege('authenticated', 'public.coin_charges', 'insert'),
                'players can''t read or write the charge ledger');
select tests.ok(not has_table_privilege('authenticated', 'public.progress_flags', 'select'),
                'players can''t read review flags');
select tests.ok(not has_function_privilege('authenticated', 'public.charge_coins(uuid, text, integer)', 'execute'),
                'players can''t charge coins directly');
