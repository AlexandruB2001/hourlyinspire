-- Server-authoritative spending (wallet phase A), with its own players: box
-- buys Mystery Boxes, pets adopts companions, ads watches rewarded ads and
-- forger edits their save.
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

insert into tests.users values
    ('box',    '00000000-0000-0000-0000-000000000050'),
    ('pets',   '00000000-0000-0000-0000-000000000051'),
    ('ads',    '00000000-0000-0000-0000-000000000052'),
    ('forger', '00000000-0000-0000-0000-000000000053'),
    ('hoard',  '00000000-0000-0000-0000-000000000054');
insert into auth.users (id, email)
select id, name || '@example.com' from tests.users where name in ('box', 'pets', 'ads', 'forger', 'hoard');
update public.profiles set username = (select name from tests.users where id = profiles.id)
where id in (select id from tests.users where name in ('box', 'pets', 'ads', 'forger', 'hoard'));

-- The prize pool --------------------------------------------------------------

select tests.ok((select count(*) from public.mystery_box_prizes) = 57, 'the box holds 45 outfits and 12 accessories');
select tests.ok(not exists (select 1 from public.mystery_box_candidates(tests.id('box'), 1220, '[]') where item_id = 'pet-snow-hat'),
                'a festival accessory stays out of the box while its festival runs (over New Year)');
select tests.ok(exists (select 1 from public.mystery_box_candidates(tests.id('box'), 601, '[]') where item_id = 'pet-snow-hat'),
                'and is in the box the rest of the year');
select tests.ok(not exists (select 1 from public.mystery_box_candidates(tests.id('box'), 1031, '[]') where item_id = 'pet-pumpkin-hat'),
                'the same for festivals within a year');
select tests.ok(not exists (select 1 from public.mystery_box_candidates(tests.id('box'), 601, '["golden-crown"]')
                            where item_id = 'golden-crown'), 'items already in the save aren''t given again');

-- Buying Mystery Boxes ---------------------------------------------------------

select tests.as_user('box');
select tests.fails($$select * from public.open_mystery_box(gen_random_uuid(), current_date)$$, 'no_cloud_save',
                   'a box is paid from the cloud save');
select tests.give_coins(100);
select tests.fails($$select * from public.open_mystery_box(gen_random_uuid(), current_date)$$, 'insufficient_coins',
                   'a box costs 150 coins');
select tests.ok(tests.coins() = 100, 'a failed purchase takes nothing');
select tests.fails($$select * from public.open_mystery_box(gen_random_uuid(), current_date - 5)$$, 'invalid_request',
                   'the day must be today''s');
select tests.give_coins(900);
select item_id as first_prize, charge_key as first_key
from public.open_mystery_box('00000000-0000-0000-0000-0000000000d1', current_date) \gset
select tests.ok(tests.coins() = 850, 'opening a box takes exactly 150 coins');
select tests.ok(:'first_key' = 'box-00000000-0000-0000-0000-0000000000d1', 'the charge key is the request');
select tests.ok((select item_id from public.open_mystery_box('00000000-0000-0000-0000-0000000000d1', current_date)) = :'first_prize',
                'retrying the same request gives the same prize');
select tests.ok(tests.coins() = 850, 'and charges nothing again');
select tests.ok((select save -> 'wallet' -> 'ownedItemIDs' ? :'first_prize' from public.get_player_save()),
                'the prize is written into the save');
select public.open_mystery_box(gen_random_uuid(), current_date) from generate_series(1, 4);
select tests.ok(tests.coins() = 250, 'five boxes cost 750');
reset role;
select tests.ok((select count(distinct item_id) = 5 and count(*) = 5 from public.owned_items where user_id = tests.id('box')),
                'every box gives something new, recorded in the server inventory');
select tests.ok((select count(*) from public.coin_charges where user_id = tests.id('box') and key like 'box-%') = 5,
                'every box is a recorded charge');

