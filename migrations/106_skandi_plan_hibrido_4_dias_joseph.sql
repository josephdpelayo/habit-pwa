-- Skandi Fit: carga el "Plan Híbrido 4 Días" de Joseph (PDF, versión final agosto 2026) como
-- su semana fija: cuatro rutinas de fuerza (skandi_templates + skandi_template_items) y tres
-- sesiones de carrera (skandi_activity_templates), cada una anclada a un weekday.
--
-- Es una semana que se repite igual, no un ciclo de varias semanas con fases -- por eso esta
-- migración NO crea fila en skandi_programs. skandi_ensure_week ya sabe estampar el calendario
-- leyendo weekday directamente cuando no hay programa activo con start_date, y ese es
-- precisamente el único camino que hoy funciona: la migración 104 reescribió el cuerpo de
-- skandi_ensure_week a partir de una copia vieja (anterior a la 102/103) y sin querer borró toda
-- la resolución por skandi_programs/skandi_program_days/skandi_program_weeks -- ver
-- docs/CAPAS_ENTRENAR_SKANDI.md. Construir este plan como programa fechado lo dejaría visible en
-- la hoja de "Programa" pero SIN estampar nada en el calendario real. Weekday es la vía segura.
--
-- weekday: 0=lunes … 6=domingo (DOW_BY_LANG / todayDow() en skandi.html).
--
-- Front Lever: el catálogo ordena progression_rank con straddle (5) antes que half-lay (6),
-- pero Joseph entrena straddle como la variante más difícil de las dos -- se respeta su nivel
-- real, no el rank del catálogo, para elegir qué exercise_id va en el día "difícil" (Día 1) y
-- cuál en el "fácil" (Día 3).
--
-- Reemplaza la semana completa de Joseph: cualquier rutina o plantilla de carrera que hoy tenga
-- weekday asignado se queda en su biblioteca (no se borra ninguna fila) pero deja de ser "el plan
-- de esta semana", igual que hicieron las migraciones 050/060/086.
--
-- No corre dos veces: si "Día 1 · Front Lever A + Pull + Posterior" ya existe para este usuario,
-- aborta con una excepción en vez de duplicar rutinas.

do $$
declare
  v_uid  uuid := (select id from auth.users where email = 'josephdpelayo@gmail.com');
  v_tpl1 uuid;
  v_tpl2 uuid;
  v_tpl3 uuid;
  v_tpl4 uuid;
  v_required_slugs text[] := array[
    'front-lever-straddle','straddle-front-lever-raise','weighted-pull-up','cable-seated-row',
    'cable-lat-pulldown','reverse-fly','dumbbell-curl','seated-leg-curl-machine','romanian-deadlift',
    'standing-calf-raise','chest-to-wall-handstand','freestanding-handstand','barbell-squat',
    'smith-machine-bulgarian-split-squat','leg-extension-machine','handstand-push-up-wall',
    'dumbbell-incline-bench-press','dips','dumbbell-lateral-raise','rope-triceps-extension',
    'muscle-up-bar','front-lever-half-lay','front-lever-row','chest-to-bar-pull-up','hip-thrust',
    'reverse-lunge-step-up','incline-dumbbell-curl','dumbbell-hammer-curl','cable-triceps-pushdown',
    'cable-face-pull','hollow-body-hold','planche-lean','tuck-planche','push-up',
    'straight-arm-pulldown','hanging-leg-raise'
  ];
  v_missing text[];
