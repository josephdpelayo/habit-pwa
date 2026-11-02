-- 145 · Programa «Parada de manos en 8 semanas» (docs/PROGRAMA_HANDSTAND.md)
--
-- 20 minutos, 6 días por semana, cuatro fases de dos semanas (Base, Línea en pared,
-- Equilibrio, Libre). Cada fase termina el sábado de su segunda semana con una prueba, que es
-- el estándar de un escalón de la escalera de parada de manos (141): 1, 3, 4 y 5.
--
-- Todo lo que escribe es del gym y no toca lo de nadie:
--
--   1. Columnas de inglés (requisito permanente de CLAUDE.md): la app hoy lee el español; el
--      día que exista el selector de idioma, el inglés ya está en la base.
--   2. Los 10 ejercicios nuevos del programa en exercise_catalog, con su figura.
--   3. 12 rutinas del gym (Fase 1–4 × A/B/C), owner_id nulo y no is_starter: no aparecen en la
--      lista de nadie hasta que empieza el programa.
--   4. La plantilla: coaching_programs con user_id nulo (114), template_key 'handstand-8', sus
--      48 días y sus 8 semanas. Empezarla es apply_coaching_program sobre la propia cuenta,
--      que ya copia una plantilla y la vuelve de la persona.
--   5. De paso: anon dejaba ejecutar apply_coaching_program y
--      ensure_coaching_week_from_template, y su candado (auth.uid() <> p_user_id) no frena una
--      llamada sin sesión, porque null <> x es null. Con la llave pública de la app y el id de
--      alguien se le reescribía la semana. Mismo caso que la 124.
--
-- Cada ejercicio de las rutinas lleva el MISMO id en las 12 (md5 del slug): "La vez pasada"
-- y las marcas de la escalera van por ex_key, así que la plancha de la fase 1 y la de la
-- prueba son la misma historia.
--
-- Requiere: 037 (exercise_catalog), 114/115 (programas y ciclos), 116 (boards.is_starter),
--           141–143 (escalera de parada de manos y sus figuras).

begin;

-- ---------------------------------------------------------------------------
-- 1. Inglés y la llave de plantilla
-- ---------------------------------------------------------------------------

alter table public.exercise_catalog add column if not exists instructions_en text;
alter table public.boards add column if not exists name_en text;
alter table public.coaching_programs add column if not exists name_en text;
alter table public.coaching_programs add column if not exists notes_en text;
alter table public.coaching_program_weeks add column if not exists note_en text;

-- Qué plantilla es. La copia de cada persona lleva la misma llave (la pone la app al
-- empezar), y así la app sabe que su programa activo es este y le pinta la fase y la prueba.
alter table public.coaching_programs add column if not exists template_key text;
create unique index if not exists idx_coaching_programs_template_key
  on public.coaching_programs(template_key) where user_id is null and template_key is not null;

comment on column public.coaching_programs.template_key is
  'Qué plantilla del gym es (o de cuál salió la copia de una persona). handstand-8: docs/PROGRAMA_HANDSTAND.md.';

-- ---------------------------------------------------------------------------
-- 2. Los ejercicios nuevos
-- ---------------------------------------------------------------------------

insert into public.exercise_catalog
  (name, slug, category, primary_muscle, secondary_muscles, equipment, movement_pattern,
   default_tracking, difficulty, aliases, instructions, instructions_en, animation_url)
