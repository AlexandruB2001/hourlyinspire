-- Community distance tests.
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

select coalesce(sum(distance_meters), 0) as expected from public.daily_progress
where local_date between current_date - 1 and current_date + 1
  and public.progress_review_reason(local_date, time_zone, steps, distance_meters, updated_at) is null \gset

select tests.as_user('kim');
select tests.ok(public.community_distance(current_date - 1, current_date + 1) = :expected,
                'the community total adds everyone''s full daily distance');
select tests.ok(public.community_distance(current_date + 10, current_date + 20) = 0, 'empty ranges are zero');
select tests.ok(public.community_distance(current_date - 400, current_date + 1)
                <= public.community_distance(current_date - 62, current_date + 1) + public.community_distance(current_date - 400, current_date - 63),
                'ranges are limited to about two months');
reset role;

select tests.ok(not has_function_privilege('anon', 'public.community_distance(date, date)', 'execute'),
                'anon cannot read the community total');
