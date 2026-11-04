-- The free daily chest: chest opens it, cheat edits their save and clock.
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

insert into tests.users values
    ('chest', '00000000-0000-0000-0000-000000000060'),
    ('cheat', '00000000-0000-0000-0000-000000000061');
insert into auth.users (id, email)
select id, name || '@example.com' from tests.users where name in ('chest', 'cheat');
update public.profiles set username = (select name from tests.users where id = profiles.id)
where id in (select id from tests.users where name in ('chest', 'cheat'));

select tests.ok(exists (select 1 from public.mystery_box_prizes where item_id = 'rainbow-contrail' and rarity = 'legendary'),
                'contrails are legendary Mystery Box prizes');

select tests.as_anon();
select tests.fails($$select * from public.claim_daily_chest(gen_random_uuid())$$, 'permission denied',
                   'signed-out callers can''t open a daily chest');

select tests.as_user('chest');
select tests.ok((select ready_at <= server_now from public.daily_chest_status()), 'a new player''s chest is ready');
select tests.give_coins(10);
select coins as first_coins, ready_at as first_ready
from public.claim_daily_chest('00000000-0000-0000-0000-0000000000e1') \gset
select tests.ok(:first_coins in (15, 20, 25, 30, 40, 50, 60, 75, 100), 'the chest holds 15 to 100 coins');
select tests.ok(tests.coins() = 10 + :first_coins, 'the coins are written into the save');
select tests.ok((select coins from public.claim_daily_chest('00000000-0000-0000-0000-0000000000e1')) = :first_coins,
                'retrying the same claim gives the same coins');
select tests.ok(tests.coins() = 10 + :first_coins, 'and pays nothing again');
select tests.fails($$select * from public.claim_daily_chest(gen_random_uuid())$$, 'daily_chest_not_ready',
                   'a second chest the same day is refused');
select tests.ok((select ready_at = :'first_ready'::timestamptz and ready_at > server_now + interval '23 hours'
                 from public.daily_chest_status()), 'the next chest is ready 24 hours later, by the server''s clock');
reset role;
select tests.ok((select count(*) from public.daily_chest_claims where user_id = tests.id('chest')) = 1, 'one claim recorded');

-- A day later it opens again.
update public.daily_chests set last_claimed_at = now() - interval '24 hours 1 minute' where user_id = tests.id('chest');
select tests.as_user('chest');
select public.claim_daily_chest(gen_random_uuid());
reset role;
select tests.ok((select count(*) from public.daily_chest_claims where user_id = tests.id('chest')) = 2,
                'the chest opens again after 24 hours');

-- The odds: bigger amounts are rarer.
do $$
declare
    i integer;
begin
    for i in 1..2000 loop
        update public.daily_chests set last_claimed_at = now() - interval '25 hours' where user_id = tests.id('cheat');
        perform set_config('request.jwt.claim.sub', tests.id('cheat')::text, true);
        perform public.claim_daily_chest(gen_random_uuid());
    end loop;
end $$;
select tests.ok((select count(*) filter (where coins = 15) > count(*) filter (where coins >= 50) * 1.5
                        and count(*) filter (where coins = 100) between 1 and 120
                        and min(coins) = 15 and max(coins) = 100
                 from public.daily_chest_claims where user_id = tests.id('cheat')),
                'small amounts are common and 100 coins is rare');
delete from public.daily_chest_claims where user_id = tests.id('cheat');
delete from public.daily_chests where user_id = tests.id('cheat');

-- Saves can't make up daily chests.
select tests.as_user('cheat');
select tests.give_coins(10);
select coins as real_coins from public.claim_daily_chest('00000000-0000-0000-0000-0000000000e2') \gset
select save as cheat_save, version as cheat_version from public.get_player_save() \gset
select public.put_player_save(jsonb_set(jsonb_set((:'cheat_save')::jsonb,
                                                  '{wallet,earned,daily-chest-00000000-0000-0000-0000-0000000000e2}', '100'),
                                        '{wallet,earned,daily-chest-made-up}', '100'), :cheat_version);
select tests.ok((select (save #>> '{wallet,earned,daily-chest-00000000-0000-0000-0000-0000000000e2}')::integer = :real_coins
                        and not (save -> 'wallet' -> 'earned' ? 'daily-chest-made-up')
                 from public.get_player_save()), 'a save can''t grow a daily chest or add one');
select version as cheat_version from public.get_player_save() \gset
select public.put_player_save(jsonb_set((:'cheat_save')::jsonb, '{wallet,earned}', '{"test-grant": 10}'), :cheat_version);
select tests.ok((select (save #>> '{wallet,earned,daily-chest-00000000-0000-0000-0000-0000000000e2}')::integer = :real_coins
                 from public.get_player_save()), 'or lose one');
select tests.fails($$select * from public.claim_daily_chest(gen_random_uuid())$$, 'daily_chest_not_ready',
                   'reinstalling or a new save doesn''t reset the timer');
reset role;
select tests.ok(not exists (select 1 from information_schema.role_table_grants
                            where table_name in ('daily_chests', 'daily_chest_claims') and grantee in ('anon', 'authenticated')),
                'the daily chest tables are only reachable through the functions');
