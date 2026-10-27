-- The far side of the Summit: zones 10-19 (10-20 km) and their achievements.
-- Mirrors ZoneCatalog.standard and AchievementCatalog.standard in WalkscapeDomain.

insert into public.zone_definitions
    (id, sort_order, name, tagline, biome, start_meters, end_meters, discovery_id, discovery_name)
values
    ('starlight-pass',   10, 'Starlight Pass',   'Ribbons of light dance over the pass.',      'starlightPass',   10000, 11000, 'fallen-star',    'Fallen Star'),
    ('hot-springs',      11, 'Hot Springs',      'Steam curls from turquoise pools.',          'hotSprings',      11000, 12000, 'spring-egg',     'Spring Egg'),
    ('maple-woods',      12, 'Maple Woods',      'Every tree is on fire with colour.',         'autumnWoods',     12000, 13000, 'maple-leaf',     'Maple Leaf'),
    ('bamboo-grove',     13, 'Bamboo Grove',     'Tall stalks creak softly in the wind.',      'bambooGrove',     13000, 14000, 'bamboo-flute',   'Bamboo Flute'),
    ('blossom-orchard',  14, 'Blossom Orchard',  'Pink petals drift on the breeze.',           'blossomOrchard',  14000, 15000, 'cherries',       'Twin Cherries'),
    ('lavender-fields',  15, 'Lavender Fields',  'Purple rows roll out to an old windmill.',   'lavenderFields',  15000, 16000, 'lavender',       'Lavender Sprig'),
    ('red-canyon',       16, 'Red Rock Canyon',  'Sun-baked mesas glow orange.',               'redCanyon',       16000, 17000, 'canyon-agate',   'Canyon Agate'),
    ('firefly-marsh',    17, 'Firefly Marsh',    'Dusk falls and the fireflies wake.',         'fireflyMarsh',    17000, 18000, 'firefly-jar',    'Firefly Jar'),
    ('sandy-shore',      18, 'Sandy Shore',      'Salt air and the sound of waves.',           'sandyShore',      18000, 19000, 'message-bottle', 'Message in a Bottle'),
    ('lighthouse-point', 19, 'Lighthouse Point', 'The end of the land, the start of the sea.', 'lighthousePoint', 19000, 20000, 'spyglass',       'Keeper''s Spyglass');

insert into public.achievements (id, name, description)
values
    ('lightkeeper', 'Lightkeeper', 'Reach Lighthouse Point in a single day (19 km).'),
    ('off-the-map', 'Off the Map', 'Walk 20 km in a single day.'),
    ('curator',     'Curator',     'Find all 20 discoveries.');

-- The map no longer ends at 10 km.
update public.achievements set name = 'Double Digits' where id = 'beyond';
update public.achievements set description = 'Find 10 discoveries.' where id = 'completionist';
