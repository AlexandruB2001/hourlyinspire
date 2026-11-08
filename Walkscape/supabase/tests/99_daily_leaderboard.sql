-- The Daily Leaderboard: ranking, privacy, blocks and held days.
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

insert into tests.users values
    ('lb_ana', '00000000-0000-0000-0000-000000000070'),
    ('lb_ben', '00000000-0000-0000-0000-000000000071'),
    ('lb_cid', '00000000-0000-0000-0000-000000000072'),
    ('lb_dee', '00000000-0000-0000-0000-000000000073'),
    ('lb_eve', '00000000-0000-0000-0000-000000000074'),
    ('lb_fay', '00000000-0000-0000-0000-000000000075'),
    ('lb_gus', '00000000-0000-0000-0000-000000000076'),
    ('lb_hal', '00000000-0000-0000-0000-000000000077');
insert into auth.users (id, email)
select id, name || '@example.com' from tests.users where name like 'lb_%';
update public.profiles set username = (select name from tests.users where id = profiles.id)
where id in (select id from tests.users where name like 'lb_%');

-- Only this file's walkers count today.
delete from public.daily_progress where local_date = current_date
    and user_id not in (select id from tests.users where name like 'lb_%');

insert into public.daily_progress (user_id, local_date, time_zone, steps, distance_meters, distance_source, client_updated_at)
values (tests.id('lb_ana'), current_date, 'UTC', 14000, 10000, 'recorded', now()),
       (tests.id('lb_ben'), current_date, 'UTC', 12000, 9000, 'recorded', now()),
       (tests.id('lb_cid'), current_date, 'UTC', 11000, 8000, 'recorded', now()),
       (tests.id('lb_dee'), current_date, 'UTC', 3000, 2000, 'recorded', now()),
       -- Estimated distances aren't ranked.
       (tests.id('lb_eve'), current_date, 'UTC', 30000, 14000, 'estimatedFromSteps', now()),
       -- 40 km on 100 steps is held.
       (tests.id('lb_fay'), current_date, 'UTC', 100, 40000, 'recorded', now());

select tests.as_anon();
select tests.fails($$select * from public.daily_leaderboard(current_date, 3)$$, 'permission denied',
                   'signed-out callers can''t read the leaderboard');
reset role;

select tests.as_user('lb_dee');
select tests.ok((select array_agg(username order by rank) from public.daily_leaderboard(current_date, 3) where not is_me)
                = array['lb_ana', 'lb_ben', 'lb_cid'], 'the top 3 walkers, longest first');
select tests.ok((select rank = 4 and total = 4 and distance_meters = 2000 and is_me
                 from public.daily_leaderboard(current_date, 3) where is_me), 'and your own position under them');
select tests.ok(tests.count($$select * from public.daily_leaderboard(current_date, 3)$$) = 4, 'four rows, no more');
reset role;

select tests.as_user('lb_ana');
select tests.ok(tests.count($$select * from public.daily_leaderboard(current_date, 3) where is_me$$) = 1,
                'a top walker appears once');
select tests.ok(tests.count($$select * from public.daily_leaderboard(current_date, 3)$$) = 3, 'so no extra row is added');
reset role;

select tests.as_user('lb_gus');
select tests.ok((select rank is null and distance_meters = 0 and total = 4 and not under_review
                 from public.daily_leaderboard(current_date, 3) where is_me), 'no walk yet: a row with no position');
reset role;

select tests.as_user('lb_fay');
select tests.ok((select rank is null and under_review from public.daily_leaderboard(current_date, 3) where is_me),
                'a held day isn''t ranked, and its owner is told');
reset role;

select tests.as_user('lb_ben');
select tests.ok(not exists (select 1 from public.daily_leaderboard(current_date, 100) where username = 'lb_fay'),
                'held days are invisible to others');
select tests.ok(not exists (select 1 from public.daily_leaderboard(current_date, 100) where username = 'lb_eve'),
                'estimated days are not on the board');
select tests.ok(exists (select 1 from public.daily_leaderboard(current_date, 100) where username = 'lb_ana'),
                'before hiding, ana shows');
reset role;

-- Hiding.
select tests.as_user('lb_ana');
select tests.ok(public.set_show_on_leaderboard(false) = false, 'a player can hide');
select tests.ok((select rank = 1 and not shown from public.daily_leaderboard(current_date, 3) where is_me),
                'hidden players still see their own position');
reset role;
select tests.as_user('lb_ben');
select tests.ok(not exists (select 1 from public.daily_leaderboard(current_date, 100) where username = 'lb_ana'),
                'but nobody else sees them');
select tests.ok((select rank = 1 from public.daily_leaderboard(current_date, 3) where is_me), 'and ranks close up');
reset role;
select tests.as_user('lb_ana');
select public.set_show_on_leaderboard(true);
reset role;

-- Turning off sharing hides you too.
update public.profiles set share_progress = false where id = tests.id('lb_cid');
select tests.as_user('lb_ben');
select tests.ok(not exists (select 1 from public.daily_leaderboard(current_date, 100) where username = 'lb_cid'),
                'players who stopped sharing are hidden');
reset role;
update public.profiles set share_progress = true where id = tests.id('lb_cid');

-- Blocks work both ways.
insert into public.blocks (blocker_id, blocked_id) values (tests.id('lb_cid'), tests.id('lb_dee'));
select tests.as_user('lb_dee');
select tests.ok(not exists (select 1 from public.daily_leaderboard(current_date, 100) where username = 'lb_cid'),
                'someone who blocked you isn''t shown');
reset role;
select tests.as_user('lb_cid');
select tests.ok(not exists (select 1 from public.daily_leaderboard(current_date, 100) where username = 'lb_dee'),
                'nor is someone you blocked');
select tests.fails($$select * from public.daily_leaderboard(current_date + 5, 3)$$, 'invalid_day',
                   'only around today can be read');
reset role;