values
  ('Preparación de muñecas','preparacion-de-munecas','Movilidad','Antebrazo',array['Hombros'],array['Peso corporal'],'Movilidad','time','basico',
   array['wrist prep','wrist warm-up','calentamiento de muñecas'],
   'En cuadrupedia, manos bajo los hombros y dedos abiertos. Haz círculos de muñeca, luego balancéate adelante y atrás pasando el hombro por delante de la muñeca. Voltea las manos con los dedos hacia las rodillas y repite suave. Termina con pulsos: despega la palma del piso dejando solo los dedos.',
   'On all fours, hands under the shoulders, fingers spread. Circle the wrists, then rock forward and back so the shoulders pass in front of the wrists. Turn the hands so the fingers point to the knees and repeat gently. Finish with pulses: lift the palms, leaving only the fingers on the floor.',
   '/skill-anim/preparacion-de-munecas.svg'),
  ('Apertura de hombros en pared','apertura-de-hombros-en-pared','Movilidad','Hombros',array['Espalda'],array['Pared'],'Movilidad','time','basico',
   array['wall shoulder stretch','wall shoulder opener'],
   'De frente a la pared, apoya las manos a la altura de la cadera y camina hacia atrás hasta que torso y brazos formen una recta, cadera a 90 grados. Deja caer el pecho hacia el piso sin arquear la lumbar. Respira y busca que las orejas queden entre los brazos.',
   'Facing a wall, place the hands at hip height and walk back until torso and arms form one straight line, hips at 90 degrees. Let the chest sink toward the floor without arching the lower back. Breathe and aim to get the ears between the arms.',
   '/skill-anim/apertura-de-hombros-en-pared.svg'),
  ('Encogimientos en pica','encogimientos-en-pica','Calistenia','Hombros',array['Espalda','Tríceps'],array['Peso corporal'],'Empuje vertical','reps','basico',
   array['pike shrugs','pike shoulder shrugs'],
   'En pica: manos en el piso, cadera arriba y brazos rectos junto a las orejas. Sin doblar los codos, empuja el piso para subir los hombros hacia las orejas y luego déjalos bajar. Es el mismo empuje que sostiene la parada de manos.',
   'In a pike: hands on the floor, hips high, arms straight by the ears. Without bending the elbows, push the floor to shrug the shoulders up toward the ears, then let them sink. It is the same push that holds a handstand.',
   '/skill-anim/encogimientos-en-pica.svg'),
  ('Patadas de conejo','patadas-de-conejo','Calistenia','Hombros',array['Core','Antebrazo'],array['Peso corporal'],'Equilibrio','reps','basico',
   array['bunny hops','handstand hops'],
   'En cuclillas, apoya las manos al ancho de hombros frente a ti con los brazos rectos. Salta con los dos pies para subir la cadera por encima de los hombros, rodillas dobladas, y aterriza suave. Mira entre las manos y mantén los brazos bloqueados.',
   'From a squat, place the hands shoulder-width in front of you with straight arms. Hop off both feet to lift the hips over the shoulders, knees bent, and land softly. Look between the hands and keep the arms locked.',
   '/skill-anim/patadas-de-conejo.svg'),
  ('Salida en rueda','salida-en-rueda','Calistenia','Hombros',array['Core'],array['Peso corporal'],'Equilibrio','reps','basico',
   array['cartwheel bail','pirouette bail','handstand bail'],
   'La salida segura de la parada de manos. Cuando sientas que te pasas, saca una mano hacia adelante y gira el cuerpo hacia ese lado, como media rueda de carro, hasta caer de pie junto a tus manos. Practícala primero desde cuclillas y luego desde la pared, a los dos lados.',
   'The safe way out of a handstand. When you feel yourself overbalancing, move one hand forward and turn the body to that side, like half a cartwheel, landing on your feet beside your hands. Practice it from a squat first, then from the wall, on both sides.',
   '/skill-anim/salida-en-rueda.svg'),
  ('Caminata en pared','caminata-en-pared','Calistenia','Hombros',array['Core','Tríceps'],array['Pared'],'Empuje vertical','reps','intermedio',
   array['wall walk','wall walk-up'],
   'Empieza en plancha con los pies contra la base de la pared. Camina los pies por la pared mientras acercas las manos, un paso corto a la vez, hasta quedar con el pecho casi tocando la pared. Baja igual de despacio, sin dejar caer la cadera.',
   'Start in a plank with the feet against the base of the wall. Walk the feet up the wall while bringing the hands closer, one short step at a time, until the chest almost touches the wall. Come down just as slowly, without letting the hips sag.',
   '/skill-anim/caminata-en-pared.svg'),
  ('Encogimientos de frente a la pared','encogimientos-de-frente-a-la-pared','Calistenia','Hombros',array['Tríceps','Espalda'],array['Pared'],'Empuje vertical','reps','intermedio',
   array['wall handstand shrugs','chest to wall shrugs'],
   'En parada de manos de frente a la pared, brazos bloqueados. Empuja el piso para subir el cuerpo unos centímetros, hombros a las orejas, y baja controlado sin doblar los codos. El cuerpo se mueve entero, como una sola pieza.',
   'In a chest-to-wall handstand, arms locked. Push the floor to raise the body a few centimeters, shoulders to the ears, and lower under control without bending the elbows. The body moves as one piece.',
   '/skill-anim/encogimientos-de-frente-a-la-pared.svg'),
  ('Patada a la pared','patada-a-la-pared','Calistenia','Hombros',array['Core','Piernas'],array['Pared'],'Equilibrio','reps','basico',
   array['kick up to wall','wall kick-up'],
   'De espaldas a la pared y a un paso de ella, en zancada con los brazos arriba. Baja las manos al piso a un palmo de la pared, patea con la pierna de atrás y deja que la otra la alcance hasta apoyar los talones. Patea con la cadera, no con fuerza: lo justo para llegar.',
   'Back to the wall, one step away, in a lunge with the arms overhead. Bring the hands to the floor a hand''s width from the wall, kick with the back leg and let the other one follow until the heels rest on the wall. Kick from the hips, not with force: just enough to get there.',
   '/skill-anim/patada-a-la-pared.svg'),
  ('Toques de hombro en pared','toques-de-hombro-en-pared','Calistenia','Hombros',array['Core','Antebrazo'],array['Pared'],'Equilibrio','reps','intermedio',
   array['wall shoulder taps','handstand shoulder taps'],
   'En parada de manos de frente a la pared. Pasa el peso a una mano y despega la otra, primero unos centímetros y después hasta tocar el hombro, y vuelve. Alterna sin que la cadera se mueva de lado: el peso se pasa con el hombro, no con la cadera.',
   'In a chest-to-wall handstand. Shift your weight onto one hand and lift the other, first a few centimeters and later up to the shoulder, then return. Alternate without the hips swaying sideways: the weight moves through the shoulder, not the hips.',
   '/skill-anim/toques-de-hombro-en-pared.svg'),
  ('Patada al equilibrio','patada-al-equilibrio','Calistenia','Hombros',array['Core','Antebrazo'],array['Peso corporal'],'Equilibrio','reps','intermedio',
   array['kick up to handstand','freestanding kick-up'],
   'La misma patada que a la pared, pero sin pared: patea con la pierna de atrás, junta las piernas arriba y busca quedarte. Si te pasas, presiona con los dedos; si no llegas, patea un poco más la siguiente. Si te vas de más, sal en rueda.',
   'The same kick as to the wall, but without it: kick with the back leg, bring the legs together on top and try to stay. If you overbalance, press with the fingers; if you fall short, kick a bit more next time. If you go over, cartwheel out.',
   '/skill-anim/patada-al-equilibrio.svg')
