-- Shared outfits. Reuses kim and leo (friends) and max (stranger) from 50_profile_showcase.sql.
\set ON_ERROR_STOP on
set client_min_messages = notice;
reset role;

select tests.as_user('kim');
select public.set_my_outfit(array['straw-hat', 'red-sneakers', 'guitar']);
select tests.ok((select outfit = array['straw-hat', 'red-sneakers', 'guitar'] from public.friend_showcases()
                 where user_id = tests.id('kim')), 'you see your own outfit');
select tests.fails($$select public.set_my_outfit(array['Not An Id!'])$$, 'invalid_outfit', 'outfit ids must be simple ids');
select tests.fails($$select public.set_my_outfit(array['a','b','c','d','e','f','g','h','i'])$$, 'invalid_outfit',
                   'at most eight pieces');
reset role;

select tests.as_user('leo');
select tests.ok((select outfit[1] = 'straw-hat' from public.friend_showcases() where user_id = tests.id('kim')),
                'friends see your outfit');
-- Either refused or filtered out by row level security; kim's outfit must not change.
do $$ begin
    update public.profiles set outfit = '{}' where id = tests.id('kim');
exception when others then null;
end $$;
reset role;
select tests.ok((select cardinality(outfit) = 3 from public.profiles where id = tests.id('kim')), 'kim''s outfit is unchanged');

select tests.as_user('max');
select tests.ok(not exists (select 1 from public.friend_showcases() where user_id = tests.id('kim')),
                'strangers don''t see it');
reset role;

select tests.as_user('kim');
select public.set_my_outfit(null);
select tests.ok((select outfit = '{}' from public.friend_showcases() where user_id = tests.id('kim')), 'null clears the outfit');
reset role;
select tests.ok(not has_function_privilege('anon', 'public.set_my_outfit(text[])', 'execute'), 'anon cannot set outfits');
