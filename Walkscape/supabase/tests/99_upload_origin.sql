-- Which uploads came from the app and which from a background refresh.
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

insert into tests.users values
    ('uo_ana', '00000000-0000-0000-0000-000000000080'),
    ('uo_ben', '00000000-0000-0000-0000-000000000081');
insert into auth.users (id, email)
select id, name || '@example.com' from tests.users where name like 'uo_%';

select tests.as_user('uo_ana');
select public.upsert_daily_progress(current_date, 'UTC', 1000, 800, 'recorded', now() - interval '3 hours', 'app');
select tests.ok((select uploaded_via = 'app' and last_background_upload_at is null
                 from public.daily_progress where user_id = auth.uid()), 'an upload with the app open is marked app');

select public.upsert_daily_progress(current_date, 'UTC', 3000, 2400, 'recorded', now() - interval '2 hours', 'background');
select tests.ok((select uploaded_via = 'background' and last_background_upload_at is not null and distance_meters = 2400
                 from public.daily_progress where user_id = auth.uid()), 'a background upload is marked and timed');

select public.upsert_daily_progress(current_date, 'UTC', 4000, 3200, 'recorded', now() - interval '1 hour', 'app');
select tests.ok((select uploaded_via = 'app' and last_background_upload_at is not null
                 from public.daily_progress where user_id = auth.uid()), 'a later app upload keeps the last background time');

-- Builds before this change don't send the marker.
select public.upsert_daily_progress(current_date, 'UTC', 4500, 3600, 'recorded', now() - interval '30 minutes');
select tests.ok((select uploaded_via is null and distance_meters = 3600 and last_background_upload_at is not null
                 from public.daily_progress where user_id = auth.uid()), 'older builds still upload, unmarked');

select public.upsert_daily_progress(current_date, 'UTC', 4600, 3700, 'recorded', now() - interval '20 minutes', 'sideways');
select tests.ok((select uploaded_via is null and distance_meters = 3700
                 from public.daily_progress where user_id = auth.uid()), 'unknown markers are ignored, not rejected');
reset role;

-- A stale background upload changes nothing.
select tests.as_user('uo_ben');
select public.upsert_daily_progress(current_date, 'UTC', 2000, 1600, 'recorded', now(), 'app');
select public.upsert_daily_progress(current_date, 'UTC', 500, 400, 'recorded', now() - interval '1 hour', 'background');
select tests.ok((select uploaded_via = 'app' and last_background_upload_at is null and distance_meters = 1600
                 from public.daily_progress where user_id = auth.uid()), 'an out-of-date background upload is ignored');
reset role;

select tests.as_anon();
select tests.fails($$select public.upsert_daily_progress(current_date, 'UTC', 1, 1, 'recorded', now(), 'app')$$,
                   'permission denied', 'signed-out callers still can''t upload');
reset role;
