-- Skandi Fit: escaleras de calistenia reales + calidad de ejecución 1-10.
--
-- Cuatro problemas que arregla esta migración:
--
-- 1. La línea de front lever estaba mal ordenada: one-leg-front-lever estaba en rank 5,
--    DESPUÉS del full lever, cuando es claramente más fácil (una pierna extendida pesa menos
--    que dos). Tampoco tenía escalón de entrada (inverted hang) ni el half-lay entre straddle
--    y full, que es donde vive el salto más grande de toda la línea.
-- 2. Handstand eran 3 escalones (pared -> libre -> una mano) para lo que en la práctica son
--    años de trabajo. Faltaba lo que de verdad construye la parada: la posición contra pared
--    de frente (chest-to-wall), que es la única que obliga a la línea correcta, y el trabajo
--    de balance (heel/toe pulls, weight shift) entre la pared y el hold libre.
-- 3. nordic-curl no tenía línea: era un ejercicio suelto imposible de hacer sin escalones.
-- 4. La calidad de una serie era binaria (hold_clean: limpio / roto / sin marcar). Una repe
--    de nordic bajada a 4 s controlados y una que se desplomó a mitad son las dos "no limpias"
--    y quedaban idénticas en el historial. Ahora es form_quality 1-10.
--
-- Dos columnas más para que subir de nivel sea un criterio y no una corazonada:
--   progression_target_sets — cuántas series hay que clavar en el target, no una sola serie
--     con suerte (el criterio anterior era el mejor set de la sesión, x2 sesiones seguidas).
--   progression_criteria — qué significa "limpio" EN ESTE escalón, en una frase. Se muestra
--     en la tarjeta del ejercicio durante el entrenamiento, que es cuando importa.

-- ---------------------------------------------------------------------------
-- 1. Esquema
-- ---------------------------------------------------------------------------

alter table public.skandi_sets
  add column if not exists form_quality smallint check (form_quality is null or form_quality between 1 and 10);

alter table public.skandi_exercises
  add column if not exists track_quality boolean not null default false,
  add column if not exists progression_target_sets integer not null default 1 check (progression_target_sets between 1 and 10),
  add column if not exists progression_criteria text;

comment on column public.skandi_sets.form_quality is
  'Calidad de ejecución 1-10 de esta serie. Reemplaza a hold_clean (que se conserva como historial: la app lee form_quality y cae a hold_clean true=8 / false=4 para series viejas). 8 o más = cuenta para subir de nivel.';
comment on column public.skandi_exercises.progression_criteria is
  'Qué es un 8+/10 en ESTE escalón. Se muestra durante el entrenamiento.';

-- ---------------------------------------------------------------------------
-- 2. Ejercicios nuevos
-- ---------------------------------------------------------------------------

insert into public.skandi_exercises
  (slug, name, english_name, category, equipment, muscles, media_page_url, instructions, coach_tips, log_mode)