begin
  if v_uid is null then
    raise exception 'Ajusta el correo: no encontré el usuario josephdpelayo@gmail.com en auth.users';
  end if;

  if exists (
    select 1 from public.skandi_templates
    where user_id = v_uid and name = 'Día 1 · Front Lever A + Pull + Posterior'
  ) then
    raise exception 'Ya existe "Día 1 · Front Lever A + Pull + Posterior" para este usuario -- esta migración ya se corrió. Bórrala manualmente primero si de verdad quieres recargarla.';
  end if;

  select array_agg(s) into v_missing
  from unnest(v_required_slugs) s
  where not exists (select 1 from public.skandi_exercises e where e.slug = s);

  if v_missing is not null then
    raise exception 'Faltan estos slugs en skandi_exercises, corrige el catálogo o esta migración antes de reintentar: %', array_to_string(v_missing, ', ');
  end if;

  -- Libera toda la semana: este plan define los 7 días, no solo los 4 de fuerza.
  update public.skandi_templates
     set weekday = null, updated_at = now()
   where user_id = v_uid and weekday is not null;

  update public.skandi_activity_templates
     set weekday = null
   where user_id = v_uid and weekday is not null;

  -- =========================================================================================
  -- Día 1 · Front Lever A + Pull + Posterior (lunes)
  -- =========================================================================================
  insert into public.skandi_templates (user_id, name, notes, weekday)
  values (
    v_uid,
    'Día 1 · Front Lever A + Pull + Posterior',
    'Prioridad: fuerza específica de Front Lever. El trabajo de pierna posterior se integra al final con pocas series productivas. Front Lever no se lleva al fallo muscular: el límite es técnico. Los ejercicios convencionales de dorsal complementan al FL; no se busca duplicar volumen innecesariamente. El RDL queda deliberadamente corto: la pierna tendrá más exposiciones durante la semana.',
    0
  )
  returning id into v_tpl1;

  insert into public.skandi_template_items
    (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, target_rir, note)
  values
    (v_tpl1, (select id from public.skandi_exercises where slug = 'front-lever-straddle'),        1, 4, '6-10s', 180, null, 'Front Lever hold principal (straddle). Progresión más difícil con línea limpia; cortar al perder posición.'),
    (v_tpl1, (select id from public.skandi_exercises where slug = 'straddle-front-lever-raise'),  2, 3, '3-6',   150, 2,    'Front Lever raises / excéntricos. RIR técnico 1-2; control escapular.'),
    (v_tpl1, (select id from public.skandi_exercises where slug = 'weighted-pull-up'),             3, 3, '4-7',   150, 1,    'Dominada lastrada. RIR 1; fuerza de tirón.'),
    (v_tpl1, (select id from public.skandi_exercises where slug = 'cable-seated-row'),              4, 2, '8-12',  90,  1,    'Remo en cable sentado / pecho apoyado. RIR 0-1; espalda alta.'),
    (v_tpl1, (select id from public.skandi_exercises where slug = 'cable-lat-pulldown'),           5, 2, '8-12',  90,  1,    'Jalón unilateral / dominada neutra. RIR 0-1; dorsal. Usa polea sencilla o agarre neutro según equipo disponible.'),
    (v_tpl1, (select id from public.skandi_exercises where slug = 'reverse-fly'),                  6, 2, '10-15', 90,  1,    'Reverse fly / peck deck inverso. RIR 0-1; deltoide posterior.'),
    (v_tpl1, (select id from public.skandi_exercises where slug = 'dumbbell-curl'),                7, 2, '8-12',  90,  1,    'Curl de bíceps. RIR 0-1.'),
    (v_tpl1, (select id from public.skandi_exercises where slug = 'seated-leg-curl-machine'),      8, 2, '10-15', 90,  1,    'Leg curl. RIR 0-1; isquios.'),
    (v_tpl1, (select id from public.skandi_exercises where slug = 'romanian-deadlift'),            9, 2, '6-10',  90,  2,    'RDL. RIR 2; posterior sin generar fatiga excesiva.'),
    (v_tpl1, (select id from public.skandi_exercises where slug = 'standing-calf-raise'),          10, 2, '10-15', 60, 1,    'Gemelos de pie. RIR 0-1.');

  -- =========================================================================================
  -- Día 2 · Push + Handstand + Cuádriceps (martes) + carrera Z2 fácil
  -- =========================================================================================
  insert into public.skandi_templates (user_id, name, notes, weekday)
  values (
    v_uid,
    'Día 2 · Push + Handstand + Cuádriceps',
    'Prioridad: Handstand fresco al inicio; después empuje e hipertrofia de cuádriceps. Carrera Z2 fácil más tarde -- idealmente separar fuerza y carrera por varias horas. Las 6 series de cuádriceps son un estímulo serio, pero no convierten el día en leg day. En Handstand, más intentos no significa mejor práctica: detener cuando caiga claramente la calidad.',
    1
  )
  returning id into v_tpl2;

  insert into public.skandi_template_items
    (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, target_rir, note)
  values
    (v_tpl2, (select id from public.skandi_exercises where slug = 'chest-to-wall-handstand'),        1, 3, '30-45s',      180, null, 'Handstand wall-facing. Control de línea y respiración.'),
    (v_tpl2, (select id from public.skandi_exercises where slug = 'freestanding-handstand'),          2, 1, '5-8 intentos', 180, null, 'Handstand libre. Intentos de alta calidad; descanso amplio.'),
    (v_tpl2, (select id from public.skandi_exercises where slug = 'barbell-squat'),                   3, 2, '6-10',        180, 2,    'Sentadilla / Smith squat. RIR 1-2.'),
    (v_tpl2, (select id from public.skandi_exercises where slug = 'smith-machine-bulgarian-split-squat'), 4, 2, '8-12',    150, 1,    'Bulgarian split squat (Smith). RIR 1; por pierna.'),
    (v_tpl2, (select id from public.skandi_exercises where slug = 'leg-extension-machine'),           5, 2, '10-15',       90,  1,    'Extensión de cuádriceps. RIR 0-1.'),
    (v_tpl2, (select id from public.skandi_exercises where slug = 'handstand-push-up-wall'),          6, 3, '5-8',         180, 2,    'HSPU progression (rank 4 de la escalera: pared, rango completo). Regresión: pike push-up (rank 1) si el rango completo no sale limpio. RIR 1-2; fuerza vertical.'),
    (v_tpl2, (select id from public.skandi_exercises where slug = 'dumbbell-incline-bench-press'),    7, 2, '6-10',        150, 1,    'Press inclinado. RIR 0-1.'),
    (v_tpl2, (select id from public.skandi_exercises where slug = 'dips'),                            8, 2, '6-10',        150, 1,    'Fondos lastrados. RIR 1.'),
    (v_tpl2, (select id from public.skandi_exercises where slug = 'dumbbell-lateral-raise'),          9, 3, '10-15',       90,  1,    'Elevaciones laterales. RIR 0-1 / fallo mecánico opcional.'),
    (v_tpl2, (select id from public.skandi_exercises where slug = 'rope-triceps-extension'),           10, 2, '10-15',     90,  1,    'Tríceps overhead en cuerda. RIR 0-1.');

  insert into public.skandi_activity_templates
    (user_id, activity_type, weekday, target_duration_min, target_zone, notes)
  values (
    v_uid, 'running', 1, 35, 2,
    'Carrera fácil (30-40 min), Z2 estable, ritmo conversacional. Base aeróbica, recuperación y técnica. Idealmente separar varias horas de la sesión de fuerza del Día 2.'
  );

  -- =========================================================================================
  -- Día 3 · Front Lever B + Muscle-Up + Brazos/Deltoides (jueves) + carrera de calidad
  -- =========================================================================================
  insert into public.skandi_templates (user_id, name, notes, weekday)
  values (
    v_uid,
    'Día 3 · Front Lever B + Muscle-Up + Brazos/Deltoides',
    'Prioridad: segunda exposición de FL, de menor intensidad y mayor control. Muscle-Up se trabaja como skill de calidad. Este día no debe convertirse en otro Día 1: la carga del FL baja y la calidad sube. Carrera de calidad más tarde: 35-45 min totales con solo 8-15 min realmente intensos. Si la calidad de FL cae durante varias semanas, el primer recorte se hace en accesorios, no en las dos exposiciones de FL.',
    3
  )
  returning id into v_tpl3;

  insert into public.skandi_template_items
    (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, target_rir, note)
  values
    (v_tpl3, (select id from public.skandi_exercises where slug = 'muscle-up-bar'),                 1, 3, '1-3',   180, null, 'Muscle-Up técnico. Repeticiones limpias; sin grind.'),
    (v_tpl3, (select id from public.skandi_exercises where slug = 'front-lever-half-lay'),          2, 3, '8-12s', 180, null, 'Front Lever hold - progresión más fácil (half-lay). Más volumen técnico que el Día 1.'),
    (v_tpl3, (select id from public.skandi_exercises where slug = 'front-lever-row'),                3, 3, '4-8',   150, 2,    'Front Lever row progression. RIR técnico 1-2.'),
    (v_tpl3, (select id from public.skandi_exercises where slug = 'chest-to-bar-pull-up'),          4, 2, '3-5',   150, null, 'Pull-up explosiva pecho-barra. Velocidad; parar si cae explosividad.'),
    (v_tpl3, (select id from public.skandi_exercises where slug = 'hip-thrust'),                    5, 2, '8-12',  150, 1,    'Hip thrust. RIR 1; glúteo integrado.'),
    (v_tpl3, (select id from public.skandi_exercises where slug = 'reverse-lunge-step-up'),         6, 2, '8-12',  150, 1,    'Reverse lunge / step-up. RIR 1; estímulo unilateral de pierna.'),
    (v_tpl3, (select id from public.skandi_exercises where slug = 'dumbbell-lateral-raise'),        7, 3, '10-15', 90,  1,    'Elevaciones laterales. RIR 0-1.'),
    (v_tpl3, (select id from public.skandi_exercises where slug = 'incline-dumbbell-curl'),         8, 2, '8-12',  90,  1,    'Curl inclinado / Bayesian. RIR 0-1. Cambia a curl en polea baja si buscas variante Bayesian.'),
    (v_tpl3, (select id from public.skandi_exercises where slug = 'dumbbell-hammer-curl'),          9, 2, '10-14', 90,  1,    'Curl martillo. RIR 0-1; braquial/antebrazo.'),
    (v_tpl3, (select id from public.skandi_exercises where slug = 'cable-triceps-pushdown'),        10, 2, '8-12', 90,  1,    'Extensión de tríceps en cable. RIR 0-1.'),
    (v_tpl3, (select id from public.skandi_exercises where slug = 'cable-face-pull'),               11, 2, '12-15', 90, 1,    'Face pull / rear delt. RIR 0-1.'),
    (v_tpl3, (select id from public.skandi_exercises where slug = 'hollow-body-hold'),              12, 3, '20-40s', 60, null, 'Hollow / core específico FL. Tensión corporal y retroversión pélvica. El PDF no da un tiempo exacto; ajusta a lo que sostengas con técnica limpia.');

  insert into public.skandi_activity_templates
    (user_id, activity_type, weekday, target_duration_min, target_zone, notes)
  values (
    v_uid, 'running', 3, 40, null,
    'Carrera de calidad: 35-45 min totales con solo 8-15 min realmente intensos (resto calentamiento/enfriamiento Z2). Umbral/velocidad sin volumen excesivo. Rotar cada semana: 1) Fartlek 6×1 min fuerte / recuperación suave · 2) Tempo 2×8 min controlado · 3) Intervalos 5×2 min fuerte / recuperación suficiente · 4) Descarga: sin intensidad, Z2 suave. Después de la sesión de fuerza del Día 3, con horas de separación si es posible.'
  );

  -- =========================================================================================
  -- Día 4 · Full Body + Planche (viernes)
  -- =========================================================================================
  insert into public.skandi_templates (user_id, name, notes, weekday)
  values (
    v_uid,
    'Día 4 · Full Body + Planche',
    'Función: completar volumen semanal. Planche va primero; después posterior, cuádriceps y torso con dosis pequeñas. El Full Body existe para rellenar huecos, no para competir con los días de prioridad. Debe dejarte funcional para recuperar el sábado y correr el fondo el domingo. Si hay fatiga acumulada de carrera, reduce primero una serie de los accesorios de pierna de este día.',
    4
  )
  returning id into v_tpl4;

  insert into public.skandi_template_items
    (template_id, exercise_id, sort_order, target_sets, target_reps, target_rest_sec, target_rir, note)
  values
    (v_tpl4, (select id from public.skandi_exercises where slug = 'planche-lean'),               1, 3, '12-20s', 180, null, 'Escápulas protraídas; técnica.'),
    (v_tpl4, (select id from public.skandi_exercises where slug = 'tuck-planche'),                2, 2, '6-10s',  180, null, 'Tuck planche. Sin fallo; posición sólida.'),
    (v_tpl4, (select id from public.skandi_exercises where slug = 'seated-leg-curl-machine'),     3, 2, '8-15',   90,  1,    'Leg curl. RIR 0-1.'),
    (v_tpl4, (select id from public.skandi_exercises where slug = 'leg-extension-machine'),       4, 2, '10-15',  90,  1,    'Extensión de cuádriceps. RIR 0-1.'),
    (v_tpl4, (select id from public.skandi_exercises where slug = 'hip-thrust'),                  5, 2, '8-12',   150, 1,    'Hip thrust / extensión de cadera. RIR 1.'),
    (v_tpl4, (select id from public.skandi_exercises where slug = 'push-up'),                     6, 2, '8-12',   150, 1,    'Press / push-up lastrado. Lastrado o en anillas, RIR 0-1.'),
    (v_tpl4, (select id from public.skandi_exercises where slug = 'straight-arm-pulldown'),       7, 2, '10-15',  90,  1,    'Pullover / straight-arm pulldown. RIR 0-1; dorsal en longitud.'),
    (v_tpl4, (select id from public.skandi_exercises where slug = 'dumbbell-lateral-raise'),      8, 2, '12-20',  90,  1,    'Elevaciones laterales. RIR 0-1.'),
    (v_tpl4, (select id from public.skandi_exercises where slug = 'standing-calf-raise'),         9, 3, '10-20',  60,  1,    'Gemelos. RIR 0-1.'),
    (v_tpl4, (select id from public.skandi_exercises where slug = 'hanging-leg-raise'),           10, 3, '8-15',  60,  null, 'Abdomen. Control, no velocidad.');

  -- =========================================================================================
  -- Domingo · Fondo Z2 (única sesión del día; sin fuerza)
  -- =========================================================================================
  insert into public.skandi_activity_templates
    (user_id, activity_type, weekday, target_duration_min, target_zone, notes)
  values (
    v_uid, 'running', 6, 50, 2,
    'Fondo (45-60 min), Z2 controlada. Aumentar tolerancia y base. Único fondo de la semana -- la progresión de carrera debe ser conservadora, la mayoría del tiempo semanal en Z2.'
  );

end $$;
