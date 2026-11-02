-- Tops (tees, sweaters and hoodies) join the shop. The Mystery Box is rolled
-- on the server, so they join its prize pool here (same ids and rarities as
-- ShopCatalog; ServerWalletCatalogTests keeps them in step). Safe to run again.

insert into public.mystery_box_prizes (item_id, kind, rarity, festival_start, festival_end) values
    ('white-tee', 'outfit', 'common', null, null),
    ('red-tee', 'outfit', 'common', null, null),
    ('blue-tee', 'outfit', 'common', null, null),
    ('yellow-tee', 'outfit', 'common', null, null),
    ('pink-tee', 'outfit', 'common', null, null),
    ('cream-knit-sweater', 'outfit', 'rare', null, null),
    ('forest-sweater', 'outfit', 'rare', null, null),
    ('berry-sweater', 'outfit', 'rare', null, null),
    ('sailor-sweater', 'outfit', 'rare', null, null),
    ('grey-hoodie', 'outfit', 'rare', null, null),
    ('sunset-hoodie', 'outfit', 'rare', null, null),
    ('lavender-hoodie', 'outfit', 'epic', null, null),
    ('starry-hoodie', 'outfit', 'epic', null, null)
on conflict (item_id) do nothing;
