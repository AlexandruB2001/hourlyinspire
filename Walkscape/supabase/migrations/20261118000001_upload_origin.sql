-- Records whether a day's walking was uploaded with the app open or by a
-- background refresh, so we can tell whether background uploads work.
-- Builds that don't send p_uploaded_via keep working: the parameter is optional.
-- Safe to run again.

alter table public.daily_progress
    add column if not exists uploaded_via text,
    add column if not exists last_background_upload_at timestamptz;

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'daily_progress_uploaded_via_check') then
        alter table public.daily_progress
            add constraint daily_progress_uploaded_via_check check (uploaded_via in ('app', 'background'));
    end if;
end;
$$;

drop function if exists public.upsert_daily_progress(date, text, integer, integer, public.distance_source, timestamptz);
drop function if exists public.upsert_daily_progress(date, text, integer, integer, public.distance_source, timestamptz, text);

-- Idempotent upsert of the caller's totals for one day. Re-sending the same
-- values changes nothing; an upload older than the stored one is ignored.
create function public.upsert_daily_progress(
    p_local_date date,
    p_time_zone text,
    p_steps integer,
    p_distance_meters integer,
    p_distance_source public.distance_source,
    p_client_updated_at timestamptz,
    p_uploaded_via text default null
)
returns public.daily_progress
language plpgsql
security invoker
set search_path = ''
as $$
declare
    result public.daily_progress;
    via text := case when p_uploaded_via in ('app', 'background') then p_uploaded_via end;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated' using errcode = '28000';
    end if;

    insert into public.daily_progress as d
        (user_id, local_date, time_zone, steps, distance_meters, distance_source, client_updated_at,
         uploaded_via, last_background_upload_at)
    values
        (auth.uid(), p_local_date, p_time_zone, p_steps, p_distance_meters, p_distance_source, p_client_updated_at,
         via, case when via = 'background' then now() end)
    on conflict (user_id, local_date) do update
        set time_zone = excluded.time_zone,
            steps = excluded.steps,
            distance_meters = excluded.distance_meters,
            distance_source = excluded.distance_source,
            client_updated_at = excluded.client_updated_at,
            uploaded_via = excluded.uploaded_via,
            last_background_upload_at = coalesce(excluded.last_background_upload_at, d.last_background_upload_at)
        where d.client_updated_at < excluded.client_updated_at
    returning * into result;

    if result is null then
        select * into result from public.daily_progress
        where user_id = auth.uid() and local_date = p_local_date;
    end if;
    return result;
end;
$$;

revoke execute on function
    public.upsert_daily_progress(date, text, integer, integer, public.distance_source, timestamptz, text)
    from public, anon;
grant execute on function
    public.upsert_daily_progress(date, text, integer, integer, public.distance_source, timestamptz, text)
    to authenticated;
