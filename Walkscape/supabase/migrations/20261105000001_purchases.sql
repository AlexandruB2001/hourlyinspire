-- App Store purchases, verified on the server.
--
-- Rows are written only by the verify-purchase and app-store-notifications
-- Edge Functions (service role) after checking Apple's signature, so a
-- client can never grant itself a purchase. Each row is one purchase
-- (original transaction); subscriptions update expires_at as they renew,
-- and refunds set revoked_at. Purchases are tied to the account through the
-- appAccountToken the app sends with every purchase.

create table public.purchases (
    original_transaction_id text primary key,
    user_id uuid not null references public.profiles (id) on delete cascade,
    product_id text not null,
    environment text not null check (environment in ('Sandbox', 'Production', 'Xcode', 'LocalTesting')),
    purchased_at timestamptz not null,
    expires_at timestamptz,
    revoked_at timestamptz,
    updated_at timestamptz not null default now(),
    constraint purchases_product_format check (product_id ~ '^com\.alexandrub\.walkscape\.[a-z0-9.-]+$')
);

create index purchases_user_idx on public.purchases (user_id);

alter table public.purchases enable row level security;
revoke all on public.purchases from anon, authenticated;

-- The caller's active purchases: bundles forever, subscriptions until they
-- expire, nothing that was refunded.
create function public.my_entitlements()
returns table (product_id text, expires_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
    select p.product_id, p.expires_at
    from public.purchases p
    where p.user_id = auth.uid()
      and p.revoked_at is null
      and (p.expires_at is null or p.expires_at > now());
$$;

-- Whether a player currently has Walkscape Plus (for showing premium frames
-- to friends). Only reveals yes/no for the caller's friends and teammates.
create function public.has_plus(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select (p_user_id = auth.uid() or public.is_friend_of_caller(p_user_id))
       and exists (select 1 from public.purchases p
                   where p.user_id = p_user_id and p.product_id like 'com.alexandrub.walkscape.plus.%'
                     and p.revoked_at is null and p.expires_at > now());
$$;

revoke all on function public.my_entitlements(), public.has_plus(uuid) from public, anon;
grant execute on function public.my_entitlements(), public.has_plus(uuid) to authenticated;
