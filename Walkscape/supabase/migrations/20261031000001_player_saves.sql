-- Cloud save: one private row per player holding their Apple Health
-- progression, wallet, journal, reward ledger and companion (see
-- CloudSave.swift), so a new phone can restore everything.
--
-- The app always merges before writing (nothing earned on either device is
-- lost), and writes are guarded by a version number so two phones saving at
-- once can't overwrite each other: a stale write fails with save_conflict and
-- the app fetches, merges and retries.

create table public.player_saves (
    user_id uuid primary key references public.profiles (id) on delete cascade,
    save jsonb not null,
    version integer not null default 1,
    updated_at timestamptz not null default now(),
    constraint player_saves_is_object check (jsonb_typeof(save) = 'object'),
    constraint player_saves_size check (octet_length(save::text) <= 1048576)
);

alter table public.player_saves enable row level security;
revoke all on public.player_saves from anon, authenticated;

-- The caller's save, or no row if they have none yet.
create function public.get_player_save()
returns table (save jsonb, version integer, updated_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
    select s.save, s.version, s.updated_at from public.player_saves s where s.user_id = auth.uid();
$$;

-- Stores the caller's save if `p_base_version` is the version they last read
-- (0 when they had none). Returns the new version.
create function public.put_player_save(p_save jsonb, p_base_version integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    new_version integer;
begin
    if auth.uid() is null then
        raise exception 'not_signed_in' using errcode = '42501';
    end if;
    if p_base_version = 0 then
        insert into public.player_saves (user_id, save) values (auth.uid(), p_save)
        on conflict (user_id) do nothing
        returning version into new_version;
    else
        update public.player_saves
        set save = p_save, version = version + 1, updated_at = now()
        where user_id = auth.uid() and version = p_base_version
        returning version into new_version;
    end if;
    if new_version is null then
        raise exception 'save_conflict' using errcode = '40001';
    end if;
    return new_version;
end;
$$;

revoke all on function public.get_player_save(), public.put_player_save(jsonb, integer) from public, anon;
grant execute on function public.get_player_save(), public.put_player_save(jsonb, integer) to authenticated;
