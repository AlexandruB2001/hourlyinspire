-- Reference data mirroring ZoneCatalog.standard and AchievementCatalog.standard
-- in WalkscapeDomain. Keep the two in sync when adding content.

insert into public.zone_definitions
    (id, sort_order, name, tagline, biome, start_meters, end_meters, discovery_id, discovery_name)
values
    ('meadow',        0, 'Sunny Meadow',  'Wildflowers sway where every journey begins.', 'meadow',       0,    1000, 'clover',      'Four-leaf Clover'),
    ('riverside',     1, 'Riverside',     'A lazy river and a creaky wooden bridge.',     'riverside',    1000, 2000, 'river-stone', 'River Stone'),
    ('pine-forest',   2, 'Pine Forest',   'Tall pines hum with birdsong.',                'pineForest',   2000, 3000, 'pinecone',    'Golden Pinecone'),
    ('rolling-hills', 3, 'Rolling Hills', 'Soft green hills roll toward the horizon.',    'rollingHills', 3000, 4000, 'feather',     'Kite Feather'),
    ('lakeside',      4, 'Lakeside',      'A mirror-still lake reflects the clouds.',     'lakeside',     4000, 5000, 'shell',       'Spiral Shell'),
    ('village',       5, 'Hearth Village','Chimney smoke and warm bread.',                'village',      5000, 6000, 'lantern',     'Brass Lantern'),
    ('crystal-caves', 6, 'Crystal Caves', 'Glowing crystals light the way.',              'crystalCaves', 6000, 7000, 'crystal',     'Glow Crystal'),
    ('snowy-ridge',   7, 'Snowy Ridge',   'Crisp air and fresh snow underfoot.',          'snowyRidge',   7000, 8000, 'snowflake',   'Snowflake Charm'),
    ('cloud-forest',  8, 'Cloud Forest',  'Mist drifts between mossy giants.',            'cloudForest',  8000, 9000, 'mushroom',    'Glowcap Mushroom'),
    ('summit',        9, 'The Summit',    'The whole world, all at once.',                'summit',       9000, 10000,'summit-flag', 'Summit Flag');

insert into public.achievements (id, name, description)
values
    ('first-steps',   'First Steps',     'Walk 1 km in a day.'),
    ('trailblazer',   'Trailblazer',     'Reach Hearth Village in a single day (5 km).'),
    ('summiteer',     'Summiteer',       'Reach the Summit in a single day (9 km).'),
    ('beyond',        'Beyond the Map',  'Walk 10 km in a single day.'),
    ('regular',       'Regular Rambler', 'Walk at least 1 km on 3 different days.'),
    ('wanderer',      'Wanderer',        'Walk 25 km in total.'),
    ('marathoner',    'Marathoner',      'Walk a marathon''s distance in total (42.2 km).'),
    ('collector',     'Collector',       'Find 5 discoveries.'),
    ('completionist', 'Cartographer',    'Find all 10 discoveries.');
