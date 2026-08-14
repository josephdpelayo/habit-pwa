-- Adds the missing Front Raise to the Skandi Fit catalog (crew reported it was absent).

insert into public.skandi_exercises
  (slug, name, english_name, category, equipment, muscles, instructions, coach_tips)
values
  ('dumbbell-front-raise','Dumbbell Front Raise','Dumbbell Front Raise','Strength','{"Dumbbells"}','{"Shoulders": 80, "Chest": 15, "Core": 5}'::jsonb,
   '{"Stand tall holding a dumbbell in each hand in front of your thighs.","Keeping a slight bend in your elbows, raise one or both arms straight in front of you to shoulder height.","Pause briefly at the top without shrugging your shoulders up.","Lower with control back to the start."}',
   '{"Use lighter weight than a lateral raise, strict form matters more than load here.","Avoid swinging the dumbbells up with your hips or lower back."}')
on conflict (slug) do nothing;
