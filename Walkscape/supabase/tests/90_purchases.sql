-- Purchase tests: rows are only written by the server; players see their own active ones.
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

insert into public.purchases (original_transaction_id, user_id, product_id, environment, purchased_at, expires_at, revoked_at)
values ('1001', tests.id('kim'), 'com.alexandrub.walkscape.bundle.trailsparkles', 'Sandbox', now(), null, null),
       ('1002', tests.id('kim'), 'com.alexandrub.walkscape.plus.monthly', 'Sandbox', now(), now() + interval '30 days', null),
       ('1003', tests.id('kim'), 'com.alexandrub.walkscape.bundle.companionskins', 'Sandbox', now(), null, now()),
       ('1004', tests.id('leo'), 'com.alexandrub.walkscape.plus.yearly', 'Sandbox', now() - interval '2 years',
        now() - interval '1 year', null);

select tests.fails($$insert into public.purchases values ('x', tests.id('max'), 'com.example.other', 'Sandbox', now(), null, null, now())$$,
                   'purchases_product_format', 'only Walkscape products can be stored');

select tests.as_user('kim');
select tests.ok(tests.count('select * from public.my_entitlements()') = 2,
                'bundles and active subscriptions count; refunded purchases do not');
select tests.ok(public.has_plus(tests.id('kim')), 'an active subscription is Plus');
select tests.fails($$insert into public.purchases values ('2001', tests.id('kim'), 'com.alexandrub.walkscape.plus.monthly',
                     'Sandbox', now(), now() + interval '1 year', null, now())$$,
                   'permission denied', 'players cannot grant themselves purchases');
select tests.fails($$select * from public.purchases$$, 'permission denied', 'the table is never read directly');
reset role;

select tests.as_user('leo');
select tests.ok(tests.count('select * from public.my_entitlements()') = 0, 'an expired subscription grants nothing');
select tests.ok(public.has_plus(tests.id('kim')), 'friends can see whether you have Plus');
reset role;

select tests.as_user('max');
select tests.ok(not public.has_plus(tests.id('kim')), 'strangers cannot see it');
select tests.ok(tests.count('select * from public.my_entitlements()') = 0, 'nobody sees someone else''s purchases');
reset role;

select tests.ok(not has_function_privilege('anon', 'public.my_entitlements()', 'execute'), 'anon cannot read entitlements');
