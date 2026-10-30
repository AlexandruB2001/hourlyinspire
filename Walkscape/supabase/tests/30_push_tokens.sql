-- Push token tests. Runs after 20_referrals_and_teams.sql (alice and bob exist).
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

insert into tests.users values ('hana', '00000000-0000-0000-0000-000000000011');
insert into auth.users (id, email) values (tests.id('hana'), 'hana@example.com');

select tests.as_user('alice');
select public.register_push_token(repeat('ab', 32), 'sandbox');
select tests.fails($$select * from public.push_tokens$$, 'permission denied', 'tokens can never be read by clients');
select tests.fails($$insert into public.push_tokens (token, user_id, environment) values (repeat('cd', 32), tests.id('bob'), 'sandbox')$$,
                   'permission denied', 'tokens can only be added through register_push_token');
select tests.fails($$select public.register_push_token('not-a-token', 'sandbox')$$, 'push_tokens_token_format',
                   'malformed tokens are rejected');
select tests.fails($$select public.register_push_token(repeat('ab', 32), 'staging')$$, 'check constraint',
                   'only sandbox and production environments are allowed');
reset role;
select tests.ok((select user_id from public.push_tokens where token = repeat('ab', 32)) = tests.id('alice'),
                'a registered token belongs to the caller');

-- The same phone signed in as someone else: the token moves.
select tests.as_user('bob');
select public.register_push_token(upper(repeat('ab', 32)), 'production', false);
reset role;
select tests.ok((select user_id = tests.id('bob') and environment = 'production' and not social
                 from public.push_tokens where token = repeat('ab', 32)),
                'registering an existing token moves it to the new account with its settings');

-- Only your own token can be removed.
select tests.as_user('alice');
select public.unregister_push_token(repeat('ab', 32));
reset role;
select tests.ok(tests.count('select 1 from public.push_tokens') = 1, 'someone else''s token is not removed');
select tests.as_user('bob');
select public.unregister_push_token(repeat('ab', 32));
reset role;
select tests.ok(tests.count('select 1 from public.push_tokens') = 0, 'your own token is removed');

-- Deleting an account deletes its tokens.
select tests.as_user('hana');
select public.register_push_token(repeat('ef', 32), 'sandbox');
select public.delete_account();
reset role;
select tests.ok(tests.count('select 1 from public.push_tokens') = 0, 'deleting an account removes its tokens');

select tests.ok(not has_function_privilege('anon', 'public.register_push_token(text, text, boolean)', 'execute'),
                'anon cannot register tokens');
