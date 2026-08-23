-- Semana de descarga de Joseph, 24–30 de agosto de 2026. NO es una migración de esquema:
-- es una carga de datos de una sola vez. Se corre igual en el SQL Editor y es idempotente
-- (volver a correrla deja el mismo resultado, no duplica nada).
--
-- Por qué la descarga entra como semana propia y no como "la rutina normal con menos series":
-- cambian los ejercicios, no solo las cargas. El lunes desaparecen RDL y leg curl para dejar
-- las piernas frescas al martes; el jueves se conserva lo específico y se van casi todos los
-- accesorios. Eso no se representa bajando un porcentaje: son rutinas distintas.
--
-- Las cuatro rutinas se crean con weekday = NULL A PROPÓSITO. Si llevaran día de la semana,
-- `skandi_ensure_week` (migración 080) las estamparía en TODAS las semanas futuras y la
-- descarga se volvería permanente. Se referencian directo desde los días del calendario.
--
-- Los días quedan con source='manual' e is_edited=true: eso los congela frente a la plantilla,
-- así que cuando cargues el programa nuevo dentro de dos semanas, esta semana no se toca.

-- ── Resolución de ejercicios ────────────────────────────────────────────────
-- Una función auxiliar temporal: busca por nombre o english_name, ignorando mayúsculas y
-- guiones, y si no encuentra nada crea el ejercicio con su reparto muscular. El reparto es lo
-- que consume el motor de fatiga, así que un ejercicio sin él mentiría en la figura corporal.

create or replace function pg_temp.ex(
  p_names text[], p_slug text, p_muscles jsonb,
  p_log_mode text default 'reps', p_log_weight boolean default true,
  p_track_quality boolean default false, p_unilateral boolean default false
) returns uuid
language plpgsql as $$
declare
  v_id uuid;
  v_norm text;
begin
  foreach v_norm in array p_names loop
    select id into v_id from public.skandi_exercises
     where lower(replace(replace(name,'-',' '),'  ',' ')) = lower(replace(replace(v_norm,'-',' '),'  ',' '))
        or lower(coalesce(english_name,'')) = lower(v_norm)
        or slug = lower(replace(v_norm,' ','-'))
     limit 1;
    if v_id is not null then return v_id; end if;
  end loop;

  -- Último intento antes de crear: el slug exacto. Sin esto, volver a correr la carga
  -- insertaría de nuevo y el `on conflict` terminaría renombrando un ejercicio que ya era tuyo.
  select id into v_id from public.skandi_exercises where slug = p_slug;
  if v_id is not null then return v_id; end if;

  insert into public.skandi_exercises (slug, name, english_name, category, muscles, log_mode, log_weight, track_quality, unilateral)
  values (p_slug, p_names[1], p_names[1], 'Strength', p_muscles, p_log_mode, p_log_weight, p_track_quality, p_unilateral)
  returning id into v_id;
  raise notice 'Ejercicio creado: % (no existía en tu catálogo)', p_names[1];
  return v_id;
end;
$$;

do $$
declare
  v_uid uuid := (select id from auth.users where email = 'josephdpelayo@gmail.com');
  v_mon date := date '2026-08-24';
  t_lun uuid; t_mar uuid; t_jue uuid; t_vie uuid;

  -- ejercicios
  e_scap uuid; e_fl_half uuid; e_fl_pull uuid; e_fl_neg uuid; e_pullup uuid; e_row uuid; e_curl uuid;
  e_hs_wall uuid; e_hs_free uuid; e_hspu uuid; e_dips uuid; e_bss uuid; e_legcurl uuid;
  e_lat uuid; e_ohtri uuid; e_calf uuid;
  e_mu uuid; e_fl_at uuid; e_fl_row uuid;
  e_plean uuid; e_goblet uuid; e_dbpress uuid; e_pulldown uuid; e_tripush uuid; e_kneeraise uuid;