-- Sold out.
insert into public.owned_items (user_id, item_id, source)
select tests.id('hoard'), item_id, 'legacy' from public.mystery_box_prizes;
select tests.as_user('hoard');
select tests.give_coins(500);
select tests.fails($$select * from public.open_mystery_box(gen_random_uuid(), current_date)$$, 'sold_out',
                   'with everything owned the box is sold out');
select tests.ok(tests.coins() = 500, 'and takes nothing');
reset role;

-- Adopting companions -----------------------------------------------------------

select tests.as_user('pets');
select tests.give_coins(999);
select tests.fails($$select * from public.adopt_companion('dragon')$$, 'unknown_companion', 'only real companions');
select tests.fails($$select * from public.adopt_companion('emberfox')$$, 'insufficient_coins', 'adopting costs 1000 coins');
select tests.give_coins(1001);
select tests.ok((select charge_key = 'companion-emberfox' and coins = 1000 from public.adopt_companion('emberfox')),
                'adopting charges 1000 coins under the companion''s key');
select tests.ok(tests.coins() = 1000, 'exactly once');
select * from public.adopt_companion('emberfox');
select tests.ok(tests.coins() = 1000, 'adopting the same companion again charges nothing');
reset role;
select tests.ok(exists (select 1 from public.owned_items where user_id = tests.id('pets') and item_id = 'companion:emberfox'),
                'the server records the adoption');

-- Rewarded ads ------------------------------------------------------------------

select tests.ok(public.record_ad_reward(tests.id('ads'), 'tx-1', '11111111-aaaa-4aaa-8aaa-111111111111', 'unit') = 'recorded',
                'a verified ad is recorded');
select tests.ok(public.record_ad_reward(tests.id('ads'), 'tx-1', '11111111-aaaa-4aaa-8aaa-111111111111', 'unit') = 'duplicate',
                'Google retrying the same ad records it once');
select tests.ok(public.record_ad_reward(tests.id('ads'), 'tx 2; drop', 'x', 'unit') = 'invalid', 'malformed callbacks are ignored');
select tests.ok(public.record_ad_reward('00000000-0000-0000-0000-0000000000ff', 'tx-9', 'r9', 'unit') = 'unknown_user',
                'ads for unknown players are ignored');
select public.record_ad_reward(tests.id('ads'), 'tx-' || n, 'reward-' || n, 'unit') from generate_series(2, 6) n;
select tests.ok(public.record_ad_reward(tests.id('ads'), 'tx-7', 'reward-7', 'unit') = 'daily_limit',
                'at most 6 verified ads a day');
select tests.ok((select sum(coins) from public.ad_rewards where user_id = tests.id('ads')) = 90, '15 coins each');

