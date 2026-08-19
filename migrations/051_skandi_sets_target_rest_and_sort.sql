-- Denormalizes target_rest_sec and sort_order onto skandi_sets so an active workout's
-- exercise list can be derived entirely from the session's own sets, independent of
-- skandi_template_items. This is what makes swapping an exercise mid-workout safe: the
-- swap only touches this session's rows, never the shared template, and it survives a
-- page reload because the app no longer has to re-read the (unswapped) template to know
-- which exercises are in the workout.

alter table public.skandi_sets add column if not exists target_rest_sec integer;
alter table public.skandi_sets add column if not exists sort_order integer;

update public.skandi_sets s
set target_rest_sec = ti.target_rest_sec,
    sort_order = ti.sort_order
from public.skandi_sessions sess
join public.skandi_template_items ti
  on ti.template_id = sess.template_id
where s.session_id = sess.id
  and ti.exercise_id = s.exercise_id
  and (s.target_rest_sec is null or s.sort_order is null);
