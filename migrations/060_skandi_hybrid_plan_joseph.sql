-- Seeds Joseph's "Plan hibrido final v2" (calistenia + hipertrofia + base aerobica) as six
-- skandi_templates + skandi_template_items, one per weekday Mon-Sat (Sun is pure Z2
-- running/mobility with no gym exercises, so no template is created for it — log those runs
-- via the app's external-activity log instead). Adds the accessory exercises the plan calls
-- for that aren't in the catalog yet; front lever / handstand / planche holds reuse the
-- existing progression-chained exercises (migration 059) so the routine slot stays fixed
-- while the actual variant trained advances via skandi_progression_state.
--
-- Weighted/ring variants of bodyweight moves (weighted dips, ring or weighted push-ups) reuse
-- the base exercise with a descriptive note rather than adding near-duplicate catalog rows —
-- same pattern as migration 050's "Lastrado con 15kg" on plain Dips.

insert into public.skandi_exercises
  (slug, name, english_name, category, equipment, muscles, instructions, coach_tips)
values
  ('front-lever-raises','Front Lever Raises','Front Lever Raises','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":45,"Core":25,"Biceps":15,"Shoulders":15}'::jsonb,
   '{"Hang from the bar and pull into your current front lever hold position.","Keeping arms straight, raise your hips and legs from a lower hang up toward the lever line.","Pause briefly near the top before lowering under control.","Reset to a dead hang or the bottom position between reps."}',
   '{"Keep the movement strict, no kipping to generate momentum.","Stop the set the moment your line breaks down, not when you physically fail."}'),
  ('weighted-pull-up','Weighted Pull Up','Weighted Pull Up','Calisthenics','{"Pull-up bar","Weight belt","Bodyweight"}','{"Back":50,"Biceps":25,"Forearms":15,"Core":10}'::jsonb,
   '{"Attach weight via a dip belt or held between your feet.","Hang with a shoulder-width overhand grip.","Pull your chest toward the bar without kipping.","Lower under control to a full hang."}',
   '{"Add weight only once bodyweight sets feel controlled at the top of the rep range.","Drop the weight before your form breaks down."}'),
  ('straight-arm-pulldown','Straight-Arm Pulldown','Straight-Arm Pulldown','Strength','{"Cable"}','{"Back":60,"Shoulders":15,"Triceps":15,"Core":10}'::jsonb,
   '{"Grip a straight or rope attachment on a high cable.","Keep a slight bend in your elbows and brace your core.","Pull the bar down in an arc to your thighs, leading with your lats.","Return under control without letting the weight stack slam."}',
   '{"Keep the movement in your shoulders, not your elbows.","This is a great primer before front lever or pull-up work."}'),
  ('incline-dumbbell-curl','Incline Dumbbell Curl','Incline Dumbbell Curl','Strength','{"Dumbbells","Bench"}','{"Biceps":80,"Forearms":20}'::jsonb,
   '{"Sit back on an incline bench with arms hanging straight down.","Keep your elbows pinned behind your torso throughout.","Curl the dumbbells up without swinging your shoulders forward.","Lower slowly to get a full stretch at the bottom."}',
   '{"The incline angle removes momentum, so use less weight than a standing curl.","Control the eccentric, that is where this variation earns its keep."}'),
  ('pogo-jumps','Pogo Jumps','Pogo Jumps','Calisthenics','{"Bodyweight"}','{"Calves":60,"Quads":25,"Core":15}'::jsonb,
   '{"Stand tall with knees almost straight.","Bounce continuously off the balls of your feet using mostly your ankles.","Keep ground contact time as short as possible.","Keep your torso upright throughout the set."}',
   '{"Think stiff spring, not a squat jump.","Stop if your calves start to feel loaded down instead of reactive."}'),
  ('cmj-vertical-jump','Countermovement Jump (CMJ)','Countermovement Jump (CMJ)','Calisthenics','{"Bodyweight"}','{"Quads":40,"Glutes":30,"Calves":20,"Hamstrings":10}'::jsonb,
   '{"Stand with feet shoulder-width apart.","Dip quickly into a quarter squat and swing your arms back.","Explode upward as high as you can, reaching or swinging arms up.","Land softly and reset fully before the next rep."}',
   '{"Rest fully between reps, this is a power exercise not conditioning.","Chase jump height and landing quality, not fatigue."}'),
  ('broad-jump','Broad Jump','Broad Jump','Calisthenics','{"Bodyweight"}','{"Quads":35,"Glutes":35,"Hamstrings":20,"Calves":10}'::jsonb,
   '{"Stand with feet shoulder-width apart, arms ready to swing.","Dip and swing your arms back to load the jump.","Drive forward and up explosively, jumping for maximum distance.","Land softly with both feet, absorbing through your hips and knees."}',
   '{"Stick the landing under control before resetting for the next rep.","Rest fully between attempts to keep quality high."}'),
  ('standing-calf-raise','Standing Calf Raise','Standing Calf Raise','Strength','{"Machine","Bodyweight"}','{"Calves":90,"Quads":10}'::jsonb,
   '{"Stand on the balls of your feet on a raised platform or machine.","Lower your heels below the platform for a full stretch.","Press up onto your toes as high as you can.","Pause briefly at the top before lowering with control."}',
   '{"Avoid bouncing at the bottom, control the full range.","Point toes straight ahead unless training a specific calf angle."}'),
  ('hip-thrust','Hip Thrust','Hip Thrust','Strength','{"Barbell","Bench"}','{"Glutes":65,"Hamstrings":20,"Core":15}'::jsonb,
   '{"Rest your upper back against a bench with a barbell over your hips.","Plant your feet flat, shoulder-width apart.","Drive through your heels to raise your hips until your torso is parallel to the floor.","Squeeze your glutes at the top, then lower with control."}',
   '{"Tuck your chin slightly to avoid overextending your lower back.","Pause and squeeze hard at the top of every rep."}'),
  ('reverse-lunge-step-up','Reverse Lunge / Step-Up','Reverse Lunge / Step-Up','Strength','{"Dumbbells","Box"}','{"Quads":40,"Glutes":40,"Hamstrings":15,"Core":5}'::jsonb,
   '{"Stand tall holding dumbbells at your sides, or set up in front of a box.","For the reverse lunge, step backward into a lunge and drive through your front heel to return.","For the step-up, place one foot on a box and drive through it to stand tall.","Keep your torso upright and control the descent on both variations."}',
   '{"Pick whichever variation feels cleaner on your knees that day.","Keep most of your weight on the working leg, not the trailing one."}'),
  ('seated-calf-raise','Seated Calf Raise','Seated Calf Raise','Strength','{"Machine"}','{"Calves":90,"Quads":10}'::jsonb,
   '{"Sit with the balls of your feet on the platform, pads on your knees.","Lower your heels for a full stretch at the bottom.","Press up onto your toes as high as possible.","Pause at the top before lowering with control."}',
   '{"The bent-knee position targets the soleus more than standing raises.","Keep reps slow, this muscle responds well to time under tension."}'),
  ('front-lever-row','Front Lever Row','Front Lever Row','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":45,"Biceps":20,"Core":25,"Shoulders":10}'::jsonb,
   '{"Hang from the bar and pull into a front lever or tuck front lever position.","Keeping your body line, row your chest toward the bar bending your elbows.","Pause briefly with your chest near the bar.","Extend your arms back out without losing your body line."}',
   '{"Keep the hips level, do not let them drop as you row.","Regress the lever angle before you regress the rowing range."}'),
  ('explosive-pull-up','Explosive Pull-Up (Chest to Bar)','Explosive Pull-Up (Chest to Bar)','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":45,"Biceps":25,"Shoulders":15,"Forearms":15}'::jsonb,
   '{"Hang from the bar with an active shoulder position.","Pull explosively so your chest reaches toward the bar.","Control the descent back to a dead hang.","Reset fully before the next explosive rep."}',
   '{"Quality over quantity, stop when the explosiveness drops off.","This builds directly toward the muscle-up pull phase."}'),
  ('scapular-pull-up','Scapular Pull-Up','Scapular Pull-Up','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":40,"Shoulders":30,"Forearms":20,"Core":10}'::jsonb,
   '{"Hang from the bar with arms fully straight.","Without bending your elbows, pull your shoulder blades down and together.","Hold the top position briefly.","Relax back to a dead hang under control."}',
   '{"Elbows stay locked the entire rep, this is a scapula-only movement.","Great activation drill before heavier pulling work."}'),
  ('heel-pulls-toe-pulls','Heel Pulls / Toe Pulls','Heel Pulls / Toe Pulls','Calisthenics','{"Wall","Bodyweight"}','{"Shoulders":40,"Core":40,"Forearms":20}'::jsonb,
   '{"Kick up into a wall handstand facing the wall.","Pull one heel away from the wall slightly, balancing on the other hand fingers pressure.","Return that foot to the wall and repeat with slight toe pulls for finer balance.","Keep breathing steadily and reset if you lose the line."}',
   '{"Small pulls only, this is a balance drill not a strength one.","Use this to build the finger-pressure control freestanding handstand needs."}'),
  ('reverse-fly','Reverse Fly','Reverse Fly','Strength','{"Dumbbells","Bench"}','{"Shoulders":70,"Back":30}'::jsonb,
   '{"Hinge at the hips holding a dumbbell in each hand, torso near parallel to the floor.","Keep a slight bend in your elbows.","Raise the dumbbells out to the sides, squeezing your shoulder blades together.","Lower with control back to the start."}',
   '{"Avoid using momentum, lead with your elbows not your hands.","Keep your neck neutral, do not crane forward."}')
on conflict (slug) do update set
  name = excluded.name,
  english_name = excluded.english_name,
  category = excluded.category,
  equipment = excluded.equipment,
  muscles = excluded.muscles,
  instructions = excluded.instructions,
  coach_tips = excluded.coach_tips,
  updated_at = now();

-- Clear Mon-Sat on Joseph's existing templates so the new plan owns those days. Existing
-- templates (e.g. "Arms", "Push Calisthenics") are unscheduled, not deleted — same
-- weekday-bump behavior the app itself does when you assign a routine to an occupied day.
update public.skandi_templates
set weekday = null, updated_at = now()
where user_id = (select id from auth.users where email = 'josephdpelayo@gmail.com')
  and weekday between 0 and 5;

-- LUNES (0) — Front Lever A + Pull
with new_template as (
  insert into public.skandi_templates (user_id, name, notes, weekday, is_public)
  values ((select id from auth.users where email = 'josephdpelayo@gmail.com'), 'Front Lever A + Pull', 'Maxima frescura para front lever. Handstand micro es opcional (8-10 min: 3 holds + 4-6 intentos, tecnico sin fatiga).', 0, true)
  returning id
)
insert into public.skandi_template_items (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, note)
select nt.id, ex.id, v.sort_order, v.target_sets, v.target_reps, v.target_rest_sec, v.note
from new_template nt
cross join (
  values
    (0, 'front-lever-tuck',        4, '8-12s',  150, 'RPE tecnico 7-8'),
    (1, 'front-lever-raises',      2, '4-6',     150, 'Control total'),
    (2, 'weighted-pull-up',        3, '4-6',     180, 'RIR 1-2'),
    (3, 'cable-seated-row',        2, '8-12',    120, 'RIR 1-2'),
    (4, 'straight-arm-pulldown',   2, '10-15',    90, 'RIR 1-2'),
    (5, 'incline-dumbbell-curl',   3, '8-12',     90, 'RIR 1-2'),
    (6, 'cable-face-pull',         2, '12-20',    75, 'RIR 2')
) as v(sort_order, slug, target_sets, target_reps, target_rest_sec, note)
join public.skandi_exercises ex on ex.slug = v.slug;

-- MARTES (1) — Pierna A + Pliometria
with new_template as (
  insert into public.skandi_templates (user_id, name, notes, weekday, is_public)
  values ((select id from auth.users where email = 'josephdpelayo@gmail.com'), 'Pierna A + Pliometria', 'Potencia + hipertrofia sin carrera. Pliometria (41 contactos) va antes de la fuerza.', 1, true)
  returning id
)
insert into public.skandi_template_items (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, note)
select nt.id, ex.id, v.sort_order, v.target_sets, v.target_reps, v.target_rest_sec, v.note
from new_template nt
cross join (
  values
    (0, 'pogo-jumps',                          2, '10',              50, 'Reactivos'),
    (1, 'cmj-vertical-jump',                    3, '4',               75, 'Maxima calidad'),
    (2, 'broad-jump',                           3, '3',               90, 'Maxima calidad'),
    (3, 'barbell-squat',                        4, '6-8',            180, 'RIR 1-2 (o Smith squat)'),
    (4, 'smith-machine-bulgarian-split-squat',  3, '8-10 por pierna',150, 'RIR 1-2'),
    (5, 'leg-extension-machine',                3, '10-15',           90, 'RIR 1-2'),
    (6, 'standing-calf-raise',                  4, '10-15',           75, 'RIR 1-2')
) as v(sort_order, slug, target_sets, target_reps, target_rest_sec, note)
join public.skandi_exercises ex on ex.slug = v.slug;

-- MIERCOLES (2) — Handstand + Planche A + Push
with new_template as (
  insert into public.skandi_templates (user_id, name, notes, weekday, is_public)
  values ((select id from auth.users where email = 'josephdpelayo@gmail.com'), 'Handstand + Planche A + Push', 'Primer dia de carrera: tranquilo. PM: Run Z2 30-40 min, RPE 2-3/10, talk test positivo.', 2, true)
  returning id
)
insert into public.skandi_template_items (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, note)
select nt.id, ex.id, v.sort_order, v.target_sets, v.target_reps, v.target_rest_sec, v.note
from new_template nt
cross join (
  values
    (0, 'wall-handstand',            3, '30-45s', 75,  'Tecnico'),
    (1, 'freestanding-handstand',    6, '15-30s',180,  'Descanso completo'),
    (2, 'planche-lean',              3, '12-20s',120,  'RPE tecnico 7-8'),
    (3, 'tuck-planche',              3, '6-10s', 150,  'RPE tecnico 7-8 (tuck / advanced tuck)'),
    (4, 'handstand-push-up-wall',    3, '5-8',   150,  'RIR 1-2 (o pike push-up)'),
    (5, 'dips',                      3, '6-10',  150,  'Lastrado, RIR 1-2'),
    (6, 'dumbbell-lateral-raise',    4, '12-20',  75,  'RIR 1-2')
) as v(sort_order, slug, target_sets, target_reps, target_rest_sec, note)
join public.skandi_exercises ex on ex.slug = v.slug;

-- JUEVES (3) — Pierna B + Core
with new_template as (
  insert into public.skandi_templates (user_id, name, notes, weekday, is_public)
  values ((select id from auth.users where email = 'josephdpelayo@gmail.com'), 'Pierna B + Core', 'Dar 24h antes de la calidad del viernes. Si el viernes llegas pesado, recorta 1 set de RDL y 1 de lunge.', 3, true)
  returning id
)
insert into public.skandi_template_items (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, note)
select nt.id, ex.id, v.sort_order, v.target_sets, v.target_reps, v.target_rest_sec, v.note
from new_template nt
cross join (
  values
    (0, 'romanian-deadlift',       4, '6-10',           150, 'RIR 2'),
    (1, 'hip-thrust',              3, '8-12',            120, 'RIR 1-2'),
    (2, 'seated-leg-curl-machine', 4, '8-15',             90, 'RIR 1-2 (o Nordic asistido)'),
    (3, 'reverse-lunge-step-up',   2, '8-12 por pierna', 120, 'RIR 2'),
    (4, 'seated-calf-raise',       3, '12-20',            75, 'RIR 1-2'),
    (5, 'hanging-leg-raise',       3, '8-15',             75, 'RIR 1-2'),
    (6, 'hollow-body-hold',        3, '20-40s',           60, 'Calidad')
) as v(sort_order, slug, target_sets, target_reps, target_rest_sec, note)
join public.skandi_exercises ex on ex.slug = v.slug;

-- VIERNES (4) — Front Lever B + Muscle-Up
with new_template as (
  insert into public.skandi_templates (user_id, name, notes, weekday, is_public)
  values ((select id from auth.users where email = 'josephdpelayo@gmail.com'), 'Front Lever B + Muscle-Up', 'Segundo dia de carrera: unico estimulo intenso. PM: Run calidad 35-45 min total, idealmente 6-8h despues (solo 8-15 min realmente intensos).', 4, true)
  returning id
)
insert into public.skandi_template_items (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, note)
select nt.id, ex.id, v.sort_order, v.target_sets, v.target_reps, v.target_rest_sec, v.note
from new_template nt
cross join (
  values
    (0, 'muscle-up-bar',        3, '1-3',  150, 'Reps limpias'),
    (1, 'front-lever-tuck',     3, '8-12s',120, 'RPE tecnico 7 (hold mas facil que lunes)'),
    (2, 'front-lever-row',      2, '4-8',  150, 'RIR tecnico 1-2'),
    (3, 'explosive-pull-up',    2, '3-5',  150, 'Velocidad'),
    (4, 'dumbbell-hammer-curl', 2, '10-12', 90, 'RIR 1-2'),
    (5, 'scapular-pull-up',     2, '8-12',  75, 'Control escapular')
) as v(sort_order, slug, target_sets, target_reps, target_rest_sec, note)
join public.skandi_exercises ex on ex.slug = v.slug;

-- SABADO (5) — Handstand + Planche B + Push
with new_template as (
  insert into public.skandi_templates (user_id, name, notes, weekday, is_public)
  values ((select id from auth.users where email = 'josephdpelayo@gmail.com'), 'Handstand + Planche B + Push', 'Segundo empuje, sin cargar piernas (se reservan para el fondo del domingo). Si hombro/codo/muneca cargados, reduce primero planche B, no el handstand.', 5, true)
  returning id
)
insert into public.skandi_template_items (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, note)
select nt.id, ex.id, v.sort_order, v.target_sets, v.target_reps, v.target_rest_sec, v.note
from new_template nt
cross join (
  values
    (0, 'freestanding-handstand',   8, '15-30s', 180, 'Descanso completo'),
    (1, 'heel-pulls-toe-pulls',     3, '4-6',     90, 'Control de balance'),
    (2, 'pseudo-planche-push-up',   3, '6-10',   120, 'RIR tecnico 1-2'),
    (3, 'planche-lean',             2, '12-20s', 120, 'RPE tecnico 7'),
    (4, 'push-up',                  3, '8-12',   120, 'Lastrado o en anillas, RIR 1-2'),
    (5, 'dumbbell-lateral-raise',   4, '12-20',   75, 'RIR 1-2'),
    (6, 'reverse-fly',              3, '12-20',   75, 'RIR 1-2')
) as v(sort_order, slug, target_sets, target_reps, target_rest_sec, note)
join public.skandi_exercises ex on ex.slug = v.slug;
