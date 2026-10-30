-- Push notification device tokens.
--
-- The app registers its APNs token here after the player allows
-- notifications. The send-push Edge Function (supabase/functions/send-push)
-- reads tokens with the service role when a friend request or team invite is
-- created, so the recipient hears about it even with the app closed.
--
-- Tokens are private: clients can only add or remove their own, through the
-- functions below, and can never read any token back.

create table public.push_tokens (
    token text primary key,
    user_id uuid not null references public.profiles (id) on delete cascade,
    environment text not null check (environment in ('sandbox', 'production')),
    -- Mirrors the in-app "Friends & teams" notification switch.
    social boolean not null default true,
    updated_at timestamptz not null default now(),
    constraint push_tokens_token_format check (token ~ '^[0-9a-f]{64,200}$')
);

create index push_tokens_user_idx on public.push_tokens (user_id);

alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon, authenticated;

-- Registers (or moves) a device token to the caller. A token belongs to one
-- device, so if someone else signed in on this phone before, it moves over.
create function public.register_push_token(p_token text, p_environment text, p_social boolean default true)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not_signed_in' using errcode = '42501';
    end if;
    insert into public.push_tokens (token, user_id, environment, social, updated_at)
    values (lower(p_token), auth.uid(), p_environment, p_social, now())
    on conflict (token) do update
        set user_id = excluded.user_id, environment = excluded.environment,
            social = excluded.social, updated_at = now();
end;
$$;

-- Removes one of the caller's tokens (signing out, or notifications turned off).
create function public.unregister_push_token(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
    delete from public.push_tokens where token = lower(p_token) and user_id = auth.uid();
$$;

revoke all on function public.register_push_token(text, text, boolean), public.unregister_push_token(text)
from public, anon;
grant execute on function public.register_push_token(text, text, boolean), public.unregister_push_token(text)
to authenticated;