on conflict (slug) do nothing;

-- Dos que ya estaban en el catálogo y no tenían figura. Solo donde está vacío: el video que
-- suba el coach manda (misma regla que la 142).
update public.exercise_catalog set animation_url = '/skill-anim/hollow-hold.svg', updated_at = now()
 where slug = 'hollow-hold' and animation_url is null;
update public.exercise_catalog set animation_url = '/skill-anim/parada-de-rana.svg', updated_at = now()
 where slug = 'parada-de-rana' and animation_url is null;

-- ---------------------------------------------------------------------------
-- 3. Las 12 rutinas
-- ---------------------------------------------------------------------------

create temporary table _hs_boards(
  key text primary key, phase int, kind text, name text, name_en text, level text
) on commit drop;

insert into _hs_boards values
  ('1a', 1, 'A', 'Parada de manos · 1A Línea y fuerza', 'Handstand · 1A Line & strength', 'basico'),
  ('1b', 1, 'B', 'Parada de manos · 1B Equilibrio',      'Handstand · 1B Balance',         'basico'),
  ('1c', 1, 'C', 'Parada de manos · 1C Prueba',          'Handstand · 1C Test',            'basico'),
  ('2a', 2, 'A', 'Parada de manos · 2A Línea y fuerza', 'Handstand · 2A Line & strength', 'basico'),
  ('2b', 2, 'B', 'Parada de manos · 2B Patada y salida', 'Handstand · 2B Kick-up & bail',  'basico'),
  ('2c', 2, 'C', 'Parada de manos · 2C Prueba',          'Handstand · 2C Test',            'basico'),
  ('3a', 3, 'A', 'Parada de manos · 3A Línea y fuerza', 'Handstand · 3A Line & strength', 'intermedio'),
  ('3b', 3, 'B', 'Parada de manos · 3B Equilibrio',      'Handstand · 3B Balance',         'intermedio'),
  ('3c', 3, 'C', 'Parada de manos · 3C Prueba',          'Handstand · 3C Test',            'intermedio'),
  ('4a', 4, 'A', 'Parada de manos · 4A Libre: volumen',  'Handstand · 4A Freestanding: volume',  'intermedio'),
  ('4b', 4, 'B', 'Parada de manos · 4B Libre: entradas', 'Handstand · 4B Freestanding: entries', 'intermedio'),
  ('4c', 4, 'C', 'Parada de manos · 4C Prueba final',    'Handstand · 4C Final test',      'intermedio');

