-- Skandi Fit: progression readiness targets + fill out under-populated skill lines.
--
-- progression_target is the performance (seconds for log_mode='seconds', reps for
-- log_mode='reps') that has to be hit CLEAN in each of two consecutive sessions on the
-- CURRENT rank before the app suggests leveling up to the next one. Numbers are the widely-
-- cited community/coaching benchmarks for these skills (Overcoming Gravity /
-- r/bodyweightfitness progression standards), not this crew's own testing — adjust freely
-- per exercise if the coach wants different thresholds. Left null on the last rank of every
-- line: there's nothing to advance to, so no target is needed.

alter table public.skandi_exercises add column if not exists progression_target integer;

-- Front Lever
update public.skandi_exercises set progression_target=20 where slug='front-lever-tuck';
update public.skandi_exercises set progression_target=15 where slug='front-lever-advanced-tuck';
update public.skandi_exercises set progression_target=12 where slug='front-lever-straddle';
update public.skandi_exercises set progression_target=10 where slug='front-lever-full';
update public.skandi_exercises set progression_target=10 where slug='one-leg-front-lever';
-- one-arm-front-lever: final rank, no target

-- Back Lever
update public.skandi_exercises set progression_target=20 where slug='back-lever-tuck';
update public.skandi_exercises set progression_target=15 where slug='back-lever-straddle';
-- back-lever-full: final rank, no target

-- Planche
update public.skandi_exercises set progression_target=20 where slug='planche-lean';
update public.skandi_exercises set progression_target=15 where slug='tuck-planche';
update public.skandi_exercises set progression_target=12 where slug='advanced-tuck-planche';
update public.skandi_exercises set progression_target=10 where slug='straddle-planche';
-- full-planche: final rank, no target

-- Handstand: was a 2-step line (wall -> freestanding) with nothing after freestanding. Adds
-- one-arm-handstand as the capstone rank, matching the other three lines' pattern of ending
-- on a near-elite variant.
update public.skandi_exercises set progression_target=60 where slug='wall-handstand';
update public.skandi_exercises set progression_target=30 where slug='freestanding-handstand';

insert into public.skandi_exercises
  (slug, name, english_name, category, equipment, muscles, media_page_url, instructions, coach_tips, progression_group, progression_rank, log_mode)
values
  ('one-arm-handstand','One-Arm Handstand','One-Arm Handstand','Calisthenics','{"Bodyweight"}','{"Shoulders":45,"Core":35,"Forearms":15,"Triceps":5}'::jsonb,null,
   '{"Kick up to a freestanding handstand you can already hold comfortably for 30+ seconds.","Shift your weight onto one hand while the other lightly taps for balance only.","Lift the tapping hand off for as long as you can hold the line.","Bring the second hand back down before you lose the position, not after."}',
   '{"Most people train this for years after the two-hand freestanding hold, be patient.","A slight lean toward the working shoulder is normal, do not fight it."}',
   'handstand',3,'seconds')
on conflict (slug) do update set
  name = excluded.name,
  english_name = excluded.english_name,
  category = excluded.category,
  equipment = excluded.equipment,
  muscles = excluded.muscles,
  instructions = excluded.instructions,
  coach_tips = excluded.coach_tips,
  progression_group = excluded.progression_group,
  progression_rank = excluded.progression_rank,
  log_mode = excluded.log_mode,
  updated_at = now();

-- Muscle-Up: previously a single loose exercise with no line before it. Adds the standard
-- three-step lead-in (explosive pulling, false-grip strength, then the transition itself via
-- slow negatives) before the existing muscle-up-bar, which becomes the line's final rank.
insert into public.skandi_exercises
  (slug, name, english_name, category, equipment, muscles, media_page_url, instructions, coach_tips, progression_group, progression_rank, log_mode, progression_target)
values
  ('chest-to-bar-pull-up','Chest-to-Bar Pull-Up','Chest-to-Bar Pull-Up','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":45,"Biceps":25,"Shoulders":15,"Forearms":15}'::jsonb,null,
   '{"Hang from the bar with an overhand grip, shoulder-width or slightly wider.","Pull explosively, driving your elbows down and back.","Touch your upper chest to the bar, not just your chin.","Lower with control back to a dead hang."}',
   '{"This is the explosive pulling strength the muscle-up transition needs, not just endurance.","Keep the bar path close to your body the whole way up."}',
   'muscle-up',1,'reps',5),
  ('false-grip-pull-up','False-Grip Pull-Up','False-Grip Pull-Up','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Forearms":35,"Back":30,"Biceps":20,"Shoulders":15}'::jsonb,null,
   '{"Set your grip with the bar low in your palm, wrists rolled slightly over the top.","Hang and pull up keeping that wrist position the whole rep.","Pull until your wrists reach bar height, not just your chin.","Lower with control without letting the grip roll back to normal."}',
   '{"Expect real forearm fatigue at first, this grip is unfamiliar.","Practice the false grip in a dead hang before adding pulling reps."}',
   'muscle-up',2,'reps',5),
  ('muscle-up-negative','Muscle-Up Negative','Muscle-Up Negative','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":35,"Chest":20,"Triceps":20,"Biceps":15,"Core":10}'::jsonb,null,
   '{"Start at the top of a muscle-up, arms locked out above the bar, false grip on.","Lower your chest back toward the bar as slowly as you can control.","Continue lowering through the transition into a hanging position.","Reset with a jump or a spot back to the top and repeat."}',
   '{"This drills the exact transition path in reverse, where most muscle-up attempts actually fail.","Slow the descent down most through the mid-transition, not just the top and bottom."}',
   'muscle-up',3,'reps',3)
on conflict (slug) do update set
  name = excluded.name,
  english_name = excluded.english_name,
  category = excluded.category,
  equipment = excluded.equipment,
  muscles = excluded.muscles,
  instructions = excluded.instructions,
  coach_tips = excluded.coach_tips,
  progression_group = excluded.progression_group,
  progression_rank = excluded.progression_rank,
  log_mode = excluded.log_mode,
  progression_target = excluded.progression_target,
  updated_at = now();

update public.skandi_exercises set progression_group='muscle-up', progression_rank=4 where slug='muscle-up-bar';
-- muscle-up-bar: final rank, no target
