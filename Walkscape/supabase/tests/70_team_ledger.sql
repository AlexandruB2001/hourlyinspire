-- Team ledger and campsite tests, with their own players: nia and oli start in Campers, pam in Hoppers.
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

insert into tests.users values
    ('nia', '00000000-0000-0000-0000-000000000016'),
    ('oli', '00000000-0000-0000-0000-000000000017'),
    ('pam', '00000000-0000-0000-0000-000000000018');
insert into auth.users (id, email) select id, name || '@example.com' from tests.users where name in ('nia', 'oli', 'pam');
update public.profiles set username = (select name from tests.users where id = profiles.id)
where id in (tests.id('nia'), tests.id('oli'), tests.id('pam'));

select tests.as_user('nia');
select public.create_team('Campers');
select join_code as campers_code from public.my_team() \gset
reset role;
select tests.as_user('oli');
select public.join_team(:'campers_code');
reset role;

insert into public.daily_progress (user_id, local_date, time_zone, steps, distance_meters, distance_source, client_updated_at)
values (tests.id('nia'), current_date, 'UTC', 40000, 30000, 'recorded', now()),
       (tests.id('nia'), current_date - 3, 'UTC', 9000, 7000, 'recorded', now()),
       (tests.id('oli'), current_date, 'UTC', 7000, 5000, 'recorded', now());

select tests.as_user('nia');
select public.sync_team_contributions();
select public.sync_team_contributions();
select tests.ok((select total_meters from public.my_team()) = 30000,
                'days since joining count once, capped at 25 km a day; days before joining don''t');
reset role;

-- Leaving keeps your past days with the team.
select tests.as_user('oli');
select public.leave_team();
reset role;
select tests.as_user('nia');
select tests.ok((select total_meters from public.my_team()) = 30000, 'the team total never goes down when someone leaves');
select tests.ok((select not is_member and meters = 5000 from public.team_contribution_totals() where username = 'oli'),
                'past members are still listed with what they walked');
reset role;

-- Switching teams doesn't count the same day twice.
select tests.as_user('pam');
select public.create_team('Hoppers');
select join_code as hoppers_code from public.my_team() \gset
reset role;
select tests.as_user('oli');
select public.join_team(:'hoppers_code');
reset role;
update public.daily_progress set distance_meters = 8000 where user_id = tests.id('oli') and local_date = current_date;
select tests.as_user('oli');
select public.sync_team_contributions();
select tests.ok((select total_meters from public.my_team()) = 0, 'a day already credited to another team stays there');
reset role;
select tests.ok((select meters from public.team_contributions where user_id = tests.id('oli') and local_date = current_date) = 5000,
                'and is not topped up for the new team');

-- Tomorrow's walk counts for the new team.
insert into public.daily_progress (user_id, local_date, time_zone, steps, distance_meters, distance_source, client_updated_at)
values (tests.id('oli'), current_date + 1, 'UTC', 3000, 2000, 'recorded', now());
select tests.as_user('pam');
select public.sync_team_contributions();
select tests.ok((select total_meters from public.my_team()) = 2000, 'new days count for the new team');
reset role;

-- ---------------------------------------------------------------- campsite
select tests.as_user('nia');
select tests.ok(cardinality(public.my_campsite()) = 0, 'a new campsite is empty');
select public.set_campsite_decorations(array['lantern', 'tent']);
select tests.ok(public.my_campsite() = array['lantern', 'tent'], 'members place decorations');
select tests.fails($$select public.set_campsite_decorations(array['Bad Deco'])$$, 'invalid_decoration', 'decoration ids are checked');
select tests.fails($$select public.set_campsite_decorations(array['a','b','c','d','e','f','g','h','i'])$$, 'team_campsites_size',
                   'at most eight decorations');
select tests.fails($$select * from public.team_campsites$$, 'permission denied', 'campsites are only read through my_campsite');
reset role;

select tests.as_user('pam');
select tests.ok(cardinality(public.my_campsite()) = 0, 'other teams have their own campsite');
reset role;

-- A deleted team keeps its days blocked, so they can't be re-credited elsewhere.
select tests.as_user('nia');
select public.leave_team();
reset role;
select tests.ok((select team_id is null from public.team_contributions where user_id = tests.id('nia') and local_date = current_date),
                'when a team is deleted its days stay claimed');

select tests.ok(not has_function_privilege('anon', 'public.sync_team_contributions()', 'execute'), 'anon cannot sync teams');