-- Cada fila: rutina, orden, slug, series, objetivo, tipo de objetivo, descanso, cues (ES / EN).
-- Los cues van uno por línea: la hoja de entreno los numera (habit-skills.js cueList).
-- Un objetivo de tiempo es un solo número ('25s'), no un rango: palomear sin escribir guarda
-- ese número, y '20-30s' no se puede leer como segundos. 'max' se escribe a mano: es la prueba.
create temporary table _hs_ex(
  board text, ord int, slug text, sets text, reps text, reps_type text, rest text, note text, note_en text
) on commit drop;

-- La preparación, igual en las 12. Sin músculo en la rutina (como el calentamiento de la 136):
-- no es carga, no suma fatiga en el mapa.
insert into _hs_ex
select b.key, o.ord, o.slug, o.sets, o.reps, 'time', o.rest, o.note, o.note_en
from _hs_boards b, (values
  (1, 'preparacion-de-munecas', '1', '90s', '10s',
   E'Círculos de muñeca, 10 por lado\nBalanceo adelante y atrás en cuadrupedia, hombro por delante de la muñeca\nPulsos de palma: despega la palma, quedan los dedos',
   E'Wrist circles, 10 each way\nRock forward and back on all fours, shoulders past the wrists\nPalm pulses: lift the palm, fingers stay down'),
  (2, 'apertura-de-hombros-en-pared', '2', '30s', '15s',
   E'Brazos y torso en una sola recta\nEl pecho cae hacia el piso, la lumbar no se arquea\nOrejas entre los brazos',
   E'Arms and torso in one straight line\nChest sinks toward the floor, lower back stays flat\nEars between the arms')
) as o(ord, slug, sets, reps, rest, note, note_en);

