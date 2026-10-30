-- Cloud save tests. Runs after 30_push_tokens.sql (alice and bob exist).
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

-- Earlier tests gave some players coins (a save); start these from none.
delete from public.player_saves;
insert into tests.users values ('ivan', '00000000-0000-0000-0000-000000000012');
insert into auth.users (id, email) values (tests.id('ivan'), 'ivan@example.com');

select tests.as_user('alice');
select tests.ok(tests.count('select * from public.get_player_save()') = 0, 'a new player has no save');
select tests.ok(public.put_player_save('{"schema":1,"coins":10}', 0) = 1, 'the first save is version 1');
select tests.fails($$select public.put_player_save('{"schema":1}', 0)$$, 'save_conflict',
                   'a second phone cannot create a save over an existing one');
select tests.ok(public.put_player_save('{"schema":1,"coins":20}', 1) = 2, 'saving from the version you read works');
select tests.fails($$select public.put_player_save('{"schema":1,"coins":5}', 1)$$, 'save_conflict',
                   'a stale save is rejected instead of overwriting newer progress');
select tests.ok((select (save->>'coins')::int = 20 and version = 2 from public.get_player_save()),
                'the stored save is the latest accepted one');
select tests.fails($$select public.put_player_save('[1,2]', 2)$$, 'player_saves_is_object', 'a save must be an object');
select tests.fails($$select * from public.player_saves$$, 'permission denied', 'the table is never read directly');
reset role;

select tests.as_user('bob');
select tests.ok(tests.count('select * from public.get_player_save()') = 0, 'nobody can read another player''s save');
select tests.fails($$update public.player_saves set save = '{}'$$, 'permission denied', 'nobody can edit saves directly');
reset role;

select tests.as_user('ivan');
select public.put_player_save('{"schema":1}', 0);
select public.delete_account();
reset role;
select tests.ok(not exists (select 1 from public.player_saves where user_id = tests.id('ivan')),
                'deleting an account deletes its save');

select tests.ok(not has_function_privilege('anon', 'public.put_player_save(jsonb, integer)', 'execute'),
                'anon cannot write saves');
