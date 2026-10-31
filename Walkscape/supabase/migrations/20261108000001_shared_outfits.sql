-- The outfit friends and teammates see on your walker. Like the rest of the
-- showcase, which items you own is decided by the app; ids are checked for
-- format only. friend_showcases() gains the outfit column.

create function public.valid_item_ids(p_ids text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
    select coalesce(cardinality(p_ids), 0) <= 8
       and coalesce((select bool_and(i ~ '^[a-z0-9-]{1,32}$') from unnest(p_ids) i), true);
$$;

alter table public.profiles
    add column outfit text[] not null default '{}',
    add constraint profiles_outfit_format check (public.valid_item_ids(outfit));

-- Sets the caller's outfit (item ids in draw order). Null clears it.
create function public.set_my_outfit(p_outfit text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    if not public.valid_item_ids(coalesce(p_outfit, '{}')) then
        raise exception 'invalid_outfit' using errcode = '22023';
    end if;
    update public.profiles set outfit = coalesce(p_outfit, '{}') where id = auth.uid();
end;
$$;

drop function public.friend_showcases();

-- Showcases of the caller's friends and teammates (and the caller).
create function public.friend_showcases()
returns table (user_id uuid, title_id text, frame_id text, favorite_zone_id text, outfit text[])
language sql
stable
security definer
set search_path = ''
as $$
    select p.id, p.title_id, p.frame_id, p.favorite_zone_id, p.outfit
    from public.profiles p
    where p.id = auth.uid()
       or public.is_friend_of_caller(p.id)
       or (public.caller_team_id() is not null
           and exists (select 1 from public.team_members m
                       where m.user_id = p.id and m.team_id = public.caller_team_id()));
$$;

revoke all on function public.valid_item_ids(text[]) from public, anon, authenticated;
revoke all on function public.set_my_outfit(text[]), public.friend_showcases() from public, anon;
grant execute on function public.set_my_outfit(text[]), public.friend_showcases() to authenticated;