values
  -- Front lever: entrada y el escalón que faltaba antes del full
  ('inverted-hang','Inverted Hang','Inverted Hang','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":40,"Core":30,"Shoulders":20,"Biceps":10}'::jsonb,null,
   '{"Hang from the bar with a shoulder-width overhand grip.","Pull your knees up and roll your hips over until you are hanging upside down.","Extend both legs straight up, body vertical, arms locked.","Hold, squeezing glutes and ribs down so the body is one straight line."}',
   '{"This is where the shoulders and the straight-arm scapular strength for every lever start.","If the shoulders cramp, hold the tuck version until the position stops feeling foreign."}',
   'seconds'),
  ('front-lever-half-lay','Front Lever Half Lay','Front Lever Half Lay','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":50,"Core":30,"Biceps":12,"Shoulders":8}'::jsonb,null,
   '{"Set up as in the straddle front lever, arms locked and torso horizontal.","Bring the legs together and bend the knees to roughly 90 degrees.","Keep the hips fully open, thighs in line with the torso.","Hold, fighting the hips from sagging below the shoulders."}',
   '{"Closing the straddle is a bigger jump than it looks, expect the hold time to halve.","Bend at the knee, never at the hip, or this becomes an advanced tuck again."}',
   'seconds'),
  -- Front lever raises: la parte dinámica de la línea, que hasta ahora era un solo ejercicio
  ('tuck-front-lever-raise','Tuck Front Lever Raise','Tuck Front Lever Raise','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":45,"Core":30,"Biceps":15,"Shoulders":10}'::jsonb,null,
   '{"Start in a dead hang with arms straight and shoulder blades depressed.","Pull the knees to the chest and roll back into a tuck front lever.","Pause one second at horizontal.","Lower back to the hang under control, arms still locked."}',
   '{"The rep is the pull into position, not the swing, so no kipping at the bottom.","Straight arms the whole time or this turns into a hanging knee raise."}',
   'reps'),
  ('advanced-tuck-front-lever-raise','Advanced Tuck Front Lever Raise','Advanced Tuck Front Lever Raise','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":48,"Core":30,"Biceps":13,"Shoulders":9}'::jsonb,null,
   '{"Hang with straight arms and depressed shoulder blades.","Pull into an advanced tuck front lever, hips open, knees bent.","Pause one second with the torso horizontal.","Lower back to the hang with the arms locked."}',
   '{"Open the hips on the way up, not after arriving at horizontal.","If the last rep swings, stop the set, the swing is what stops the progress."}',
   'reps'),
  ('straddle-front-lever-raise','Straddle Front Lever Raise','Straddle Front Lever Raise','Calisthenics','{"Pull-up bar","Bodyweight"}','{"Back":50,"Core":30,"Biceps":12,"Shoulders":8}'::jsonb,null,
   '{"Hang with straight arms and depressed shoulder blades.","Pull into a straddle front lever, legs wide and straight.","Pause one second at horizontal, hips level with the shoulders.","Lower back to the hang under control."}',
   '{"A wider straddle is a shorter lever, narrow it as the reps get easy.","Hips level with the shoulders, if they hang low the rep does not count."}',
   'reps'),
  -- Handstand: los escalones que faltaban entre la pared y el hold libre
  ('wall-plank-hold','Wall Plank Hold','Wall Plank Hold','Calisthenics','{"Wall","Bodyweight"}','{"Shoulders":45,"Core":35,"Triceps":10,"Forearms":10}'::jsonb,null,
   '{"Start in a plank with your feet against the base of the wall.","Walk your feet up the wall while walking your hands closer to it.","Stop when the body is at about 45 degrees, shoulders open over the wrists.","Hold, ribs down and glutes tight."}',
   '{"This builds the shoulder endurance the handstand needs before balance is even a question.","If the lower back arches, walk the hands out a little until it flattens."}',
   'seconds'),
  ('chest-to-wall-handstand','Chest-to-Wall Handstand','Chest-to-Wall Handstand','Calisthenics','{"Wall","Bodyweight"}','{"Shoulders":45,"Core":35,"Forearms":10,"Triceps":10}'::jsonb,null,
   '{"Face the wall and walk up it into a handstand, chest and thighs touching the wall.","Stack shoulders over wrists, hands about 10-15 cm from the wall.","Push the floor away, ribs down, toes pointed, glutes tight.","Come down one leg at a time under control."}',
   '{"This is the only handstand position that forces the correct line, the back-to-wall version lets you arch and hide it.","Log the time you can hold TOUCHING the wall at chest and thighs, not just being upside down."}',
   'seconds'),
  ('handstand-weight-shift','Handstand Weight Shift','Handstand Weight Shift','Calisthenics','{"Wall","Bodyweight"}','{"Shoulders":45,"Core":30,"Forearms":20,"Triceps":5}'::jsonb,null,
   '{"Kick up to a handstand you can hold comfortably, wall or freestanding.","Shift your weight onto one hand, keeping the shoulder stacked over that wrist.","Unweight the other hand until only the fingertips rest on the floor.","Hold the shift, then return to two hands and switch sides."}',
   '{"The shift comes from the shoulder and ribcage, not from bending the hips sideways.","Alternate sides within the set, the non-dominant side is what gates the one-arm."}',
   'seconds'),
  -- Nordic curl: la línea completa, antes era un solo ejercicio sin escalones
  ('nordic-curl-negative','Nordic Curl Negative','Nordic Curl Negative','Calisthenics','{"Bodyweight"}','{"Hamstrings":75,"Glutes":15,"Core":10}'::jsonb,null,
   '{"Kneel with your ankles anchored, hips fully extended, torso in line with the thighs.","Lower forward as slowly as you can control, resisting with the hamstrings.","Catch yourself with your hands only when you can no longer slow the descent.","Push back up with the arms and reset for the next rep."}',
   '{"The only number that matters here is how many seconds the descent lasts, aim for 4-5.","Hips stay open the whole way, the moment they break this becomes a kneeling fall."}',
   'reps'),
  ('nordic-curl-assisted','Assisted Nordic Curl','Assisted Nordic Curl','Calisthenics','{"Bodyweight","Band"}','{"Hamstrings":75,"Glutes":15,"Core":10}'::jsonb,null,
   '{"Anchor a band overhead or to a rack behind you and loop it across your chest.","Kneel with ankles anchored and hips extended.","Lower under control to the floor, then pull yourself back up using the hamstrings.","Use the least band tension that still lets you come back up without hands."}',
   '{"This is the first version with a real concentric, that is the whole point of it.","Downgrade the band before you downgrade the tempo."}',
   'reps'),
  ('nordic-curl-weighted','Weighted Nordic Curl','Weighted Nordic Curl','Calisthenics','{"Bodyweight","Plate"}','{"Hamstrings":75,"Glutes":15,"Core":10}'::jsonb,null,
   '{"Hold a plate against your chest, or wear a weighted vest.","Kneel with ankles anchored, hips fully extended.","Lower under control all the way to the floor without the hands.","Pull yourself back up to the start, still without pushing off."}',
   '{"Add load only once the bodyweight version is 5 clean reps with no hand assist.","Log the added weight in the weight field, the reps stay low on purpose."}',
   'reps')
