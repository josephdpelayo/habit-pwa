-- Rutina básica de push para Emmanuel Pelayo, agendada para HOY.
--
-- Es una siembra de datos, no un cambio de esquema: crea (o reescribe) un
-- pizarrón del gym con los siete ejercicios de empuje que pidió el coach, se lo
-- asigna a Emmanuel para que le aparezca en Entrenar → Mis rutinas, y le deja
-- el entreno de hoy en su calendario.
--
-- Tres decisiones que conviene no perder:
--
--   · El pizarrón es del gym (owner_id null), no una rutina personal suya: así
--     se puede volver a asignar a otro socio sin duplicarla, y el socio no la
--     puede editar por accidente. NO se marca is_starter (migración 116): eso
--     la pondría en la lista de TODOS los socios, y esto es para uno.
--
--   · La fila del calendario nace con generated_from_base = false y
--     base_template_dow = null — igual que un entreno agregado a mano desde la
--     app. Eso es justo lo que la protege: ensure_coaching_week_from_template
--     (migración 115) solo borra lo que él mismo estampó desde la plantilla.
--     created_by apunta al admin, que es lo que hace que la app etiquete el día
--     como «de tu coach» (isCoachSet en app.html).
--
--   · «Hoy» se resuelve en America/Mazatlan y no con current_date, que es UTC:
--     corriendo esto después de las cinco de la tarde, el servidor ya cree que
--     es mañana y el entreno caería en el día equivocado.
--
-- El id del pizarrón va fijo para que volver a correr la migración actualice
-- ESE pizarrón y no cree otro ni toque ninguno ajeno.

begin;

do $$
declare
  v_board  constant uuid := '29630dd2-8c81-4e8a-9a95-77740316bd41';
  v_name   constant text := 'Push básico';
  v_color  constant text := '#2563eb';
  v_user       uuid;
  v_user_name  text;
  v_coach      uuid;
  v_coach_name text;
  v_n          integer;
  v_ds         date := (now() at time zone 'America/Mazatlan')::date;
  v_exercises  jsonb;
  v_missing    text;
  v_otros      text;