insert into _hs_ex values
  -- ── Fase 1 · Base ─────────────────────────────────────────────────────────
  ('1a', 3, 'hollow-hold', '3', '20s', 'time', '40s',
   E'Lumbar pegada al piso\nBrazos junto a las orejas, piernas juntas y estiradas\nSi se despega la lumbar, sube las piernas',
   E'Lower back glued to the floor\nArms by the ears, legs together and straight\nIf the lower back lifts, raise the legs'),
  ('1a', 4, 'plancha-en-pared-45-grados', '4', '25s', 'time', '60s',
   E'Hombros encima de las muñecas\nCostillas adentro y glúteo apretado: una sola línea\nEmpuja el piso con toda la mano',
   E'Shoulders over the wrists\nRibs in and glutes tight: one single line\nPush the floor with the whole hand'),
  ('1a', 5, 'encogimientos-en-pica', '3', '10', 'reps', '45s',
   E'Codos bloqueados todo el tiempo\nSube los hombros a las orejas empujando el piso\nBaja lento',
   E'Elbows locked the whole time\nShrug up to the ears by pushing the floor\nLower slowly'),
  ('1a', 6, 'parada-de-rana', '3', '15s', 'time', '30s',
   E'Rodillas apoyadas sobre los codos\nInclínate hasta que los pies se despeguen solos\nMira un poco adelante de las manos',
   E'Knees resting on the elbows\nLean until the feet lift on their own\nLook slightly ahead of the hands'),

  ('1b', 3, 'parada-de-rana', '5', '15s', 'time', '30s',
   E'Rodillas apoyadas sobre los codos\nInclínate hasta que los pies se despeguen solos\nMira un poco adelante de las manos',
   E'Knees resting on the elbows\nLean until the feet lift on their own\nLook slightly ahead of the hands'),
  ('1b', 4, 'patadas-de-conejo', '4', '5', 'reps', '45s',
   E'Brazos bloqueados, mirada entre las manos\nLa cadera sube por encima de los hombros\nAterriza suave, sin ruido',
   E'Arms locked, eyes between the hands\nHips rise over the shoulders\nLand softly, without noise'),
  ('1b', 5, 'salida-en-rueda', '3', '3', 'reps', '30s',
   E'3 por lado, desde cuclillas\nSaca una mano adelante y gira hacia ese lado\nCae de pie junto a las manos',
   E'3 each side, from a squat\nMove one hand forward and turn to that side\nLand on your feet beside your hands'),
  ('1b', 6, 'hollow-hold', '2', '20s', 'time', '40s',
   E'Lumbar pegada al piso\nBrazos junto a las orejas, piernas juntas y estiradas',
   E'Lower back glued to the floor\nArms by the ears, legs together and straight'),

  ('1c', 3, 'plancha-en-pared-45-grados', '2', 'max', 'time', '90s',
   E'PRUEBA: el estándar es 45 s con la línea limpia\nCuenta solo lo que aguantas sin romper la línea\nApunta tus segundos',
   E'TEST: the standard is 45 s with a clean line\nCount only what you hold without breaking the line\nLog your seconds'),
  ('1c', 4, 'hollow-hold', '1', 'max', 'time', '60s',
   E'PRUEBA: el estándar es 30 s\nTermina cuando se despega la lumbar',
   E'TEST: the standard is 30 s\nStop when the lower back lifts'),
  ('1c', 5, 'parada-de-rana', '3', 'max', 'time', '45s',
   E'Juego: ¿cuánto aguantas?\nApunta tu mejor marca',
   E'Play: how long can you hold?\nLog your best'),
  ('1c', 6, 'salida-en-rueda', '2', '3', 'reps', '30s',
   E'3 por lado\nPara pasar de fase tiene que salir sin pensarlo, a los dos lados',
   E'3 each side\nTo move on it has to come out without thinking, on both sides'),

  -- ── Fase 2 · Línea en pared ───────────────────────────────────────────────
  ('2a', 3, 'hollow-hold', '2', '30s', 'time', '30s',
   E'Lumbar pegada al piso\nBrazos junto a las orejas, piernas juntas y estiradas',
   E'Lower back glued to the floor\nArms by the ears, legs together and straight'),
  ('2a', 4, 'caminata-en-pared', '3', '1', 'reps', '60s',
   E'Pasos cortos con manos y pies\nArriba: pecho casi tocando la pared, 10 s\nBaja igual de lento, la cadera no cae',
   E'Short steps with hands and feet\nAt the top: chest almost touching the wall, 10 s\nCome down just as slowly, hips do not sag'),
  ('2a', 5, 'parada-de-manos-de-frente-a-la-pared', '3', '30s', 'time', '75s',
   E'Manos a un palmo de la pared\nEmpuja el piso: hombros a las orejas\nCostillas adentro, puntas estiradas',
   E'Hands a hand''s width from the wall\nPush the floor: shoulders to the ears\nRibs in, toes pointed'),
  ('2a', 6, 'encogimientos-de-frente-a-la-pared', '2', '6', 'reps', '60s',
   E'Codos bloqueados\nEl cuerpo sube entero, como una pieza\nBaja controlado',
   E'Elbows locked\nThe whole body rises as one piece\nLower under control'),

  ('2b', 3, 'patada-a-la-pared', '4', '2', 'reps', '45s',
   E'Brazos arriba en zancada, manos a un palmo de la pared\nPatea con la pierna de atrás; la otra la alcanza\nLo justo para llegar, sin golpear la pared',
   E'Arms up in a lunge, hands a hand''s width from the wall\nKick with the back leg; the other one follows\nJust enough to get there, without hitting the wall'),
  ('2b', 4, 'parada-de-manos-en-pared', '3', '25s', 'time', '60s',
   E'Talones apenas apoyados\nHombros encima de las muñecas\nSin plátano: costillas adentro',
   E'Heels barely resting\nShoulders over the wrists\nNo banana: ribs in'),
  ('2b', 5, 'salida-en-rueda', '3', '2', 'reps', '30s',
   E'2 por lado, desde la pared\nSaca la mano y gira antes de caer\nPractica más el lado que te cuesta',
   E'2 each side, from the wall\nMove the hand and turn before you fall\nPractice the harder side more'),
  ('2b', 6, 'patadas-de-conejo', '3', '6', 'reps', '45s',
   E'Brazos bloqueados, mirada entre las manos\nLa cadera sube por encima de los hombros',
   E'Arms locked, eyes between the hands\nHips rise over the shoulders'),

  ('2c', 3, 'parada-de-manos-de-frente-a-la-pared', '2', 'max', 'time', '120s',
   E'PRUEBA: el estándar es 60 s con la línea limpia\nCuenta solo lo que aguantas sin romper la línea\nApunta tus segundos',
   E'TEST: the standard is 60 s with a clean line\nCount only what you hold without breaking the line\nLog your seconds'),
  ('2c', 4, 'patada-a-la-pared', '3', '2', 'reps', '45s',
   E'Lo justo para llegar, sin golpear la pared',
   E'Just enough to get there, without hitting the wall'),
  ('2c', 5, 'salida-en-rueda', '2', '2', 'reps', '30s',
   E'2 por lado, desde la pared\nPara pasar de fase tiene que salir a los dos lados',
   E'2 each side, from the wall\nTo move on it has to come out on both sides'),
  ('2c', 6, 'hollow-hold', '1', 'max', 'time', '60s',
   E'Juego: ¿cuánto aguantas?',
   E'Play: how long can you hold?'),

  -- ── Fase 3 · Equilibrio ───────────────────────────────────────────────────
  ('3a', 3, 'parada-de-manos-de-frente-a-la-pared', '2', '45s', 'time', '75s',
   E'Primero la línea, después despegarse\nEmpuja el piso: hombros a las orejas\nCostillas adentro, puntas estiradas',
   E'Line first, then leave the wall\nPush the floor: shoulders to the ears\nRibs in, toes pointed'),
  ('3a', 4, 'heel-pulls-toe-pulls', '3', '8', 'reps', '75s',
   E'De frente a la pared, manos un poco más cerca\nDespega el talón o la punta y busca el equilibrio\nCorrige con los dedos, no con los hombros',
   E'Chest to the wall, hands a little closer\nLift the heel or the toes and find the balance\nCorrect with the fingers, not the shoulders'),
  ('3a', 5, 'toques-de-hombro-en-pared', '2', '6', 'reps', '60s',
   E'6 por lado\nPasa el peso con el hombro, la cadera no se mueve\nEmpieza despegando la mano unos centímetros',
   E'6 each side\nShift the weight through the shoulder, the hips stay still\nStart by lifting the hand a few centimeters'),
  ('3a', 6, 'hollow-hold', '2', '30s', 'time', '30s',
   E'Lumbar pegada al piso\nBrazos junto a las orejas, piernas juntas y estiradas',
   E'Lower back glued to the floor\nArms by the ears, legs together and straight'),

  ('3b', 3, 'patadas-de-conejo', '3', '5', 'reps', '45s',
   E'Con pausa: quédate arriba un segundo\nRodillas juntas, cadera sobre los hombros\nBrazos bloqueados',
   E'With a pause: stay up for one second\nKnees together, hips over the shoulders\nArms locked'),
  ('3b', 4, 'patada-al-equilibrio', '5', '2', 'reps', '45s',
   E'Junto a una pared por si acaso, no contra ella\nJunta las piernas arriba\nSi te pasas, dedos; si te vas de más, sal en rueda',
   E'Next to a wall just in case, not against it\nBring the legs together on top\nIf you overbalance, fingers; if you go over, cartwheel out'),
  ('3b', 5, 'salida-en-rueda', '2', '2', 'reps', '30s',
   E'2 por lado, desde la patada',
   E'2 each side, from the kick-up'),
  ('3b', 6, 'parada-de-manos-en-pared', '2', '30s', 'time', '60s',
   E'Talones apenas apoyados\nHombros encima de las muñecas',
   E'Heels barely resting\nShoulders over the wrists'),

  ('3c', 3, 'heel-pulls-toe-pulls', '2', 'max', 'reps', '90s',
   E'PRUEBA: el estándar es 2 series de 10\nCada jalón vuelve a la pared sin caerse\nApunta cuántos salieron',
   E'TEST: the standard is 2 sets of 10\nEach pull comes back to the wall without falling\nLog how many you got'),
  ('3c', 4, 'patada-al-equilibrio', '4', '2', 'reps', '45s',
   E'Cuenta cuántas se quedan 3 s arriba\nLa meta para pasar son 5',
   E'Count how many stay up for 3 s\nThe goal to move on is 5'),
  ('3c', 5, 'salida-en-rueda', '1', '2', 'reps', '30s',
   E'2 por lado',
   E'2 each side'),
  ('3c', 6, 'parada-de-manos-de-frente-a-la-pared', '1', 'max', 'time', '60s',
   E'Juego: tu mejor marca de la fase',
   E'Play: your best mark of the phase'),

  -- ── Fase 4 · Libre ────────────────────────────────────────────────────────
  ('4a', 3, 'parada-de-manos-de-frente-a-la-pared', '1', '45s', 'time', '60s',
   E'Recordatorio de la línea antes de ir libre',
   E'A reminder of the line before going freestanding'),
  -- EMOM: cada intento más su descanso es un minuto, así que el descanso es lo que sobra del
  -- minuto (con un intento de ~40 s, 20 s). El minuto exacto lo lleva el Reloj.
  ('4a', 4, 'parada-de-manos-libre', '8', 'max', 'time', '20s',
   E'EMOM 8 min: un intento al empezar cada minuto (Reloj → Intervalos)\nApunta los segundos de cada intento\nLínea antes que tiempo',
   E'EMOM 8 min: one attempt at the top of every minute (Clock → Intervals)\nLog the seconds of each attempt\nLine before time'),
  ('4a', 5, 'encogimientos-de-frente-a-la-pared', '2', '8', 'reps', '60s',
   E'Codos bloqueados\nEl cuerpo sube entero, como una pieza',
   E'Elbows locked\nThe whole body rises as one piece'),
  ('4a', 6, 'hollow-hold', '2', '30s', 'time', '30s',
   E'Lumbar pegada al piso\nBrazos junto a las orejas, piernas juntas y estiradas',
   E'Lower back glued to the floor\nArms by the ears, legs together and straight'),

  ('4b', 3, 'patada-al-equilibrio', '5', '2', 'reps', '45s',
   E'Cuenta las que pasan 10 s\nJunta las piernas arriba\nSi te vas de más, sal en rueda',
   E'Count the ones that pass 10 s\nBring the legs together on top\nIf you go over, cartwheel out'),
  ('4b', 4, 'heel-pulls-toe-pulls', '2', '10', 'reps', '75s',
   E'Control con los dedos\nCada jalón vuelve sin caerse',
   E'Control with the fingers\nEach pull comes back without falling'),
  ('4b', 5, 'parada-de-manos-libre', '4', 'max', 'time', '60s',
   E'Desde tu mejor entrada\nApunta los segundos\nLínea antes que tiempo',
   E'From your best entry\nLog the seconds\nLine before time'),
  ('4b', 6, 'salida-en-rueda', '1', '2', 'reps', '30s',
   E'2 por lado',
   E'2 each side'),

  ('4c', 3, 'parada-de-manos-de-frente-a-la-pared', '1', '30s', 'time', '60s',
   E'Activación: la línea de siempre',
   E'Activation: the usual line'),
  ('4c', 4, 'parada-de-manos-libre', '3', 'max', 'time', '120s',
   E'PRUEBA FINAL: el estándar es 2 series de 30 s\nCuentan tus 2 mejores intentos\nLínea limpia o no cuenta',
   E'FINAL TEST: the standard is 2 sets of 30 s\nYour 2 best attempts count\nClean line or it does not count'),
  ('4c', 5, 'patada-al-equilibrio', '2', '2', 'reps', '45s',
   E'Juego libre: entradas y salidas',
   E'Free play: entries and exits');

