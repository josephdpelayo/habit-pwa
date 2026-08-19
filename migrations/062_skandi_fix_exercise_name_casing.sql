-- "Cable skull crushes" was the only exercise name in the catalog not in Title Case
-- (every other entry is, e.g. "Cable Triceps Pushdown") — a plain data-entry inconsistency
-- spotted during a UX pass, not a behavior change.

update public.skandi_exercises set
  name = 'Cable Skull Crushes',
  updated_at = now()
where slug = 'cable-skull-crushes';