begin
  -- ── 1. El socio ────────────────────────────────────────────────────────────
  -- Por nombre, porque es lo único que hay en profiles. Si hay cero o más de
  -- uno, esto se para: inyectarle una rutina al Emmanuel equivocado es peor
  -- que no inyectar nada.
  select count(*) into v_n
  from public.profiles
  where name ilike '%emmanuel%' and name ilike '%pelayo%';

  if v_n = 0 then
    raise exception 'Ningún perfil se llama «Emmanuel Pelayo». Revisa cómo está escrito su nombre en profiles.';
  elsif v_n > 1 then
    raise exception 'Hay % perfiles que coinciden con «Emmanuel Pelayo»: %. Sustituye la búsqueda por el id correcto.',
      v_n,
      (select string_agg(name || ' [' || id || ']', ', ')
         from public.profiles
        where name ilike '%emmanuel%' and name ilike '%pelayo%');
  end if;

  select id, name into v_user, v_user_name
  from public.profiles
  where name ilike '%emmanuel%' and name ilike '%pelayo%';

  raise notice 'Socio: % [%]', v_user_name, v_user;

  -- ── 2. Quién se la manda ───────────────────────────────────────────────────
  -- created_by distinto del socio es lo que hace que el día se vea como puesto
  -- por el coach y no como algo que él mismo se agendó.
  select id, name into v_coach, v_coach_name
  from public.profiles
  where role = 'admin'
  order by created_at
  limit 1;

  if v_coach is null then
    raise notice 'No hay ningún perfil admin: el entreno quedará sin created_by y la app no lo marcará como "de tu coach".';
  else
    raise notice 'Se agenda a nombre de: % [%]', v_coach_name, v_coach;
  end if;

  -- ── 3. Los ejercicios ──────────────────────────────────────────────────────
  -- El shape es el mismo que escribe el constructor de rutinas de app.html
  -- (addExerciseSb): series y reps son texto, repsType 'reps', descanso
  -- normalizado como '90s', y targetRir null = sin objetivo de RIR.
  select jsonb_agg(
           jsonb_build_object(
             'id',                    uuid_generate_v4(),
             'catalogId',             '',
             'name',                  p.nombre,
             'canonicalName',         p.nombre,
             'exerciseKey',           p.slug,
             'exerciseType',          'Fuerza',
             'sets',                  p.series,
             'reps',                  p.reps,
             'repsType',              'reps',
             'rest',                  p.descanso,
             'restNext',              p.descanso,
             'targetRir',             null::integer,
             'supersetGroup',         '',
             'block',                 '',
             'isSuperset',            false,
             'muscleGroup',           p.mg,
             'secondaryMuscleGroups', to_jsonb(p.secundarios),
             'muscles',               jsonb_build_object('primary', p.mg, 'secondary', to_jsonb(p.secundarios)),
             'equipment',             to_jsonb(p.equipo),
             'movementPattern',       p.patron,
             'difficulty',            'basico',
             'note',                  p.nota,
             'description',           p.nota,
             'video',                 '',
             'videoTitle',            '',
             'videos',                '[]'::jsonb
           ) order by p.ord)
    into v_exercises
    from (values
      (1, 'bench-press-mancuernas',           'Bench press mancuernas',           '3', '8',  '90s', 'Pecho',   array['Tríceps','Hombros'], array['Mancuernas','Banco'],          'Empuje horizontal', 'Baja controlado hasta el pecho, codos a unos 45°.'),
      (2, 'bench-press-inclinado-mancuernas', 'Bench press inclinado mancuernas', '3', '8',  '90s', 'Pecho',   array['Hombros','Tríceps'], array['Mancuernas','Banco inclinado'],'Empuje inclinado',  'Banco a 30°. No dejes que los codos se vayan atrás.'),
      (3, 'fondos-en-paralelas',              'Fondos en paralelas',              '2', '6',  '90s', 'Tríceps', array['Pecho','Hombros'],   array['Peso corporal','Paralelas'],    'Empuje vertical',   'Pecho ligeramente al frente. Baja solo hasta donde el hombro aguante sin abrirse.'),
      (4, 'cross-over-polea-alta',            'Cross over polea alta',            '3', '10', '60s', 'Pecho',   array['Hombros'],           array['Polea'],                        'Aducción',          'Codo casi fijo: el movimiento es del hombro, no del brazo.'),
      (5, 'elevaciones-laterales-mancuernas', 'Elevaciones laterales mancuernas', '2', '10', '45s', 'Hombros', array[]::text[],            array['Mancuernas'],                   'Abducción',         'Sube hasta la altura del hombro, sin impulso de cadera.'),
      (6, 'pushdown-barra',                   'Pushdown barra',                   '2', '10', '45s', 'Tríceps', array[]::text[],            array['Polea','Barra'],                'Extensión codo',    'Codos pegados al costado: lo único que se mueve es el antebrazo.'),
      (7, 'extension-triceps-cuerda',         'Extensión tríceps cuerda',         '2', '10', '45s', 'Tríceps', array[]::text[],            array['Polea'],                        'Extensión codo',    'Abre la cuerda al final del recorrido.')
    ) as p(ord, slug, nombre, series, reps, descanso, mg, secundarios, equipo, patron, nota);

  -- Si el catálogo está cargado (migración 037 / 071), cada ejercicio se
  -- enriquece con su ficha: id de catálogo, equipo, patrón y video. Sin
  -- catálogo la rutina funciona igual, solo sin ficha de técnica.
  if to_regclass('public.exercise_catalog') is not null then
    select jsonb_agg(
             case when c.id is null then t.x
             else t.x || jsonb_build_object(
               'catalogId',       c.id::text,
               'name',            c.name,
               'canonicalName',   c.name,
               'exerciseType',    coalesce(c.category, 'Fuerza'),
               'muscleGroup',     coalesce(c.primary_muscle, t.x->>'muscleGroup'),
               'muscles',         jsonb_build_object(
                                    'primary',   coalesce(c.primary_muscle, t.x->>'muscleGroup'),
                                    'secondary', t.x->'secondaryMuscleGroups'),
               'equipment',       to_jsonb(coalesce(c.equipment, '{}'::text[])),
               'movementPattern', coalesce(c.movement_pattern, t.x->>'movementPattern'),
               'difficulty',      coalesce(c.difficulty, 'basico'),
               'video',           coalesce(c.video_url, ''),
               'videos',          case when coalesce(c.video_url, '') <> ''
                                       then jsonb_build_array(jsonb_build_object('url', c.video_url, 'title', c.name))
                                       else '[]'::jsonb end)
             end order by t.ord)
      into v_exercises
      from jsonb_array_elements(v_exercises) with ordinality as t(x, ord)
      left join public.exercise_catalog c on c.slug = t.x->>'exerciseKey';
  end if;

  select string_agg(x->>'exerciseKey', ', ')
    into v_missing
    from jsonb_array_elements(v_exercises) x
   where coalesce(x->>'catalogId', '') = '';

  if v_missing is not null then
    raise notice 'Sin ficha en exercise_catalog (la rutina funciona, pero esos ejercicios van sin video ni indicaciones): %', v_missing;
  end if;

  -- ── 4. El pizarrón ─────────────────────────────────────────────────────────
  insert into public.boards (id, name, color, exercises, owner_id)
  values (v_board, v_name, v_color, v_exercises, null)
  on conflict (id) do update
    set name = excluded.name,
        color = excluded.color,
        exercises = excluded.exercises;

  select string_agg(name || ' [' || id || ']', ', ') into v_otros
  from public.boards
  where id <> v_board and owner_id is null and lower(name) = lower(v_name);

  if v_otros is not null then
    raise notice 'Ojo: ya había otro pizarrón del gym llamado «%»: %. Revisa cuál quieres conservar.', v_name, v_otros;
  end if;

  -- ── 5. Que le aparezca en Mis rutinas ──────────────────────────────────────
  insert into public.board_assignments (board_id, user_id)
  values (v_board, v_user)
  on conflict do nothing;

  -- ── 6. El entreno de hoy ───────────────────────────────────────────────────
  if exists (select 1 from public.coaching_schedule
              where user_id = v_user and ds = v_ds and board_id = v_board) then
    raise notice 'Ya tenía «%» agendada el % — no se duplica.', v_name, v_ds;
  else
    insert into public.coaching_schedule (
      user_id, board_id, board_name, board_color, ds,
      status, created_by, generated_from_base, base_template_dow)
    values (v_user, v_board, v_name, v_color, v_ds,
      'scheduled', v_coach, false, null);
    raise notice 'Agendado «%» para el % (hora de Mazatlán).', v_name, v_ds;
  end if;

  select string_agg(board_name || ' (' || status || ')', ', ') into v_otros
  from public.coaching_schedule
  where user_id = v_user and ds = v_ds and board_id is distinct from v_board;

  if v_otros is not null then
    raise notice 'Hoy además tiene: %. Un día admite varios entrenos (migración 034); si sobra alguno, bórralo desde el panel del coach.', v_otros;
  end if;
end $$;

commit;