-- Antes de escribir rutinas: todo slug tiene que existir y estar activo. Una rutina con un
-- ejercicio que no está en el catálogo pierde su ficha, su figura y su escalón, así que esto
-- aborta la migración entera en lugar de dejarla a medias.
do $$
declare v_missing text;
begin
  select string_agg(distinct e.slug, ', ') into v_missing
  from _hs_ex e
  where not exists (select 1 from public.exercise_catalog c where c.slug = e.slug and c.is_active);
  if v_missing is not null then
    raise exception 'Faltan en exercise_catalog (o están escondidos): %', v_missing;
  end if;
end $$;

insert into public.boards (id, name, name_en, color, exercises, owner_id, is_starter, goal, level,
                           duration_min, equipment, tags, updated_at)
select md5('habit-handstand:board:' || b.key)::uuid,
       b.name, b.name_en, '#14b8a6',
       (select jsonb_agg(jsonb_build_object(
          'id',                    md5('habit-handstand:ex:' || e.slug)::uuid,
          'catalogId',             c.id::text,
          'name',                  c.name,
          'canonicalName',         c.name,
          'exerciseKey',           c.slug,
          'exerciseType',          c.category,
          'sets',                  e.sets,
          'reps',                  e.reps,
          'repsType',              e.reps_type,
          'rest',                  e.rest,
          'restNext',              e.rest,
          'targetRir',             null,
          'supersetGroup',         '',
          'block',                 '',
          'isSuperset',            false,
          'muscleGroup',           case when c.category = 'Movilidad' then '' else coalesce(c.primary_muscle, '') end,
          'secondaryMuscleGroups', case when c.category = 'Movilidad' then '[]'::jsonb else to_jsonb(coalesce(c.secondary_muscles, array[]::text[])) end,
          'muscles',               jsonb_build_object('primary', case when c.category = 'Movilidad' then null else c.primary_muscle end,
                                                      'secondary', case when c.category = 'Movilidad' then '[]'::jsonb else to_jsonb(coalesce(c.secondary_muscles, array[]::text[])) end),
          'equipment',             to_jsonb(coalesce(c.equipment, array[]::text[])),
          'movementPattern',       coalesce(c.movement_pattern, ''),
          'difficulty',            coalesce(c.difficulty, 'basico'),
          'note',                  e.note,
          'note_en',               e.note_en,
          'description',           e.note,
          'video',                 coalesce(c.video_url, ''),
          'videoTitle',            c.name,
          'videos',                case when coalesce(c.video_url, '') <> ''
                                        then jsonb_build_array(jsonb_build_object('url', c.video_url, 'title', c.name))
                                        else '[]'::jsonb end
        ) order by e.ord)
        from _hs_ex e join public.exercise_catalog c on c.slug = e.slug and c.is_active
        where e.board = b.key),
       null, false, 'Parada de manos', b.level, 20, array['Pared','Peso corporal'],
       case when b.kind = 'C' then array['programa-handstand','prueba'] else array['programa-handstand'] end,
       now()
