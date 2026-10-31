-- The live-project repair (supabase/repairs/20261110_migrations_out_of_order.sql)
-- must be safe to run over any partial state: run it twice over a fully
-- migrated database and check everything still works.
\set ON_ERROR_STOP on
set client_min_messages = warning;
reset role;
\i Walkscape/supabase/repairs/20261110_migrations_out_of_order.sql
\i Walkscape/supabase/repairs/20261110_migrations_out_of_order.sql
set client_min_messages = notice;

select tests.ok((select count(*) from pg_trigger where tgname = 'daily_progress_flags') = 1, 'the repair leaves one flag trigger');
select tests.ok((select count(*) from pg_constraint where conrelid = 'public.daily_progress'::regclass and contype = 'c'
                 and pg_get_constraintdef(oid) like '%distance_meters%') = 1, 'and one distance limit');
select tests.ok((select count(*) from pg_constraint where conrelid = 'public.team_contributions'::regclass and contype = 'c'
                 and pg_get_constraintdef(oid) like '%350000%') = 1, 'and the team ledger allows full days');
select tests.as_user('purse');
select version as purse_version from public.get_player_save() \gset
select tests.ok(public.put_player_save((select save from public.get_player_save()), :purse_version) = :purse_version + 1,
                'saving works after the repair');
select tests.ok((select (save #>> '{wallet,spent,team-00000000-0000-0000-0000-0000000000c1}')::integer = 25
                 from public.get_player_save()), 'with fees still written back');
reset role;
select id as haul_id from public.groups where name = 'Long Haul' \gset
select tests.as_user('walk5');
select tests.ok((select count(*) from public.group_leaderboard(:'haul_id', 'day', current_date, 100, 0)) = 7
                and (select distance_meters from public.group_leaderboard(:'haul_id', 'day', current_date, 100, 0)
                     where username = 'walk100') = 100000,
                'group leaderboards still count full days');
reset role;
