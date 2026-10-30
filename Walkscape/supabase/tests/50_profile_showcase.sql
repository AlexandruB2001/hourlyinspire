-- Profile showcase tests. Uses its own players: kim and leo are friends, max is a stranger.
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

insert into tests.users values
    ('kim', '00000000-0000-0000-0000-000000000013'),
    ('leo', '00000000-0000-0000-0000-000000000014'),
    ('max', '00000000-0000-0000-0000-000000000015');
insert into auth.users (id, email) select id, name || '@example.com' from tests.users where name in ('kim', 'leo', 'max');
update public.profiles set username = (select name from tests.users where id = profiles.id)
where id in (tests.id('kim'), tests.id('leo'), tests.id('max'));
insert into public.friendships (requester_id, addressee_id, status, responded_at)
values (tests.id('kim'), tests.id('leo'), 'accepted', now());

select tests.as_user('kim');
select public.set_my_showcase('lighthouse-keeper', 'gold', 'summit');
select tests.fails($$select public.set_my_showcase('Bad Title!', null, null)$$, 'profiles_title_id_format',
                   'title ids must be simple ids');
select tests.ok((select title_id = 'lighthouse-keeper' and frame_id = 'gold' and favorite_zone_id = 'summit'
                 from public.friend_showcases() where user_id = tests.id('kim')),
                'you see your own showcase');
reset role;

select tests.as_user('leo');
select tests.ok((select title_id from public.friend_showcases() where user_id = tests.id('kim')) = 'lighthouse-keeper',
                'friends see your title');
update public.profiles set title_id = 'hacked' where id = tests.id('kim');
reset role;
select tests.ok((select title_id from public.profiles where id = tests.id('kim')) = 'lighthouse-keeper',
                'nobody can change someone else''s title');

select tests.as_user('max');
select tests.ok(not exists (select 1 from public.friend_showcases() where user_id = tests.id('kim')),
                'strangers are not listed');
reset role;

select tests.as_user('kim');
select public.set_my_showcase(null, null, null);
select tests.ok((select title_id is null from public.friend_showcases() where user_id = tests.id('kim')),
                'a showcase can be cleared');
reset role;

select tests.ok(not has_function_privilege('anon', 'public.friend_showcases()', 'execute'), 'anon cannot list showcases');