from _hs_boards b
on conflict (id) do update set
  name = excluded.name, name_en = excluded.name_en, color = excluded.color,
  exercises = excluded.exercises, is_starter = false, goal = excluded.goal, level = excluded.level,
  duration_min = excluded.duration_min, equipment = excluded.equipment, tags = excluded.tags,
  updated_at = now();

-- ---------------------------------------------------------------------------
-- 4. La plantilla: 8 semanas, 6 días
-- ---------------------------------------------------------------------------

insert into public.coaching_programs (id, user_id, name, name_en, notes, notes_en, is_active,
                                      created_by, weeks, start_date, template_key)
values (md5('habit-handstand:program')::uuid, null,
        'Parada de manos en 8 semanas', 'Handstand in 8 weeks',
        '20 minutos al día, 6 días por semana. Cuatro fases de dos semanas: Base, Línea en pared, Equilibrio y Libre. Cada fase termina con una prueba el sábado; si no la pasas, repites la fase.',
        '20 minutes a day, 6 days a week. Four two-week phases: Base, Wall line, Balance and Freestanding. Each phase ends with a test on Saturday; if you do not pass it, you repeat the phase.',
        false, null, 8, null, 'handstand-8')
on conflict (id) do update set
  name = excluded.name, name_en = excluded.name_en, notes = excluded.notes, notes_en = excluded.notes_en,
  weeks = excluded.weeks, template_key = excluded.template_key, updated_at = now();

