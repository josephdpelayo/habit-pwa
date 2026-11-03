-- 145 · Los ejercicios de parada de manos (docs/PROGRAMA_HANDSTAND.md)
--
-- Diez ejercicios nuevos del catálogo —la preparación de muñecas y hombros, los encogimientos,
-- las patadas, la salida en rueda, la caminata y los toques— cada uno con su figura, sus
-- instrucciones en español y en inglés, y su patrón de movimiento.
--
-- **Esto ya no trae un programa.** La primera versión escribía además 12 rutinas fijas y una
-- plantilla de 8 semanas; Joseph decidió el 2 nov 2026 que no quiere un programa cerrado, sino
-- asignar ejercicios según el nivel de cada quien, y dentro de una skill elegir la progresión
-- serie por serie (en una skill la progresión es la carga, no el peso). Nada de eso se corrió
-- nunca en Supabase, así que esta migración se reescribió en lugar de agregar una que deshaga.
-- Los ejercicios y las figuras sirven igual con el modelo nuevo: son contenido, no estructura.
--
-- Dos cosas más que no son del programa y por eso se quedan:
--
--   1. exercise_catalog.instructions_en (requisito permanente de CLAUDE.md): la app hoy lee el
--      español; el día que exista el selector de idioma, el inglés ya está en la base.
--   2. anon dejaba ejecutar apply_coaching_program y ensure_coaching_week_from_template, y su
--      candado (auth.uid() <> p_user_id) no frena una llamada sin sesión, porque null <> x es
--      null. Con la llave pública de la app y el id de alguien se le reescribía la semana.
--      Mismo caso que la 124, y no tiene nada que ver con el handstand.
--
-- Requiere: 037 (exercise_catalog), 142 (animation_url).

begin;

-- ---------------------------------------------------------------------------
-- 1. Inglés en el catálogo
-- ---------------------------------------------------------------------------

alter table public.exercise_catalog add column if not exists instructions_en text;

comment on column public.exercise_catalog.instructions_en is
  'Las instructions en inglés. Requisito permanente: todo texto nuevo nace en los dos idiomas.';

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
-- 5. anon fuera de las funciones que reescriben la semana de alguien
-- ---------------------------------------------------------------------------

-- Cada una solo donde esté, como en la 124: un revoke sobre una función que no existe es un
-- error, y aquí tumbaría toda la migración por una firma que cambió de versión (la 115 dejó
-- apply_coaching_program en cinco argumentos y tiró la de cuatro).
do $$
declare f text;
begin
  foreach f in array array['public.apply_coaching_program(uuid, uuid, date, date, date)',
                           'public.apply_coaching_program(uuid, uuid, date, date)',
                           'public.ensure_coaching_week_from_template(uuid, date)',
                           'public.coaching_week_slots(uuid, uuid, integer)'] loop
    if to_regprocedure(f) is not null then
      execute 'revoke execute on function ' || f || ' from anon';
    else
      raise notice 'No existe %, no hay permiso que quitar', f;
    end if;
  end loop;
end $$;

do $$
declare n_ex int; n_fig int;
begin
  select count(*) into n_ex from public.exercise_catalog
   where slug in ('preparacion-de-munecas','apertura-de-hombros-en-pared','encogimientos-en-pica',
                  'patadas-de-conejo','salida-en-rueda','caminata-en-pared',
                  'encogimientos-de-frente-a-la-pared','patada-a-la-pared',
                  'toques-de-hombro-en-pared','patada-al-equilibrio')
     and is_active and instructions_en is not null and animation_url is not null;
  select count(*) into n_fig from public.exercise_catalog
   where slug in ('hollow-hold','parada-de-rana') and animation_url is not null;
  if n_ex <> 10 or n_fig <> 2 then
    raise exception 'Contenido incompleto: % de 10 ejercicios nuevos, % de 2 figuras', n_ex, n_fig;
  end if;
  raise notice 'Parada de manos: 10 ejercicios nuevos con figura e inglés, y 2 figuras más.';
end $$;

commit;
