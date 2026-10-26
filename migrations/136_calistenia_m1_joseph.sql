-- Calistenia de Joseph (planificación M1 de Algecalistenia) como rutinas suyas en HABIT.
--
-- Es una siembra de datos, no un cambio de esquema. Del PDF entran solo Empuje,
-- Tirón y Handstand; la Pierna queda fuera a propósito (la lleva por su lado).
--
-- Lo que deja en su cuenta:
--
--   · Cuatro rutinas PROPIAS (owner_id = Joseph, color MEMBER_ROUTINE_COLOR):
--     «Empuje», «Empuje ½», «Tirón» y «Handstand». Son suyas y no del gym
--     porque es su plan personal: las puede editar desde Entrenar y nadie más
--     las ve (política de la 070).
--
--   · Handstand es una sesión aparte, no un bloque dentro de Empuje/Tirón: el
--     PDF lo pone todos los días, y un día del programa admite una sola rutina
--     (idx_coaching_program_days_slot, 115). Se arranca desde «Entrenar ahora».
--
--   · Un programa INACTIVO «Calistenia M1» con la semana del PDF: lunes y
--     miércoles Empuje, martes y viernes Tirón, sábado Empuje ½. Jueves (pierna)
--     y domingo (descanso) quedan sin fila. Inactivo para no pisar la semana que
--     ya tenga: se activa desde Entrenar → programa cuando él quiera.
--
-- «Empuje ½» es el sábado: los mismos ejercicios con la mitad de las series.
-- El PDF solo dice «½ empuje»; esa lectura es una suposición.
--
-- Los ids de las rutinas y de cada ejercicio son fijos (md5 de una clave): las
-- series que registra se cuelgan del id del ejercicio, así que volver a correr
-- esto actualiza las rutinas sin dejar su historial huérfano.
--
-- Solo se enlazan al catálogo los ejercicios que SON el mismo movimiento (ficha
-- y video correctos). El resto lleva su músculo escrito aquí, para que cuente
-- en el mapa de fatiga aunque no tenga ficha.

begin;

do $$
declare
  v_color constant text := '#a78bfa';  -- MEMBER_ROUTINE_COLOR en app.html
  v_user      uuid;
  v_user_name text;
  v_program   uuid;
  v_missing   text;
  r           record;
