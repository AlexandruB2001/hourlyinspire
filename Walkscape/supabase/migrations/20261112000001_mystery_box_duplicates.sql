-- Mystery Box duplicates. The box now rolls from every prize (not just the
-- ones you don't own), so its odds (60/28/10/2 by rarity) hold on every box
-- and the collection is never guaranteed. A duplicate gives coins back by
-- rarity (80/100/150/200): the server charges the net price (150 minus the
-- refund) in the same transaction; when the refund is bigger than the price
-- the difference is credited as wallet.earned["box-bonus-<request>"]. Atomic,
-- and a retry never pays twice. Safe to run again.

insert into public.coin_prices (item, coins) values
    ('duplicate-common', 80),
    ('duplicate-rare', 100),
    ('duplicate-epic', 150),
    ('duplicate-legendary', 200)
on conflict (item) do update set coins = excluded.coins;

alter table public.mystery_box_opens
    add column if not exists coins integer,
    add column if not exists duplicate boolean not null default false,
    add column if not exists refund integer not null default 0;

drop function if exists public.open_mystery_box(uuid, date);

-- Buys and opens a Mystery Box. `p_request_id` makes retries safe: the same
-- request returns the same prize and charges once. `p_day` is the player's
-- local day (festivals). `coins` is what was charged after any refund
-- (negative when a duplicate paid out more than the box cost).
create function public.open_mystery_box(p_request_id uuid, p_day date)
returns table (item_id text, kind text, rarity text, charge_key text, coins integer, duplicate boolean, refund integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
    me uuid := auth.uid();
    price integer;
    doc jsonb;
    md integer;
    roll double precision := random();
    picked_rarity text;
    prize text;
    is_duplicate boolean;
    refund_amount integer := 0;
    net integer;
    box_key text := 'box-' || p_request_id::text;
begin
    if me is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if p_request_id is null or p_day is null
       or p_day > (now() at time zone 'utc')::date + 1 or p_day < (now() at time zone 'utc')::date - 1 then
        raise exception 'invalid_request' using errcode = '22023';
    end if;
    select c.coins into price from public.coin_prices c where c.item = 'mystery-box';
    -- One purchase at a time per player: the save row is the lock.
    select s.save into doc from public.player_saves s where s.user_id = me for update;
    if exists (select 1 from public.mystery_box_opens o where o.user_id = me and o.request_id = p_request_id) then
        return query
            select o.item_id, z.kind, z.rarity, o.charge_key, coalesce(o.coins, price), o.duplicate, o.refund
            from public.mystery_box_opens o join public.mystery_box_prizes z on z.item_id = o.item_id
            where o.user_id = me and o.request_id = p_request_id;
        return;
    end if;
    if doc is null then
        raise exception 'no_cloud_save' using errcode = 'P0002';
    end if;
    md := extract(month from p_day)::integer * 100 + extract(day from p_day)::integer;
    -- A rarity by weight, then a prize of that rarity evenly. Everything is in
    -- the pool except festival accessories while their festival runs.
    with pool as (
        select z.item_id, z.rarity from public.mystery_box_prizes z
        where not (z.festival_start is not null
                   and case when z.festival_start <= z.festival_end then md between z.festival_start and z.festival_end
                            else md >= z.festival_start or md <= z.festival_end end)
    ), weights as (
        select p.rarity, case p.rarity when 'common' then 60 when 'rare' then 28 when 'epic' then 10 else 2 end as weight
        from pool p group by p.rarity
    ), ladder as (
        select w.rarity, sum(w.weight) over (order by w.weight desc, w.rarity) as upto, sum(w.weight) over () as total
        from weights w
    )
    select l.rarity into picked_rarity from ladder l where l.upto > roll * l.total order by l.upto limit 1;
    if picked_rarity is null then
        raise exception 'sold_out' using errcode = 'P0002';
    end if;
    select z.item_id into prize
    from public.mystery_box_prizes z
    where z.rarity = picked_rarity
      and not (z.festival_start is not null
               and case when z.festival_start <= z.festival_end then md between z.festival_start and z.festival_end
                        else md >= z.festival_start or md <= z.festival_end end)
    order by random()
    limit 1;

    is_duplicate := exists (select 1 from public.owned_items o where o.user_id = me and o.item_id = prize)
                    or coalesce(doc -> 'wallet' -> 'ownedItemIDs', '[]'::jsonb) ? prize;
    if is_duplicate then
        select c.coins into refund_amount from public.coin_prices c where c.item = 'duplicate-' || picked_rarity;
        refund_amount := coalesce(refund_amount, 0);
    end if;
    net := price - refund_amount;

    -- The full price must be affordable; a duplicate then costs only the net.
    perform public.charge_coins(me, box_key, price);
    if refund_amount > 0 then
        if net > 0 then
            update public.coin_charges c set amount = net where c.user_id = me and c.key = box_key;
            update public.player_saves s
            set save = jsonb_set(s.save, array['wallet', 'spent', box_key], to_jsonb(net))
            where s.user_id = me;
        else
            delete from public.coin_charges c where c.user_id = me and c.key = box_key;
            update public.player_saves s set save = s.save #- array['wallet', 'spent', box_key] where s.user_id = me;
            if net < 0 then
                update public.player_saves s
                set save = jsonb_set(s.save, array['wallet', 'earned', 'box-bonus-' || p_request_id::text], to_jsonb(-net))
                where s.user_id = me;
            end if;
        end if;
        update public.player_saves s
        set save = jsonb_set(s.save, '{wallet,coins}', to_jsonb(coalesce((s.save #>> '{wallet,coins}')::integer, 0) + refund_amount))
        where s.user_id = me and jsonb_typeof(s.save -> 'wallet' -> 'coins') = 'number';
    else
        insert into public.owned_items (user_id, item_id, source) values (me, prize, 'mystery-box') on conflict do nothing;
        -- The save gets the prize too, so it shows on every phone.
        update public.player_saves s
        set save = jsonb_set(s.save, '{wallet,ownedItemIDs}',
                             coalesce(s.save -> 'wallet' -> 'ownedItemIDs', '[]'::jsonb) || to_jsonb(prize))
        where s.user_id = me and jsonb_typeof(s.save -> 'wallet') = 'object';
    end if;
    insert into public.mystery_box_opens (user_id, request_id, item_id, charge_key, coins, duplicate, refund)
    values (me, p_request_id, prize, box_key, net, is_duplicate, refund_amount);
    return query
        select z.item_id, z.kind, z.rarity, box_key, net, is_duplicate, refund_amount
        from public.mystery_box_prizes z where z.item_id = prize;
end;
$$;

revoke all on function public.open_mystery_box(uuid, date) from public, anon;
grant execute on function public.open_mystery_box(uuid, date) to authenticated;