select tests.as_user('ads');
select public.put_player_save('{"schema": 2, "wallet": {"earned": {"starter": 50, "ad-made-up": 15}, "spent": {}}}', 0);
select tests.ok(tests.coins() = 65, 'with ad verification off, ad coins in saves are kept as before');
reset role;
update public.wallet_settings set verify_ad_rewards = true;
select tests.as_user('ads');
select version as ads_version from public.get_player_save() \gset
select public.put_player_save('{"schema": 2, "wallet": {"earned": {"starter": 50, "ad-made-up": 15}, "spent": {}}}', :ads_version);
select tests.ok((select not (save -> 'wallet' -> 'earned' ? 'ad-made-up')
                        and (save #>> '{wallet,earned,ad-11111111-aaaa-4aaa-8aaa-111111111111}')::integer = 15
                 from public.get_player_save()), 'with it on, only verified ads pay, even ones the app missed');
select tests.ok(tests.coins() = 50 + 90, 'so the balance counts verified ads only');
reset role;
update public.wallet_settings set verify_ad_rewards = false;

-- Inventory enforcement ---------------------------------------------------------

select tests.as_user('forger');
select tests.give_coins(200);
select save as forger_save, version as forger_version from public.get_player_save() \gset
select public.put_player_save(jsonb_set(jsonb_set((:'forger_save')::jsonb, '{wallet,ownedItemIDs}', '["golden-crown"]'),
                                        '{wallet,equipped}', '{"head": "golden-crown"}'), :forger_version);
select tests.ok((select save -> 'wallet' -> 'ownedItemIDs' ? 'golden-crown' from public.get_player_save()),
                'before enforcement starts, saves are trusted (old builds still open boxes on the phone)');
reset role;

select public.start_wallet_enforcement();
select tests.ok((select enforce_inventory from public.wallet_settings), 'enforcement can be switched on');
select tests.ok(exists (select 1 from public.owned_items where user_id = tests.id('forger') and item_id = 'golden-crown'
                        and source = 'legacy'), 'what saves held when it started is carried over');

select tests.as_user('forger');
select save as forger_save, version as forger_version from public.get_player_save() \gset
select public.put_player_save(jsonb_set(jsonb_set((:'forger_save')::jsonb, '{wallet,ownedItemIDs}',
                                                  '["golden-crown", "wizard-hat", "pet-snow-hat", "pet-bow"]'),
                                        '{wallet,equipped}', '{"head": "wizard-hat", "neck": "golden-crown"}'),
                              :forger_version);
select tests.ok((select not (save -> 'wallet' -> 'ownedItemIDs' ? 'wizard-hat') from public.get_player_save()),
                'a Mystery Box item the server never gave is removed');
select tests.ok((select save -> 'wallet' -> 'equipped' = '{"neck": "golden-crown"}'::jsonb from public.get_player_save()),
                'and taken off if worn');
select tests.ok((select save -> 'wallet' -> 'ownedItemIDs' ?& array['golden-crown', 'pet-snow-hat', 'pet-bow']
                 from public.get_player_save()), 'owned box items, festival rewards and level gifts are kept');

-- Companions: the first pick plus server adoptions.
select version as forger_version from public.get_player_save() \gset
select tests.fails(format('select public.put_player_save(%L::jsonb, %s)',
    '{"schema": 2, "wallet": {"earned": {"starter": 50}, "spent": {}}, "companion": {"speciesID": "mossling"},
      "companionRoster": {"resting": [{"state": {"speciesID": "emberfox"}, "walkedMeters": 0}]}}', :forger_version),
    'invalid_companions', 'a save can''t hold companions nobody paid for');
select public.put_player_save('{"schema": 2, "wallet": {"earned": {"starter": 50}, "spent": {}},
                                "companion": {"speciesID": "mossling"}, "companionRoster": {"resting": []}}', :forger_version);
select tests.ok(true, 'one companion (the free first pick) is fine');
reset role;

select tests.as_user('pets');
select version as pets_version from public.get_player_save() \gset
select public.put_player_save(jsonb_build_object('schema', 2,
    'wallet', (select save -> 'wallet' from public.get_player_save()),
    'companion', '{"speciesID": "mossling"}'::jsonb,
    'companionRoster', '{"resting": [{"state": {"speciesID": "emberfox"}, "walkedMeters": 0}]}'::jsonb), :pets_version);
select tests.ok(true, 'an adopted companion is allowed');
select tests.ok(tests.coins() = 1000, 'and saving can''t refund the adoption');
reset role;

update public.wallet_settings set enforce_inventory = false;

-- Privileges ----------------------------------------------------------------------

select tests.ok(not has_function_privilege('authenticated', 'public.record_ad_reward(uuid, text, text, text)', 'execute'),
                'players can''t record ads');
select tests.ok(not has_function_privilege('authenticated', 'public.start_wallet_enforcement()', 'execute'),
                'or switch enforcement');
select tests.ok(not has_function_privilege('authenticated', 'public.mystery_box_candidates(uuid, integer, jsonb)', 'execute'),
                'or list another player''s candidates');
select tests.ok(not has_table_privilege('authenticated', 'public.owned_items', 'insert')
                and not has_table_privilege('authenticated', 'public.owned_items', 'select'),
                'or touch the inventory directly');
select tests.ok(not has_table_privilege('authenticated', 'public.wallet_settings', 'update'), 'or the settings');
