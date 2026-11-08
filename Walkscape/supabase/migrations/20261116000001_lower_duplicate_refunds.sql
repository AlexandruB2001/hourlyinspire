-- Duplicates from the Mystery Box give fewer coins back, so a nearly complete
-- collection doesn't get cheaper to finish. Legendary stays at 200. Safe to run again.

update public.coin_prices c
set coins = v.coins
from (values
    ('duplicate-common', 40),
    ('duplicate-rare', 60),
    ('duplicate-epic', 100),
    ('duplicate-legendary', 200)
) as v(item, coins)
where c.item = v.item;
