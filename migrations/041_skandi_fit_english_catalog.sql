-- Skandi Fit should be English-first. Translate the initial seeded catalog.

alter table public.skandi_exercises
  alter column category set default 'Strength';

update public.skandi_exercises set
  slug='barbell-bench-press',
  name='Barbell Bench Press',
  english_name='Barbell Bench Press',
  category='Strength',
  equipment='{"Barbell","Bench"}',
  muscles='{"Chest":60,"Triceps":25,"Shoulders":15}'::jsonb,
  instructions='{"Set your shoulder blades back and down.","Keep your feet planted.","Lower the bar under control to your chest.","Press without losing upper-back tension."}',
  coach_tips='{"Do not bounce the bar.","Keep your wrists neutral."}',
  updated_at=now()
where slug='bench-press-barra';

update public.skandi_exercises set
  name='Dumbbell Bench Press',
  english_name='Dumbbell Bench Press',
  category='Strength',
  equipment='{"Dumbbells","Bench"}',
  muscles='{"Chest":55,"Triceps":25,"Shoulders":20}'::jsonb,
  instructions='{"Start with the dumbbells over your chest.","Lower with elbows around 45 degrees.","Press up without crashing the dumbbells together."}',
  coach_tips='{"Control the range.","Do not lose tension at the bottom."}',
  updated_at=now()
where slug='dumbbell-bench-press';

update public.skandi_exercises set
  slug='barbell-squat',
  name='Barbell Squat',
  english_name='Barbell Squat',
  category='Strength',
  equipment='{"Barbell","Rack"}',
  muscles='{"Quads":45,"Glutes":30,"Hamstrings":15,"Core":10}'::jsonb,
  instructions='{"Set the bar securely on your back.","Track knees in line with your feet.","Lower with control.","Drive the floor away to stand up."}',
  coach_tips='{"Do not let your knees cave in.","Keep your torso braced."}',
  updated_at=now()
where slug='sentadilla-barra';

update public.skandi_exercises set
  slug='romanian-deadlift',
  name='Romanian Deadlift',
  english_name='Romanian Deadlift',
  category='Strength',
  equipment='{"Barbell","Dumbbells"}',
  muscles='{"Hamstrings":45,"Glutes":35,"Back":10,"Core":10}'::jsonb,
  instructions='{"Push your hips back.","Keep your spine neutral.","Keep the weight close to your body.","Stand tall by squeezing your glutes."}',
  coach_tips='{"Do not turn it into a squat.","Feel the stretch in your hamstrings."}',
  updated_at=now()
where slug='peso-muerto-rumano';

update public.skandi_exercises set
  slug='wide-grip-pull-ups',
  name='Wide Grip Pull Ups',
  english_name='Wide Grip Pull Ups',
  category='Calisthenics',
  equipment='{"Pull-up bar","Bodyweight"}',
  muscles='{"Back":55,"Biceps":25,"Core":10,"Forearms":10}'::jsonb,
  instructions='{"Hang under control.","Set your shoulder blades.","Pull your chest toward the bar.","Lower without dropping loose."}',
  coach_tips='{"Avoid kicking.","Leave one rep in reserve if technique breaks."}',
  updated_at=now()
where slug='dominadas-pronas';

update public.skandi_exercises set
  slug='supinated-pull-ups',
  name='Supinated Pull Ups',
  english_name='Supinated Pull Ups',
  category='Calisthenics',
  equipment='{"Pull-up bar","Bodyweight"}',
  muscles='{"Biceps":40,"Back":40,"Core":10,"Forearms":10}'::jsonb,
  instructions='{"Use palms facing you.","Keep shoulders down.","Pull until your chin clears the bar.","Lower with control."}',
  coach_tips='{"If your elbow hurts, try neutral grip.","Do not over-arch your back to compensate."}',
  updated_at=now()
where slug='dominadas-supinas';

update public.skandi_exercises set
  slug='t-bar-row',
  name='T-Bar Row',
  english_name='T-Bar Row',
  category='Strength',
  equipment='{"Barbell","Dumbbells"}',
  muscles='{"Back":55,"Biceps":20,"Core":15,"Shoulders":10}'::jsonb,
  instructions='{"Set a stable torso angle.","Pull with your elbows.","Pause at the top.","Lower without rounding."}',
  coach_tips='{"Do not turn the row into a hip swing."}',
  updated_at=now()
where slug='remo-en-t';

update public.skandi_exercises set
  slug='shoulder-press',
  name='Shoulder Press',
  english_name='Shoulder Press',
  category='Strength',
  equipment='{"Barbell","Dumbbells"}',
  muscles='{"Shoulders":55,"Triceps":25,"Core":20}'::jsonb,
  instructions='{"Keep ribs down.","Press vertically.","Lock out with control.","Lower to a safe depth."}',
  coach_tips='{"Brace before each press."}',
  updated_at=now()
where slug='press-militar';

update public.skandi_exercises set
  slug='dips',
  name='Dips',
  english_name='Dips',
  category='Calisthenics',
  equipment='{"Parallel bars","Bodyweight"}',
  muscles='{"Triceps":40,"Chest":35,"Shoulders":15,"Core":10}'::jsonb,
  instructions='{"Keep shoulders away from your ears.","Lower with control.","Press until arms extend.","Keep your core tight."}',
  coach_tips='{"Do not force depth if your shoulder feels off."}',
  updated_at=now()
where slug='fondos-paralelas';

update public.skandi_exercises set
  slug='dumbbell-curl',
  name='Dumbbell Curl',
  english_name='Dumbbell Curl',
  category='Strength',
  equipment='{"Dumbbells"}',
  muscles='{"Biceps":75,"Forearms":25}'::jsonb,
  instructions='{"Keep elbows close.","Curl without swinging.","Pause at the top.","Lower slowly."}',
  coach_tips='{"Less ego, more control."}',
  updated_at=now()
where slug='curl-mancuernas';

update public.skandi_exercises set
  slug='rope-triceps-extension',
  name='Rope Triceps Extension',
  english_name='Rope Triceps Extension',
  category='Strength',
  equipment='{"Cable","Rope"}',
  muscles='{"Triceps":85,"Forearms":15}'::jsonb,
  instructions='{"Keep elbows fixed.","Extend down.","Open the rope at the bottom.","Return with control."}',
  coach_tips='{"Avoid moving your shoulders to help."}',
  updated_at=now()
where slug='extension-triceps-cuerda';

update public.skandi_exercises set
  name='Plank',
  english_name='Plank',
  category='Core',
  equipment='{"Bodyweight"}',
  muscles='{"Core":70,"Shoulders":15,"Glutes":15}'::jsonb,
  instructions='{"Elbows under shoulders.","Ribs down.","Glutes active.","Breathe without losing position."}',
  coach_tips='{"Stop before your form breaks."}',
  updated_at=now()
where slug='plank';
