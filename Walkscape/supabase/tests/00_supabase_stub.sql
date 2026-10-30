-- Minimal stand-in for the parts of Supabase the migrations rely on, so the
-- schema and its row level security can be tested on plain Postgres.
-- Mirrors Supabase: roles anon/authenticated, auth.users, auth.uid() from the
-- JWT "sub" claim, and default privileges that grant everything in public to
-- the API roles (so RLS and explicit revokes must do the protecting).

create role anon nologin;
create role authenticated nologin;

create schema auth;
grant usage on schema auth to anon, authenticated;
grant usage on schema public to anon, authenticated;

create table auth.users (
    id uuid primary key,
    email text
);

create function auth.uid() returns uuid
language sql stable
as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on functions to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;

-- Test helpers -------------------------------------------------------------

create schema tests;
grant usage on schema tests to anon, authenticated;

create table tests.users (name text primary key, id uuid not null);
grant select on tests.users to anon, authenticated;

create function tests.id(p_name text) returns uuid
language sql stable as $$ select id from tests.users where name = p_name $$;

-- Switches the session to an API role, optionally as a signed-in user.
create function tests.as_user(p_name text) returns void
language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', coalesce(tests.id(p_name)::text, ''), false);
    execute 'set role authenticated';
end $$;

create function tests.as_anon() returns void
language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', '', false);
    execute 'set role anon';
end $$;

create function tests.ok(p_condition boolean, p_message text) returns void
language plpgsql as $$
begin
    if p_condition is distinct from true then
        raise exception 'not ok - %', p_message;
    end if;
    raise notice 'ok - %', p_message;
end $$;

-- Runs `p_sql` and checks it fails with a message containing `p_expected`.
create function tests.fails(p_sql text, p_expected text, p_message text) returns void
language plpgsql as $$
begin
    begin
        execute p_sql;
    exception when others then
        if position(p_expected in sqlerrm) > 0 then
            raise notice 'ok - %', p_message;
            return;
        end if;
        raise exception 'not ok - % (expected error containing "%", got "%")', p_message, p_expected, sqlerrm;
    end;
    raise exception 'not ok - % (expected an error, none raised)', p_message;
end $$;

-- Returns how many rows `p_sql` produces when run by the current role.
create function tests.count(p_sql text) returns bigint
language plpgsql as $$
declare n bigint;
begin
    execute 'select count(*) from (' || p_sql || ') q' into n;
    return n;
end $$;

-- Gives the signed-in test player `p_amount` coins in their cloud save, the
-- way the app's wallet stores them (schema 2, keyed earnings).
create function tests.give_coins(p_amount integer) returns void
language plpgsql security definer as $$
begin
    insert into public.player_saves (user_id, save)
    values (auth.uid(), jsonb_build_object('schema', 2, 'wallet',
            jsonb_build_object('earned', jsonb_build_object('test-grant', p_amount), 'spent', '{}'::jsonb)))
    on conflict (user_id) do update
        set save = jsonb_set(public.player_saves.save, '{wallet,earned,test-grant}',
                             to_jsonb(coalesce((public.player_saves.save #>> '{wallet,earned,test-grant}')::integer, 0) + p_amount)),
            version = public.player_saves.version + 1;
end $$;

-- Coins the signed-in test player has left in their cloud save.
create function tests.coins() returns bigint
language sql security definer as $$
    select (select coalesce(sum(value::bigint), 0) from jsonb_each_text(s.save -> 'wallet' -> 'earned'))
         - (select coalesce(sum(value::bigint), 0) from jsonb_each_text(coalesce(s.save -> 'wallet' -> 'spent', '{}'::jsonb)))
    from public.player_saves s where s.user_id = auth.uid()
$$;

grant execute on all functions in schema tests to anon, authenticated;
