-- Adds the plain bodyweight Push-Up (missing from the catalog) and seeds Joseph's
-- Wednesday routine as a skandi_templates + skandi_template_items set, matching the
-- app's own weekday indexing (Mon=0 ... Sun=6, see DOW/todayDow() in skandi.html).

insert into public.skandi_exercises
  (slug, name, english_name, category, equipment, muscles, media_page_url, instructions, coach_tips)
values
  ('push-up','Push Up','Push Up','Calisthenics','{"Bodyweight"}','{"Chest":45,"Triceps":25,"Shoulders":20,"Core":10}'::jsonb,null,
   '{"Set your hands just outside shoulder width, body in a straight line.","Brace your core and squeeze your glutes.","Lower your chest to just above the floor, elbows at roughly 45 degrees.","Press back up to full lockout without letting your hips sag."}',
   '{"Keep your neck neutral, eyes slightly ahead of your hands.","If form breaks down, drop to knees rather than grinding out bad reps."}')
on conflict (slug) do update set
  name = excluded.name,
  english_name = excluded.english_name,
  category = excluded.category,
  equipment = excluded.equipment,
  muscles = excluded.muscles,
  media_page_url = excluded.media_page_url,
  instructions = excluded.instructions,
  coach_tips = excluded.coach_tips,
  updated_at = now();

-- Mirror the app's own "one routine per weekday" behavior (assignOwnRoutineToDay in
-- skandi.html bumps any existing template on that day to weekday = null) before
-- inserting the new one.
update public.skandi_templates
set weekday = null, updated_at = now()
where user_id = (select id from auth.users where email = 'josephdpelayo@gmail.com')
  and weekday = 2;

with new_template as (
  insert into public.skandi_templates (user_id, name, notes, weekday, is_public)
  values (
    (select id from auth.users where email = 'josephdpelayo@gmail.com'),
    'Miércoles',
    null,
    2,
    true
  )
  returning id
)
insert into public.skandi_template_items
  (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, note)
select nt.id, ex.id, v.sort_order, v.target_sets, v.target_reps, v.target_rest_sec, v.note
from new_template nt
cross join (
  values
    (0, 'wall-handstand',                     4, '20-30s', 180, null),
    (1, 'pseudo-planche-push-up',              3, '5-8',    180, null),
    (2, 'shoulder-press',                      4, '8-12',   180, null),
    (3, 'dumbbell-lateral-raise',              3, '12-15',   90, null),
    (4, 'smith-machine-incline-bench-press',   4, '8-12',   180, null),
    (5, 'dips',                                3, 'máx',     90, 'Lastrado con 15kg'),
    (6, 'cable-crossover-fly',                 3, '12-15',   90, null),
    (7, 'rope-triceps-extension',              3, '12-15',   90, null),
    (8, 'push-up',                             1, 'máx',     90, null)
) as v(sort_order, slug, target_sets, target_reps, target_rest_sec, note)
join public.skandi_exercises ex on ex.slug = v.slug;
