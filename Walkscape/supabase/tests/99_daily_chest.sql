-- The free daily chest: chest opens it, cheat edits their save, clock and time zone.
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
select tests.fails($$select * from public.claim_daily_chest(gen_random_uuid(), 'UTC')$$, 'permission denied',
                   'signed-out callers can''t open a daily chest');

select tests.as_user('chest');
select tests.ok((select ready_at <= server_now from public.daily_chest_status('Europe/London')), 'a new player''s chest is ready');
select tests.give_coins(10);
select coins as first_coins, ready_at as first_ready
from public.claim_daily_chest('00000000-0000-0000-0000-0000000000e1', 'Europe/London') \gset
select tests.ok(:first_coins in (25, 30, 40, 50, 60, 75, 100, 125, 150), 'the chest holds 25 to 150 coins');
select tests.ok(tests.coins() = 10 + :first_coins, 'the coins are written into the save');
select tests.ok((select coins from public.claim_daily_chest('00000000-0000-0000-0000-0000000000e1', 'Europe/London')) = :first_coins,
                'retrying the same claim gives the same coins');
select tests.ok(tests.coins() = 10 + :first_coins, 'and pays nothing again');
select tests.fails($$select * from public.claim_daily_chest(gen_random_uuid(), 'Europe/London')$$, 'daily_chest_not_ready',
                   'a second chest the same day is refused');
select tests.ok(:'first_ready'::timestamptz = ((now() at time zone 'Europe/London')::date + 1)::timestamp at time zone 'Europe/London',
                'the next chest is ready at the player''s midnight, by the server''s clock');
select tests.ok((select ready_at = :'first_ready'::timestamptz from public.daily_chest_status('Europe/London')),
                'and the status says so');
select tests.fails($$select * from public.claim_daily_chest(gen_random_uuid(), 'Pacific/Pago_Pago')$$, 'daily_chest_not_ready',
                   'moving the time zone back a day doesn''t open another');
reset role;
select tests.ok((select count(*) from public.daily_chest_claims where user_id = tests.id('chest')) = 1, 'one claim recorded');

-- After midnight it opens again.
update public.daily_chests set last_day = last_day - 1 where user_id = tests.id('chest');
select tests.as_user('chest');
select public.claim_daily_chest(gen_random_uuid(), 'Europe/London');
reset role;
select tests.ok((select count(*) from public.daily_chest_claims where user_id = tests.id('chest')) = 2,
                'the chest opens again the next day');

-- The odds: bigger amounts are rarer.
do $$
declare
    i integer;
begin
    for i in 1..2000 loop
        update public.daily_chests set last_day = date '2000-01-01' where user_id = tests.id('cheat');
        perform set_config('request.jwt.claim.sub', tests.id('cheat')::text, true);
        perform public.claim_daily_chest(gen_random_uuid(), 'UTC');
    end loop;
end $$;
select tests.ok((select count(*) filter (where coins = 25) > count(*) filter (where coins >= 75) * 1.5
                        and count(*) filter (where coins = 150) between 1 and 120
                        and min(coins) = 25 and max(coins) = 150
                 from public.daily_chest_claims where user_id = tests.id('cheat')),
                'small amounts are common and 150 coins is rare');
delete from public.daily_chest_claims where user_id = tests.id('cheat');
delete from public.daily_chests where user_id = tests.id('cheat');

-- Saves can't make up daily chests.
select tests.as_user('cheat');
select tests.give_coins(10);
select coins as real_coins from public.claim_daily_chest('00000000-0000-0000-0000-0000000000e2', 'UTC') \gset
select save as cheat_save, version as cheat_version from public.get_player_save() \gset
select public.put_player_save(jsonb_set(jsonb_set((:'cheat_save')::jsonb,
                                                  '{wallet,earned,daily-chest-00000000-0000-0000-0000-0000000000e2}', '150'),
                                        '{wallet,earned,daily-chest-made-up}', '150'), :cheat_version);
select tests.ok((select (save #>> '{wallet,earned,daily-chest-00000000-0000-0000-0000-0000000000e2}')::integer = :real_coins
                        and not (save -> 'wallet' -> 'earned' ? 'daily-chest-made-up')
                 from public.get_player_save()), 'a save can''t grow a daily chest or add one');
select version as cheat_version from public.get_player_save() \gset
select public.put_player_save(jsonb_set((:'cheat_save')::jsonb, '{wallet,earned}', '{"test-grant": 10}'), :cheat_version);
select tests.ok((select (save #>> '{wallet,earned,daily-chest-00000000-0000-0000-0000-0000000000e2}')::integer = :real_coins
                 from public.get_player_save()), 'or lose one');
select tests.fails($$select * from public.claim_daily_chest(gen_random_uuid(), 'UTC')$$, 'daily_chest_not_ready',
                   'reinstalling or a new save doesn''t reset the day');
reset role;
select tests.ok(not exists (select 1 from information_schema.role_table_grants
                            where table_name in ('daily_chests', 'daily_chest_claims') and grantee in ('anon', 'authenticated')),
                'the daily chest tables are only reachable through the functions');