on conflict (slug) do update set
  name = excluded.name,
  english_name = excluded.english_name,
  category = excluded.category,
  equipment = excluded.equipment,
  muscles = excluded.muscles,
  instructions = excluded.instructions,
  coach_tips = excluded.coach_tips,
  log_mode = excluded.log_mode,
  updated_at = now();

-- ---------------------------------------------------------------------------
-- 3. Front lever (holds): orden correcto, 8 escalones
-- ---------------------------------------------------------------------------

update public.skandi_exercises set
  progression_group='front-lever', progression_rank=1, log_mode='seconds',
  progression_target=45, progression_target_sets=1,
  progression_criteria='Body vertical and still, arms locked, no swinging or shoulder shrugging.'
where slug='inverted-hang';

update public.skandi_exercises set
  progression_group='front-lever', progression_rank=2, log_mode='seconds',
  progression_target=15, progression_target_sets=3,
  progression_criteria='Torso horizontal, back flat, arms locked straight, knees stay glued to the chest.'
where slug='front-lever-tuck';

update public.skandi_exercises set
  progression_group='front-lever', progression_rank=3, log_mode='seconds',
  progression_target=15, progression_target_sets=2,
  progression_criteria='Hips open with thighs off the chest, lower back flat, torso still horizontal.'
where slug='front-lever-advanced-tuck';

update public.skandi_exercises set
  progression_group='front-lever', progression_rank=4, log_mode='seconds',
  progression_target=12, progression_target_sets=2,
  progression_criteria='One leg fully straight and horizontal, hips level with the shoulders. Alternate the working leg between sets.'
where slug='one-leg-front-lever';

update public.skandi_exercises set
  progression_group='front-lever', progression_rank=5, log_mode='seconds',
  progression_target=12, progression_target_sets=2,
  progression_criteria='Both legs straight in a straddle, hips level with the shoulders, no piking.'
where slug='front-lever-straddle';

update public.skandi_exercises set
  progression_group='front-lever', progression_rank=6, log_mode='seconds',
  progression_target=10, progression_target_sets=2,
  progression_criteria='Legs together with knees bent 90 degrees, hips fully open and level with the shoulders.'
where slug='front-lever-half-lay';

update public.skandi_exercises set
  progression_group='front-lever', progression_rank=7, log_mode='seconds',
  progression_target=10, progression_target_sets=2,
  progression_criteria='Whole body horizontal in one line, arms locked, no sag at the hips.'
where slug='front-lever-full';

update public.skandi_exercises set
  progression_group='front-lever', progression_rank=8, log_mode='seconds',
  progression_target=null, progression_target_sets=1,
  progression_criteria='Final rank of the line. Full body horizontal on one arm, hips square to the ceiling.'
where slug='one-arm-front-lever';

-- ---------------------------------------------------------------------------
-- 4. Front lever raises: línea propia (la parte dinámica)
-- ---------------------------------------------------------------------------

update public.skandi_exercises set
  progression_group='front-lever-raise', progression_rank=1, log_mode='reps',
  progression_target=8, progression_target_sets=2,
  progression_criteria='Pulled into position with straight arms, one second pause at horizontal, no kipping.'
where slug='tuck-front-lever-raise';

