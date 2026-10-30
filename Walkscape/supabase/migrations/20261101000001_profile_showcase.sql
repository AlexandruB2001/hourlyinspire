-- Profile showcase: the title, frame and favourite zone friends and
-- teammates see. Ids are checked for format only; which ones a player has
-- unlocked is decided by the app (see Titles.swift), like the rest of the
-- client-reported progress described in docs/BACKEND.md.

alter table public.profiles
    add column title_id text,
    add column frame_id text,
    add column favorite_zone_id text,
    add constraint profiles_title_id_format check (title_id ~ '^[a-z0-9-]{1,32}$'),
    add constraint profiles_frame_id_format check (frame_id ~ '^[a-z0-9-]{1,32}$'),
    add constraint profiles_favorite_zone_id_format check (favorite_zone_id ~ '^[a-z0-9-]{1,32}$');

grant update (title_id, frame_id, favorite_zone_id) on public.profiles to authenticated;

-- Sets the caller's showcase. Null clears a field.
create function public.set_my_showcase(p_title_id text, p_frame_id text, p_favorite_zone_id text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;
    update public.profiles
    set title_id = p_title_id, frame_id = p_frame_id, favorite_zone_id = p_favorite_zone_id
    where id = auth.uid();
end;
$$;

-- Showcases of the caller's friends and teammates (and the caller).
create function public.friend_showcases()
returns table (user_id uuid, title_id text, frame_id text, favorite_zone_id text)
language sql
stable
security definer
set search_path = ''
as $$
    select p.id, p.title_id, p.frame_id, p.favorite_zone_id
    from public.profiles p
    where p.id = auth.uid()
       or public.is_friend_of_caller(p.id)
       or (public.caller_team_id() is not null
           and exists (select 1 from public.team_members m
                       where m.user_id = p.id and m.team_id = public.caller_team_id()));
$$;

revoke all on function public.set_my_showcase(text, text, text), public.friend_showcases() from public, anon;
grant execute on function public.set_my_showcase(text, text, text), public.friend_showcases() to authenticated;
