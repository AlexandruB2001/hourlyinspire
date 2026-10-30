-- Team world unlock tests, with their own players: quin and remy share a team, sol has none.
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

insert into tests.users values
    ('quin', '00000000-0000-0000-0000-000000000019'),
    ('remy', '00000000-0000-0000-0000-000000000020'),
    ('sol', '00000000-0000-0000-0000-000000000021');
insert into auth.users (id, email) select id, name || '@example.com' from tests.users where name in ('quin', 'remy', 'sol');
update public.profiles set username = (select name from tests.users where id = profiles.id)
where id in (tests.id('quin'), tests.id('remy'), tests.id('sol'));

select tests.as_user('quin');
select public.create_team('Wayfarers');
select id as wayfarers_id, join_code as wayfarers_code from public.my_team() \gset
select tests.ok(tests.count('select * from public.record_team_world_unlocks()') = 0, 'nothing is unlocked before 100 km');
reset role;
select tests.as_user('remy');
select public.join_team(:'wayfarers_code');
reset role;

-- 9 days of 25 km: 225 km, past the Moonlit Gate (100 km) and Glowcap Glade (200 km).
insert into public.team_contributions (user_id, local_date, team_id, meters)
select tests.id('quin'), current_date - n, :'wayfarers_id', 25000 from generate_series(1, 9) n;

select tests.as_user('remy');
select tests.ok(tests.count('select * from public.record_team_world_unlocks()') = 2, 'every member can record the reached zones');
select tests.ok(tests.count('select * from public.record_team_world_unlocks()') = 2, 'recording again changes nothing');
select tests.ok((select array_agg(zone_id order by zone_id) from public.record_team_world_unlocks()) = array['ef-gate', 'ef-glade'],
                'the zones within the team''s ledger distance');
select tests.fails($$select * from public.team_world_unlocks$$, 'permission denied', 'the table is never read directly');
select tests.fails($$insert into public.team_world_unlocks values ('00000000-0000-0000-0000-000000000000', 'ak-castle', now())$$,
                   'permission denied', 'players cannot unlock zones themselves');
reset role;

select tests.as_user('sol');
select tests.ok(tests.count('select * from public.record_team_world_unlocks()') = 0, 'players without a team see nothing');
reset role;

select tests.ok((select count(*) from public.team_world_zones) = 21, 'every zone of the five worlds');
select tests.ok(not has_function_privilege('anon', 'public.record_team_world_unlocks()', 'execute'), 'anon cannot record unlocks');