update public.skandi_exercises set
  progression_group='front-lever-raise', progression_rank=2, log_mode='reps',
  progression_target=6, progression_target_sets=2,
  progression_criteria='Hips open on the way up, one second pause at horizontal, controlled lowering.'
where slug='advanced-tuck-front-lever-raise';

update public.skandi_exercises set
  progression_group='front-lever-raise', progression_rank=3, log_mode='reps',
  progression_target=5, progression_target_sets=2,
  progression_criteria='Legs straight in a straddle, hips level with the shoulders at the top, no swing at the bottom.'
where slug='straddle-front-lever-raise';

update public.skandi_exercises set
  name='Front Lever Raise (Full)', english_name='Front Lever Raise (Full)',
  progression_group='front-lever-raise', progression_rank=4, log_mode='reps',
  progression_target=null, progression_target_sets=1,
  progression_criteria='Final rank of the line. Legs together and straight, pause at horizontal, lowered under control.'
where slug='front-lever-raises';

-- ---------------------------------------------------------------------------
-- 5. Handstand: 7 escalones en vez de 3
-- ---------------------------------------------------------------------------

update public.skandi_exercises set
  progression_group='handstand', progression_rank=1, log_mode='seconds',
  progression_target=45, progression_target_sets=1,
  progression_criteria='Shoulders open over the wrists, ribs down, no arch in the lower back.'
where slug='wall-plank-hold';

update public.skandi_exercises set
  name='Wall Handstand (Back to Wall)', english_name='Wall Handstand (Back to Wall)',
  progression_group='handstand', progression_rank=2, log_mode='seconds',
  progression_target=45, progression_target_sets=1,
  progression_criteria='Heels resting on the wall, shoulders stacked, no banana in the back.'
where slug='wall-handstand';

update public.skandi_exercises set
  progression_group='handstand', progression_rank=3, log_mode='seconds',
  progression_target=60, progression_target_sets=1,
  progression_criteria='Chest and thighs touching the wall the whole hold, hands 10-15 cm out, toes pointed.'
where slug='chest-to-wall-handstand';

update public.skandi_exercises set
  progression_group='handstand', progression_rank=4, log_mode='reps',
  progression_target=10, progression_target_sets=2,
  progression_criteria='One controlled pull per rep, heel or toe leaves the wall and comes back without falling out.'
where slug='heel-pulls-toe-pulls';

update public.skandi_exercises set
  progression_group='handstand', progression_rank=5, log_mode='seconds',
  progression_target=30, progression_target_sets=2,
  progression_criteria='Balanced on fingers with no wall, no walking on the hands, exited on your own terms.'
where slug='freestanding-handstand';

update public.skandi_exercises set
  progression_group='handstand', progression_rank=6, log_mode='seconds',
  progression_target=20, progression_target_sets=2,
  progression_criteria='Weight fully over one shoulder, other hand on fingertips only, hips square.'
where slug='handstand-weight-shift';

update public.skandi_exercises set
  progression_group='handstand', progression_rank=7,
  progression_target=null, progression_target_sets=1,
  progression_criteria='Final rank of the line. Second hand fully off the floor, body still stacked.'
where slug='one-arm-handstand';

-- ---------------------------------------------------------------------------
-- 6. Nordic curl: línea nueva
-- ---------------------------------------------------------------------------

update public.skandi_exercises set
  progression_group='nordic-curl', progression_rank=1, log_mode='reps',
  progression_target=5, progression_target_sets=3,
  progression_criteria='Descent lasts 4-5 seconds with the hips open, hands only catch at the very end.'
where slug='nordic-curl-negative';

update public.skandi_exercises set
  progression_group='nordic-curl', progression_rank=2, log_mode='reps',
  progression_target=6, progression_target_sets=3,
  progression_criteria='Back up without the hands, hips extended throughout, band tension as low as possible.'
where slug='nordic-curl-assisted';

update public.skandi_exercises set
  progression_group='nordic-curl', progression_rank=3, log_mode='reps',
  progression_target=5, progression_target_sets=2,
  progression_criteria='Full descent and full return with no band and no hand push, hips open the whole rep.'
where slug='nordic-curl';

update public.skandi_exercises set
  progression_group='nordic-curl', progression_rank=4, log_mode='reps',
  progression_target=null, progression_target_sets=1,
  progression_criteria='Final rank of the line. Same standard as the bodyweight version, with the plate held on the chest.'
where slug='nordic-curl-weighted';