begin
  if v_uid is null then raise exception 'Ajusta el correo: no encontré el usuario.'; end if;

  -- ── Ejercicios ────────────────────────────────────────────────────────────
  e_scap      := pg_temp.ex(array['Scapular Pull-Up','Dominada escapular'],'scapular-pull-up',
                   '{"Back":70,"Shoulders":20,"Forearms":10}', 'reps', false);
  e_fl_half   := pg_temp.ex(array['Front Lever Half Lay','Front Lever Half'],'front-lever-half-lay',
                   '{"Back":45,"Core":30,"Shoulders":15,"Biceps":10}', 'seconds', false, true);
  e_fl_at     := pg_temp.ex(array['Front Lever Advanced Tuck'],'front-lever-advanced-tuck',
                   '{"Back":45,"Core":30,"Shoulders":15,"Biceps":10}', 'seconds', false, true);
  e_fl_pull   := pg_temp.ex(array['Advanced Tuck Front Lever Raise','Front Lever Raise (Advanced Tuck)','Front Lever Raises'],'front-lever-pull-advanced-tuck',
                   '{"Back":45,"Core":30,"Shoulders":15,"Biceps":10}', 'reps', false, true);
  e_fl_neg    := pg_temp.ex(array['Front Lever Negative (Advanced Tuck)','Front Lever Negative'],'front-lever-negative-advanced-tuck',
                   '{"Back":45,"Core":30,"Shoulders":15,"Biceps":10}', 'reps', false, true);
  e_fl_row    := pg_temp.ex(array['Front Lever Row'],'front-lever-row',
                   '{"Back":50,"Core":25,"Biceps":15,"Shoulders":10}', 'reps', false, true);
  e_pullup    := pg_temp.ex(array['Pull-Up','Dominada'],'pull-up','{"Back":60,"Biceps":25,"Forearms":10,"Core":5}');
  e_row       := pg_temp.ex(array['Chest-Supported Row','Remo apoyado en pecho','Single-Arm Dumbbell Row'],'chest-supported-row',
                   '{"Back":70,"Biceps":20,"Shoulders":10}');
  e_curl      := pg_temp.ex(array['Biceps Curl','Dumbbell Curl','Cable Bicep Curl'],'biceps-curl','{"Biceps":80,"Forearms":20}');
  e_hs_wall   := pg_temp.ex(array['Chest-to-Wall Handstand','Handstand Wall-Facing','Wall Handstand'],'chest-to-wall-handstand',
                   '{"Shoulders":55,"Core":25,"Triceps":15,"Forearms":5}', 'seconds', false, true);
  e_hs_free   := pg_temp.ex(array['Freestanding Handstand','Free Handstand'],'freestanding-handstand',
                   '{"Shoulders":55,"Core":25,"Triceps":15,"Forearms":5}', 'seconds', false, true);
  e_hspu      := pg_temp.ex(array['Chest-to-Wall HSPU','Handstand Push-Up (Wall)','Handstand push up'],'chest-to-wall-hspu',
                   '{"Shoulders":50,"Triceps":35,"Core":10,"Chest":5}', 'reps', false, true);
  e_dips      := pg_temp.ex(array['Dips','Fondos en paralelas','Dip'],'dips','{"Chest":45,"Triceps":40,"Shoulders":15}');
  e_bss       := pg_temp.ex(array['Bulgarian Split Squat','Bulgarian split squat'],'bulgarian-split-squat',
                   '{"Quads":50,"Glutes":35,"Hamstrings":15}', 'reps', true, false, true);
  e_legcurl   := pg_temp.ex(array['Leg Curl','Seated Leg Curl','Lying Leg Curl','Curl femoral sentado'],'leg-curl',
                   '{"Hamstrings":90,"Calves":10}');
  e_lat       := pg_temp.ex(array['Dumbbell Lateral Raise','Lateral Raise','Cable Lateral Raise'],'dumbbell-lateral-raise',
                   '{"Shoulders":90,"Triceps":10}');
  e_ohtri     := pg_temp.ex(array['Overhead Triceps Extension','Rope Triceps Extension'],'overhead-triceps-extension',
                   '{"Triceps":90,"Shoulders":10}');
  e_calf      := pg_temp.ex(array['Standing Calf Raise'],'standing-calf-raise','{"Calves":100}');
  e_mu        := pg_temp.ex(array['Muscle-Up (Bar)','Muscle-Up','Muscle-up en barra'],'muscle-up-bar',
                   '{"Back":40,"Triceps":25,"Chest":15,"Shoulders":15,"Biceps":5}', 'reps', false, true);
  e_plean     := pg_temp.ex(array['Planche Lean'],'planche-lean',
                   '{"Shoulders":50,"Core":25,"Chest":15,"Biceps":10}', 'seconds', false, true);
  e_goblet    := pg_temp.ex(array['Dumbbell Goblet Squat','Sentadilla goblet'],'dumbbell-goblet-squat',
                   '{"Quads":55,"Glutes":30,"Core":15}');
  e_dbpress   := pg_temp.ex(array['Dumbbell Chest Press','Press de pecho con mancuernas'],'dumbbell-chest-press',
                   '{"Chest":60,"Triceps":25,"Shoulders":15}');
  e_pulldown  := pg_temp.ex(array['Cable Lat Pulldown','Lat Pulldown','Jalón al pecho'],'lat-pulldown',
                   '{"Back":65,"Biceps":25,"Shoulders":10}');
  e_tripush   := pg_temp.ex(array['Cable Triceps Pushdown','Triceps Pushdown'],'cable-triceps-pushdown','{"Triceps":100}');
  e_kneeraise := pg_temp.ex(array['Hanging Knee Raise','Elevación de rodillas colgado'],'hanging-knee-raise',
                   '{"Core":85,"Forearms":15}', 'reps', false);

  -- ── Las cuatro rutinas ────────────────────────────────────────────────────
  -- weekday NULL: ver el comentario de arriba. Si llevaran día, la descarga sería para siempre.
  select id into t_lun from public.skandi_templates where user_id=v_uid and name='Descarga · Front Lever A + Pull' limit 1;
  if t_lun is null then
    insert into public.skandi_templates (user_id, name, weekday, is_public, notes)
    values (v_uid, 'Descarga · Front Lever A + Pull', null, false,
    'Semana de descarga 24–30 ago. Calentamiento general 6–8 min antes de empezar. Fuerza a RIR 3, nada de fallo. Skills a RPE técnico 5–6, solo repeticiones limpias. Pesos al 70–80% de lo normal. No progreses peso, palanca, reps ni segundos. En el half hold NO busques tu máximo: paras en 5–7 s con buena posición.')
    returning id into t_lun;
  end if;

  select id into t_mar from public.skandi_templates where user_id=v_uid and name='Descarga · Handstand + Push + Pierna' limit 1;
  if t_mar is null then
    insert into public.skandi_templates (user_id, name, weekday, is_public, notes)
    values (v_uid, 'Descarga · Handstand + Push + Pierna', null, false,
    'Semana de descarga 24–30 ago. Calentamiento de muñeca y hombro 5–6 min. Máximo 10–12 min totales de práctica de handstand: si el tercer intento libre sale excelente, ahí se queda. Fuerza a RIR 3, pesos al 70–80%. Después (idealmente separado unas horas) van los 25 min de Z2.')
    returning id into t_mar;
  end if;

  select id into t_jue from public.skandi_templates where user_id=v_uid and name='Descarga · Front Lever B + Muscle-Up' limit 1;
  if t_jue is null then
    insert into public.skandi_templates (user_id, name, weekday, is_public, notes)
    values (v_uid, 'Descarga · Front Lever B + Muscle-Up', null, false,
    'Semana de descarga 24–30 ago. Gimnasio de calistenia en CDMX, como práctica y no para probarte con equipo nuevo. Calentamiento general y de hombro 7–8 min. Nada de máximos de muscle-up, nada de "a ver cuántos saco", nada de estrenar progresión de front lever porque las barras estén buenas.')
    returning id into t_jue;
  end if;

  select id into t_vie from public.skandi_templates where user_id=v_uid and name='Descarga · Full Body + Planche' limit 1;
  if t_vie is null then
    insert into public.skandi_templates (user_id, name, weekday, is_public, notes)
    values (v_uid, 'Descarga · Full Body + Planche', null, false,
    'Semana de descarga 24–30 ago. Gym del hotel. Debe sentirse casi demasiado fácil: el sábado ya traes carrera + HIIT. Calentamiento general 5–7 min. Nada después: sin cardio extra, sin finisher, sin caminadora "ya que estoy aquí".')
    returning id into t_vie;
  end if;

  delete from public.skandi_template_items where template_id in (t_lun, t_mar, t_jue, t_vie);

  -- ── LUNES 24 · Front Lever A + Pull ───────────────────────────────────────
  insert into public.skandi_template_items (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, target_rir, note) values
    (t_lun, e_scap,    0, 2, '6-8',   60,  4, 'Fácil, solo para despertar la escápula.'),
    (t_lun, e_fl_half, 1, 3, '5-7 s', 165, null, 'RPE técnico 6. Aunque aguantes más, paras en 5–7 s con buena posición.'),
    (t_lun, e_fl_pull, 2, 2, '4',     150, 3, 'Advanced tuck. Puedes ~5 reps apretando: por eso hoy son 4 y dejamos margen.'),
    (t_lun, e_fl_neg,  3, 2, '2-3',   150, null, 'Advanced tuck, descenso 4–5 s. Arriba → bajada lenta → pelvis controlada → codos extendidos → terminar antes de perder la línea.'),
    (t_lun, e_pullup,  4, 2, '5-6',   150, 3, null),
    (t_lun, e_row,     5, 2, '8-10',  120, 3, null),
    (t_lun, e_curl,    6, 1, '10-12', 85,  3, 'Nada de RDL ni leg curl hoy: las piernas quedan frescas para el martes.');

  -- ── MARTES 25 · Handstand + Push + Pierna ─────────────────────────────────
  insert into public.skandi_template_items (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, target_rir, note) values
    (t_mar, e_hs_wall, 0, 2, '30 s',  75,  null, 'RPE 4–5.'),
    (t_mar, e_hs_free, 1, 5, '1 intento', 75, null, 'Solo intentos buenos. Tope de 10–12 min de práctica en total.'),
    (t_mar, e_hspu,    2, 2, '4-5',   165, 3, 'Chest-to-wall.'),
    (t_mar, e_dips,    3, 2, '6-8',   150, 3, null),
    (t_mar, e_bss,     4, 2, '6-8',   120, 3, 'Por pierna.'),
    (t_mar, e_legcurl, 5, 2, '8-10',  90,  3, null),
    (t_mar, e_lat,     6, 2, '10-15', 75,  3, null),
    (t_mar, e_ohtri,   7, 1, '10-12', 75,  3, null),
    (t_mar, e_calf,    8, 2, '10-15', 68,  3, null);

  -- ── JUEVES 27 · Front Lever B + Muscle-Up técnico ─────────────────────────
  insert into public.skandi_template_items (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, target_rir, note) values
    (t_jue, e_mu,      0, 2, '1',     180, null, 'RPE 5–6. Técnico, no máximos.'),
    (t_jue, e_fl_at,   1, 2, '8-10 s',150, null, 'RPE técnico 5–6.'),
    (t_jue, e_fl_row,  2, 2, '4',     150, 3, 'Advanced tuck.'),
    (t_jue, e_scap,    3, 2, '8',     85,  4, 'Fácil.'),
    (t_jue, e_hs_free, 4, 4, '1 intento', 75, null, 'Técnica. Y ahí termina la sesión.');

  -- ── VIERNES 28 · Full Body + Planche ──────────────────────────────────────
  insert into public.skandi_template_items (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, target_rir, note) values
    (t_vie, e_plean,     0, 2, '12-15 s', 120, null, 'RPE técnico 5–6.'),
    (t_vie, e_goblet,    1, 2, '8',     120, 4, null),
    (t_vie, e_dbpress,   2, 2, '8-10',  120, 3, null),
    (t_vie, e_pulldown,  3, 2, '8-10',  120, 3, null),
    (t_vie, e_legcurl,   4, 1, '10-12', 90,  4, null),
    (t_vie, e_lat,       5, 1, '12-15', 75,  3, null),
    (t_vie, e_tripush,   6, 1, '10-12', 75,  3, null),
    (t_vie, e_curl,      7, 1, '10-12', 75,  3, null),
    (t_vie, e_kneeraise, 8, 2, '10-12', 68,  null, 'Controlado.');

  -- ── El calendario: 24 al 30 de agosto ─────────────────────────────────────
  -- Primero se apaga lo que la plantilla había estampado. Se marca 'skipped' y no se borra:
  -- esa lápida es lo que impide que `skandi_ensure_week` lo vuelva a poner al abrir la semana.
  update public.skandi_planned_sessions
     set status = 'skipped', is_edited = true
   where user_id = v_uid
     and day between v_mon and v_mon + 6
     and status = 'planned'
     and session_id is null and activity_id is null;

  -- Y se borra cualquier intento previo de correr ESTA carga, para que sea idempotente.
  delete from public.skandi_planned_sessions
   where user_id = v_uid and day between v_mon and v_mon + 6
     and source = 'manual' and title like 'Descarga%';

  insert into public.skandi_planned_sessions
    (user_id, day, sort_order, discipline, source, is_edited, template_id, title,
     target_duration_min, target_zone, notes)
  values
    (v_uid, v_mon,     0, 'strength', 'manual', true, t_lun, 'Descarga · Front Lever A + Pull', 50, null,
     'Sesión de mayor prioridad de la semana, con bastante menos volumen. Barco.'),
    (v_uid, v_mon + 1, 0, 'strength', 'manual', true, t_mar, 'Descarga · Handstand + Push + Pierna', 55, null,
     'Barco.'),
    (v_uid, v_mon + 1, 1, 'run',      'manual', true, null,  'Descarga · Z2 suave', 25, 2,
     'Min 0–5 muy suave · min 5–22 en Z2 · min 22–25 muy suave. RPE 2–3, talk test positivo. Sin strides, sin progresivo, sin buscar un pace.'),
    (v_uid, v_mon + 2, 0, 'rest',     'manual', true, null,  'Descarga · Descanso / desembarque', null, null,
     'Sin entrenamiento. Camina normal en el desembarque y el aeropuerto; no hay que compensar nada. Este descanso cae entre las dos exposiciones de front lever.'),
    (v_uid, v_mon + 3, 0, 'strength', 'manual', true, t_jue, 'Descarga · Front Lever B + Muscle-Up', 40, null,
     'Gimnasio de calistenia, CDMX. Sin carrera hoy.'),
    (v_uid, v_mon + 4, 0, 'strength', 'manual', true, t_vie, 'Descarga · Full Body + Planche', 40, null,
     'Gym del hotel. Debe sentirse casi demasiado fácil.'),
    (v_uid, v_mon + 5, 0, 'run',      'manual', true, null,  'Descarga · Carrera del convivio', 35, 2,
     'Z1–Z2 la mayor parte. RPE 2–3, se puede conversar. Si el grupo acelera, no lo conviertas en tempo: en unas horas ya viene la intensidad. Sin strides.'),
    (v_uid, v_mon + 5, 1, 'hiit',     'manual', true, null,  'Descarga · HIIT del convivio', 30, null,
     'RPE máximo 7–8. Sin fallo muscular y sin sprint máximo. Es prácticamente el único estímulo intenso de la semana. El baño de hielo no cuenta como volumen.'),
    (v_uid, v_mon + 6, 0, 'rest',     'manual', true, null,  'Descarga · Descanso completo', null, null,
     'Sin fondo Z2 esta semana: el sábado ya concentró impacto e intensidad. Caminata normal y 10–15 min de movilidad si te apetece. Nada estructurado.');

  raise notice 'Listo: 4 rutinas de descarga y 9 días cargados del % al %.', v_mon, v_mon + 6;
end;
$$;

drop function if exists pg_temp.ex(text[], text, jsonb, text, boolean, boolean, boolean);
