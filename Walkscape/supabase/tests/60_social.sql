-- Social tests. kim and leo are friends (from 50_profile_showcase.sql); max is a stranger.
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

-- ------------------------------------------------------- shared discoveries
select tests.as_user('kim');
select public.record_discoveries(format('[{"id":"forest-spirit","date":"%s"},{"id":"owl","date":"%s"}]',
                                        current_date, current_date)::jsonb);
select public.record_discoveries(format('[{"id":"forest-spirit","date":"%s"}]', current_date)::jsonb);
select tests.ok(tests.count('select * from public.my_shared_discoveries(current_date - 7)') = 0,
                'nothing is shared until a friend finds the same thing');
select tests.fails(format($$select public.record_discoveries('[{"id":"Bad Id","date":"%s"}]')$$, current_date),
                   'discoveries_id_format', 'bad ids are rejected');
reset role;
select tests.ok((select count(*) from public.discoveries where user_id = tests.id('kim')) = 2,
                'repeated reports are stored once');

select tests.as_user('leo');
select public.record_discoveries(format('[{"id":"forest-spirit","date":"%s"},{"id":"old","date":"%s"}]',
                                        current_date, current_date - 30)::jsonb);
select tests.ok((select friend_username from public.my_shared_discoveries(current_date - 7)
                 where discovery_id = 'forest-spirit') = 'kim',
                'two friends finding the same thing on the same day share it');
reset role;
select tests.ok(not exists (select 1 from public.discoveries where discovery_id = 'old'),
                'old dates are ignored');

select tests.as_user('max');
select public.record_discoveries(format('[{"id":"forest-spirit","date":"%s"}]', current_date)::jsonb);
select tests.ok(tests.count('select * from public.my_shared_discoveries(current_date - 7)') = 0,
                'strangers never show up as shared discoveries');
select tests.fails($$select * from public.discoveries$$, 'permission denied', 'discoveries are never read directly');
reset role;

-- ------------------------------------------------------------- milestones
select tests.as_user('kim');
select public.record_milestones(format('[{"id":"total-10k","date":"%s"}]', current_date)::jsonb);
reset role;

select tests.as_user('leo');
select tests.ok((select milestone_id from public.friend_milestone_feed(current_date - 7) where username = 'kim') = 'total-10k',
                'friends see your milestones');
select public.react_to_milestone(tests.id('kim'), 'total-10k', 'cheer');
select public.react_to_milestone(tests.id('kim'), 'total-10k', 'star');
select tests.ok((select reactions = 1 and my_reaction = 'star' from public.friend_milestone_feed(current_date - 7)
                 where username = 'kim'),
                'one reaction per friend; reacting again changes it');
select tests.fails($$select public.react_to_milestone(tests.id('kim'), 'total-10k', 'boo')$$, 'check constraint',
                   'only the four reactions exist');
reset role;

select tests.as_user('max');
select tests.ok(tests.count('select * from public.friend_milestone_feed(current_date - 7)') = 0,
                'strangers see no milestones');
select tests.fails(format($$select public.react_to_milestone(%L, 'total-10k', 'cheer')$$, tests.id('kim')),
                   'not_friends', 'strangers cannot react');
reset role;

select tests.as_user('kim');
select tests.ok((select reactor_username = 'leo' and reaction = 'star' from public.my_milestone_reactions(now() - interval '1 hour')),
                'you see who cheered you');
select tests.fails(format($$select public.react_to_milestone(%L, 'total-10k', 'cheer')$$, tests.id('kim')),
                   '', 'you cannot react to your own milestone');
reset role;

-- --------------------------------------------------------- walked together
insert into public.daily_progress (user_id, local_date, time_zone, steps, distance_meters, distance_source, client_updated_at)
values (tests.id('kim'), current_date, 'UTC', 6000, 4000, 'recorded', now()),
       (tests.id('leo'), current_date, 'UTC', 9000, 6500, 'recorded', now())
on conflict (user_id, local_date) do update set distance_meters = excluded.distance_meters;
select tests.as_user('kim');
select tests.ok((select meters from public.walked_together() where username = 'leo') = 10500,
                'walked together adds both friends'' distance since becoming friends');
reset role;

select tests.ok(not has_function_privilege('anon', 'public.react_to_milestone(uuid, text, text)', 'execute'),
                'anon cannot react');