-- ---------------------------------------------------------------------------
-- 7. Criterios y series objetivo para las líneas que ya existían
-- ---------------------------------------------------------------------------

update public.skandi_exercises set progression_target_sets=2,
  progression_criteria='Knees tucked to the chest, arms locked, body horizontal and still.'
where slug='back-lever-tuck';
update public.skandi_exercises set progression_target_sets=2,
  progression_criteria='Legs straight in a straddle, arms locked, shoulders open with no elbow bend.'
where slug='back-lever-straddle';
update public.skandi_exercises set
  progression_criteria='Final rank of the line. Whole body horizontal and straight, arms locked.'
where slug='back-lever-full';

update public.skandi_exercises set progression_target_sets=2,
  progression_criteria='Shoulders clearly ahead of the wrists, scapulae protracted, hips level.'
where slug='planche-lean';
update public.skandi_exercises set progression_target_sets=2,
  progression_criteria='Feet off the floor, knees tucked, arms locked, shoulders leaning past the wrists.'
where slug='tuck-planche';
update public.skandi_exercises set progression_target_sets=2,
  progression_criteria='Hips open with the back flat, arms locked, no bounce at the shoulder.'
where slug='advanced-tuck-planche';
update public.skandi_exercises set progression_target_sets=2,
  progression_criteria='Legs straight in a straddle, hips level with the shoulders, arms locked.'
where slug='straddle-planche';
update public.skandi_exercises set
  progression_criteria='Final rank of the line. Body horizontal and straight, arms locked.'
where slug='full-planche';

update public.skandi_exercises set progression_target_sets=2,
  progression_criteria='Chest touches the bar, no kipping, controlled descent to a dead hang.'
where slug='chest-to-bar-pull-up';
update public.skandi_exercises set progression_target_sets=2,
  progression_criteria='False grip held the whole rep, wrists reach bar height.'
where slug='false-grip-pull-up';
update public.skandi_exercises set progression_target_sets=2,
  progression_criteria='Descent through the transition takes 3+ seconds without dropping.'
where slug='muscle-up-negative';
update public.skandi_exercises set
  progression_criteria='Final rank of the line. No kipping, no chicken wing, lockout at the top.'
where slug='muscle-up-bar';

-- ---------------------------------------------------------------------------
-- 8. Qué ejercicios piden calidad 1-10
-- ---------------------------------------------------------------------------

-- Todo lo que es una habilidad (tiene línea de progresión) y todo hold estático: la nota
-- de calidad reemplaza al RIR en esos ejercicios, porque una repe de nordic o de front lever
-- raise no se lleva a RIR 2, se lleva hasta que la forma se rompe.
update public.skandi_exercises
  set track_quality = true
where progression_group is not null or log_mode = 'seconds';

-- ---------------------------------------------------------------------------
-- 9. Corrección de la sesión cargada a mano del 17 de agosto (opcional, idempotente)
-- ---------------------------------------------------------------------------

-- Esas elevaciones fueron en straddle, no completas. Si la sesión no existe, no hace nada.
update public.skandi_sets s
set exercise_id = (select id from public.skandi_exercises where slug='straddle-front-lever-raise'),
    updated_at = now()
from public.skandi_sessions ss
where ss.id = s.session_id
  and s.exercise_id = (select id from public.skandi_exercises where slug='front-lever-raises')
  and ss.title = 'Front Lever A + Pull'
  and ss.completed_at >= timestamptz '2026-08-17 00:00:00-07'
  and ss.completed_at <  timestamptz '2026-08-18 00:00:00-07';

-- ---------------------------------------------------------------------------
-- 10. Semilla del escalón actual por línea, a partir de lo ya entrenado
-- ---------------------------------------------------------------------------

-- Sin esto, una rutina que apunta al escalón más alto de una línea nueva (p.ej. "Front Lever
-- Raise (Full)") arrancaría el entrenamiento en la variante más difícil, porque skandi_-
-- progression_state está vacío para los grupos recién creados. Se siembra con la variante más
-- alta que el usuario YA registró; do nothing respeta cualquier escalón elegido a mano.
insert into public.skandi_progression_state (user_id, progression_group, exercise_id)
select distinct on (s.user_id, e.progression_group)
  s.user_id, e.progression_group, e.id
from public.skandi_sets s
join public.skandi_exercises e on e.id = s.exercise_id
where e.progression_group is not null
order by s.user_id, e.progression_group, e.progression_rank desc
on conflict (user_id, progression_group) do nothing;