begin
  -- ── 1. El socio ────────────────────────────────────────────────────────────
  select p.id, p.name into v_user, v_user_name
  from public.profiles p
  join auth.users u on u.id = p.id
  where lower(u.email) = 'josephdpelayo@gmail.com';

  if v_user is null then
    raise exception 'No hay perfil para josephdpelayo@gmail.com.';
  end if;
  raise notice 'Socio: % [%]', v_user_name, v_user;

  v_program := md5('calistenia-m1:' || v_user || ':program')::uuid;

  -- ── 2. Los ejercicios ──────────────────────────────────────────────────────
  -- Mismo shape que escribe el constructor de rutinas (saveRoutineSb /
  -- addExerciseSb). El calentamiento lleva «calentamiento» o «movilidad» en el
  -- nombre: es lo que mira isWarmupExercise para no arrancar el descanso de 90 s.
  -- reps 'fallo' / 'max' se pintan «al fallo» / «al máximo» (repsWordEs) y no
  -- se suponen al palomear: esas se escriben.
  create temp table m1_ex on commit drop as
  select
    v.rutina, v.ord, v.clave, v.catalogo, v.nombre, v.tipo, v.series, v.reps,
    v.reps_type, v.descanso, v.rir, v.mg, v.secundarios, v.equipo, v.patron, v.nota
  from (values
    -- ── Handstand (todos los días, sesión aparte) ───────────────────────────
    ('handstand', 1, 'calentamiento-entrada-en-calor-movilidad', array[]::text[],
      'Calentamiento: entrada en calor y movilidad', 'Movilidad', '1', '5:00', 'time', '', null::int,
      '', array[]::text[], array['Peso corporal'], 'Calentamiento',
      'Correr o comba para entrar en calor; luego movilidad articular, 20 s por articulación.'),
    ('handstand', 2, 'retraccion-protraccion-escapular-flexion', array[]::text[],
      'Retracción-protracción escapular en flexión (calentamiento)', 'Movilidad', '2', '10', 'reps', '', null,
      'Hombros', array['Pecho','Core'], array['Peso corporal'], 'Calentamiento',
      'En posición de flexión con brazos rectos: junta y separa las escápulas sin doblar los codos.'),
    ('handstand', 3, 'handstand-pared-empuje-escapular', array['parada-de-manos-en-pared'],
      'Handstand en pared empujando escápulas (calentamiento)', 'Isométrico', '1', '15s', 'time', '', null,
      'Hombros', array['Tríceps','Core'], array['Peso corporal','Pared'], 'Empuje vertical',
      '10-15 s. Empuja el suelo: escápulas arriba, hombros a las orejas.'),
    ('handstand', 4, 'parada-de-manos-libre', array['parada-de-manos-libre'],
      'Parada de manos libre', 'Isométrico', '4', '30s', 'time', '', null,
      'Hombros', array['Tríceps','Core','Antebrazo'], array['Peso corporal'], 'Equilibrio',
      '3-4 aguantes buscando 30-45 s sólidos con buena forma. En tierra (fuera del barco): 5-6 aguantes.'),

    -- ── Empuje (lunes y miércoles) ───────────────────────────────────────────
    ('empuje', 1, 'calentamiento-entrada-en-calor-movilidad', array[]::text[],
      'Calentamiento: entrada en calor y movilidad', 'Movilidad', '1', '5:00', 'time', '', null,
      '', array[]::text[], array['Peso corporal'], 'Calentamiento',
      'Entrada en calor y movilidad articular, 20 s por articulación.'),
    ('empuje', 2, 'retraccion-protraccion-escapular-flexion', array[]::text[],
      'Retracción-protracción escapular en flexión (calentamiento)', 'Movilidad', '2', '10', 'reps', '', null,
      'Hombros', array['Pecho','Core'], array['Peso corporal'], 'Calentamiento',
      'En posición de flexión con brazos rectos: junta y separa las escápulas sin doblar los codos.'),
    ('empuje', 3, 'flexiones-y-pica-calentamiento', array[]::text[],
      'Flexiones normales y de pica (calentamiento)', 'Movilidad', '1', '', 'reps', '', null,
      'Pecho', array['Hombros','Tríceps'], array['Peso corporal'], 'Calentamiento',
      'Algunas flexiones normales y de pica, y carga de peso en las muñecas. Prepara bien el cuerpo.'),
    ('empuje', 4, 'flexiones-de-pino-libre', array[]::text[],
      'Flexiones de pino libre', 'Calistenia', '4', 'max', 'reps', '3-4 min', null,
      'Hombros', array['Tríceps','Core'], array['Peso corporal'], 'Empuje vertical',
      '3-4 intentos. Apunta las reps limpias de cada intento (0 si no sale). Objetivo del bloque: sacarlas.'),
    ('empuje', 5, 'aguante-de-90-grados', array[]::text[],
      'Aguante de 90 grados', 'Isométrico', '2', 'fallo', 'time', '3-4 min', null,
      'Hombros', array['Tríceps','Pecho','Core'], array['Peso corporal'], 'Empuje vertical',
      'Al fallo técnico: cortas cuando se rompe la forma. Apunta los segundos.'),
    ('empuje', 6, 'subida-a-pino-por-fuerza', array[]::text[],
      'Subida a pino por fuerza', 'Calistenia', '2', 'fallo', 'reps', '3-4 min', null,
      'Hombros', array['Core','Tríceps'], array['Peso corporal'], 'Empuje vertical',
      'Press a handstand. Al fallo.'),
    ('empuje', 7, 'flexiones-de-pino-profundas-pared-paralelas', array['flexion-en-parada-de-manos-pared'],
      'Flexiones de pino profundas en pared en paralelas', 'Calistenia', '2', 'fallo', 'reps', '3-4 min', 0,
      'Hombros', array['Tríceps','Core'], array['Peso corporal','Pared','Paralelas'], 'Empuje vertical',
      'Con las manos en paralelas para bajar más allá de la altura de las manos. RIR 0.'),
    ('empuje', 8, 'flexiones-lean-planche', array['lagartija-pseudo-planche'],
      'Flexiones lean planche', 'Calistenia', '2', '6', 'reps', '3-4 min', null,
      'Pecho', array['Hombros','Tríceps','Core'], array['Peso corporal'], 'Empuje horizontal',
      'Hombros por delante de las manos todo el recorrido.'),

    -- ── Tirón (martes y viernes) ─────────────────────────────────────────────
    ('tiron', 1, 'calentamiento-entrada-en-calor-movilidad', array[]::text[],
      'Calentamiento: entrada en calor y movilidad', 'Movilidad', '1', '5:00', 'time', '', null,
      '', array[]::text[], array['Peso corporal'], 'Calentamiento',
      'Correr o comba para entrar en calor; luego movilidad articular, 20 s por articulación.'),
    ('tiron', 2, 'flexiones-antagonistas-calentamiento', array['push-up'],
      'Flexiones (calentamiento)', 'Movilidad', '1', '8', 'reps', '', null,
      'Pecho', array['Tríceps','Hombros'], array['Peso corporal'], 'Calentamiento',
      'Para calentar los músculos antagonistas.'),
    ('tiron', 3, 'retracciones-escapulares-colgado-calentamiento', array['dominada-escapular'],
      'Retracciones escapulares colgado (calentamiento)', 'Movilidad', '1', '', 'reps', '', null,
      'Espalda', array['Hombros'], array['Peso corporal','Barra fija'], 'Calentamiento',
      'Colgado de la barra, brazos rectos: baja y junta las escápulas.'),
    ('tiron', 4, 'dominadas-calentamiento', array['dominadas-pronas'],
      'Dominadas (calentamiento)', 'Movilidad', '1', '', 'reps', '', null,
      'Espalda', array['Bíceps'], array['Peso corporal','Barra fija'], 'Calentamiento',
      'Alguna dominada suave. Prepara bien el cuerpo.'),
    ('tiron', 5, 'aguante-front-lever', array[]::text[],
      'Aguante front lever', 'Isométrico', '1', '', 'time', '3-4 min', null,
      'Espalda', array['Core','Hombros','Bíceps'], array['Peso corporal','Barra fija'], 'Jalón horizontal',
      'Una serie al 80 % de tu máximo: si tu mejor aguante son 10 s, aguanta 8 s. Apunta los segundos y la variante.'),
    ('tiron', 6, 'front-press-negativa-aguante', array['elevaciones-a-front-lever'],
      'Front press + negativa + aguante', 'Calistenia', '2', 'fallo', 'reps', '3-4 min', null,
      'Espalda', array['Core','Hombros'], array['Peso corporal','Barra fija'], 'Jalón vertical',
      'En la misma serie: presses al fallo, luego una negativa lenta y termina con un aguante al fallo.'),
    ('tiron', 7, 'half-press-negativa', array[]::text[],
      'Half press + negativa', 'Calistenia', '2', 'fallo', 'reps', '3-4 min', null,
      'Espalda', array['Core','Hombros'], array['Peso corporal','Barra fija'], 'Jalón vertical',
      'Medio recorrido del press y negativa controlada. Al fallo.'),
    ('tiron', 8, 'touch-tuck-advanced', array[]::text[],
      'Touch tuck advanced', 'Calistenia', '2', '6-8', 'reps', '3-4 min', null,
      'Espalda', array['Core','Bíceps'], array['Peso corporal','Barra fija','Banda elástica'], 'Jalón vertical',
      '6-8 reps. Con goma si hace falta.'),
    ('tiron', 9, 'dominadas-tuck-advanced-front', array[]::text[],
      'Dominadas tuck advanced de front', 'Calistenia', '2', '6', 'reps', '3-4 min', null,
      'Espalda', array['Bíceps','Core'], array['Peso corporal','Barra fija'], 'Jalón vertical',
      'Dominadas manteniendo la posición de front lever tuck avanzado.')
  ) as v(rutina, ord, clave, catalogo, nombre, tipo, series, reps, reps_type, descanso, rir,
         mg, secundarios, equipo, patron, nota);

  -- Empuje ½ (sábado): los mismos ejercicios, la mitad de las series (mínimo 1).
  insert into m1_ex
  select 'empuje-medio', ord, clave, catalogo, nombre, tipo,
         case when ord <= 3 then series else greatest(1, series::int / 2)::text end,
         reps, reps_type, descanso, rir, mg, secundarios, equipo, patron,
         case when clave = 'flexiones-de-pino-libre'
              then '2 intentos. Apunta las reps limpias de cada intento (0 si no sale).'
              else nota end
  from m1_ex where rutina = 'empuje';

  -- ── 3. Las rutinas ─────────────────────────────────────────────────────────
  for r in
    select * from (values
      ('handstand',    'Handstand'),
      ('empuje',       'Empuje'),
      ('empuje-medio', 'Empuje ½'),
      ('tiron',        'Tirón')
    ) as t(rutina, nombre)
  loop
    insert into public.boards (id, name, color, exercises, owner_id, updated_at)
    select md5('calistenia-m1:' || v_user || ':' || r.rutina)::uuid,
           r.nombre, v_color,
           jsonb_agg(x.ex order by x.ord), v_user, now()
    from (
      select e.ord,
             jsonb_build_object(
               'id',                    md5('calistenia-m1:' || v_user || ':' || r.rutina || ':' || e.clave)::uuid,
               'catalogId',             coalesce(c.id::text, ''),
               'name',                  e.nombre,
               'canonicalName',         e.nombre,
               'exerciseKey',           coalesce(c.slug, e.clave),
               'exerciseType',          e.tipo,
               'sets',                  e.series,
               'reps',                  e.reps,
               'repsType',              e.reps_type,
               'rest',                  e.descanso,
               'restNext',              e.descanso,
               'targetRir',             e.rir,
               'supersetGroup',         '',
               'block',                 '',
               'isSuperset',            false,
               'muscleGroup',           e.mg,  -- '' en el calentamiento general: no suma fatiga
               'secondaryMuscleGroups', to_jsonb(e.secundarios),
               'muscles',               jsonb_build_object('primary', nullif(e.mg, ''), 'secondary', to_jsonb(e.secundarios)),
               'equipment',             to_jsonb(e.equipo),
               'movementPattern',       e.patron,
               'difficulty',            coalesce(c.difficulty, case when e.tipo = 'Movilidad' then 'basico' else 'avanzado' end),
               'note',                  e.nota,
               'description',           e.nota,
               'video',                 coalesce(c.video_url, ''),
               'videoTitle',            coalesce(c.name, ''),
               'videos',                case when coalesce(c.video_url, '') <> ''
                                             then jsonb_build_array(jsonb_build_object('url', c.video_url, 'title', c.name))
                                             else '[]'::jsonb end
             ) as ex
      from m1_ex e
      left join lateral (
        select ec.id, ec.slug, ec.name, ec.difficulty, ec.video_url
        from public.exercise_catalog ec
        where ec.slug = any(e.catalogo) and ec.is_active
        order by array_position(e.catalogo, ec.slug)
        limit 1
      ) c on true
      where e.rutina = r.rutina
    ) x
    on conflict (id) do update
      set name = excluded.name,
          color = excluded.color,
          exercises = excluded.exercises,
          updated_at = excluded.updated_at;

    raise notice 'Rutina «%» lista.', r.nombre;
  end loop;

  select string_agg(distinct e.nombre, ', ') into v_missing
  from m1_ex e
  where cardinality(e.catalogo) > 0
    and not exists (select 1 from public.exercise_catalog ec
                    where ec.slug = any(e.catalogo) and ec.is_active);
  if v_missing is not null then
    raise notice 'Se esperaba ficha en el catálogo y no la hay (van sin video): %', v_missing;
  end if;

  -- ── 4. El programa (inactivo) ──────────────────────────────────────────────
  insert into public.coaching_programs (id, user_id, name, notes, is_active, created_by, weeks)
  values (v_program, v_user, 'Calistenia M1',
          'Algecalistenia, planificación M1. Handstand todos los días como sesión aparte; jueves pierna (fuera de este programa); domingo descanso.',
          false, v_user, 4)
  on conflict (id) do update
    set name = excluded.name, notes = excluded.notes, updated_at = now();

  delete from public.coaching_program_days where program_id = v_program;

  insert into public.coaching_program_days (program_id, dow, week_index, board_id, board_name, board_color)
  select v_program, d.dow, 0, md5('calistenia-m1:' || v_user || ':' || d.rutina)::uuid, d.nombre, v_color
  from (values
    (0, 'empuje',       'Empuje'),
    (1, 'tiron',        'Tirón'),
    (2, 'empuje',       'Empuje'),
    (4, 'tiron',        'Tirón'),
    (5, 'empuje-medio', 'Empuje ½')
  ) as d(dow, rutina, nombre);

  raise notice 'Programa «Calistenia M1» guardado SIN activar: actívalo desde Entrenar cuando quieras.';
end $$;

commit;