delete from public.coaching_program_days where program_id = md5('habit-handstand:program')::uuid;

-- Lunes a sábado: A B A B A C. Domingo sin fila: descanso. Semana N es de la fase ceil(N/2).
insert into public.coaching_program_days (program_id, week_index, dow, board_id, board_name, board_color)
select md5('habit-handstand:program')::uuid, w.n, d.dow,
       md5('habit-handstand:board:' || ((w.n + 1) / 2) || lower(d.kind))::uuid,
       b.name, '#14b8a6'
from generate_series(1, 8) as w(n)
cross join (values (0, 'A'), (1, 'B'), (2, 'A'), (3, 'B'), (4, 'A'), (5, 'C')) as d(dow, kind)
join _hs_boards b on b.key = ((w.n + 1) / 2) || lower(d.kind);

delete from public.coaching_program_weeks where program_id = md5('habit-handstand:program')::uuid;

insert into public.coaching_program_weeks (program_id, week_index, phase, note, note_en)
select md5('habit-handstand:program')::uuid, w.n,
       case when w.n % 2 = 0 then 'test' else 'acumulacion' end,
       'Fase ' || f.n || ' · ' || f.es || case when w.n % 2 = 0 then ' · el sábado es la prueba' else '' end,
       'Phase ' || f.n || ' · ' || f.en || case when w.n % 2 = 0 then ' · test on Saturday' else '' end
from generate_series(1, 8) as w(n)
join (values (1, 'Base', 'Base'), (2, 'Línea en pared', 'Wall line'),
             (3, 'Equilibrio', 'Balance'), (4, 'Libre', 'Freestanding')) as f(n, es, en)
  on f.n = (w.n + 1) / 2;

-- ---------------------------------------------------------------------------
-- 5. anon fuera de las funciones que reescriben la semana de alguien
-- ---------------------------------------------------------------------------

revoke execute on function public.apply_coaching_program(uuid, uuid, date, date, date) from anon;
revoke execute on function public.ensure_coaching_week_from_template(uuid, date) from anon;
revoke execute on function public.coaching_week_slots(uuid, uuid, integer) from anon;

do $$
declare n_boards int; n_days int; n_weeks int;
begin
  select count(*) into n_boards from public.boards where 'programa-handstand' = any(tags) and owner_id is null;
  select count(*) into n_days from public.coaching_program_days where program_id = md5('habit-handstand:program')::uuid;
  select count(*) into n_weeks from public.coaching_program_weeks where program_id = md5('habit-handstand:program')::uuid;
  if n_boards <> 12 or n_days <> 48 or n_weeks <> 8 then
    raise exception 'Programa incompleto: % rutinas (12), % días (48), % semanas (8)', n_boards, n_days, n_weeks;
  end if;
  raise notice 'Programa «Parada de manos en 8 semanas»: 12 rutinas, 48 días, 8 semanas.';
end $$;

commit;
