-- Skandi Fit — el lastre SUMA al peso corporal, no lo sustituye.
--
-- Fase 0 de docs/PREVENCION_LESIONES_HOMBRO_CODO.md, y es un arreglo, no una función nueva.
-- `setStimulusUnits()` en skandi-recovery.js calculaba la carga de una serie como
-- `weight_kg > 0 ? weight_kg : 70`: el lastre entraba EN LUGAR del peso corporal. O sea que
-- unos fondos con +15 kg × 8 valían 15·8/500 = 0.24 unidades de estímulo y los mismos fondos
-- sin lastre valían 70·8/500 = 1.12. Ponerse el cinturón dividía la carga calculada entre 4.7,
-- justo en los ejercicios donde el tendón es el que paga la cuenta. Eso contaminaba la figura
-- de recuperación muscular y el cociente agudo:crónico por articulación de
-- skandi-joint-load.js — las dos cosas que deberían avisar de una sobrecarga en hombro o codo.
--
-- La carga que importa es "peso corporal + lastre". Esta columna es la fracción del peso
-- corporal que mueve el ejercicio, y el motor la usa como
-- `peso_corporal × bodyweight_share + lastre`.
--
-- ── Por qué solo se puebla una familia ──────────────────────────────────────
-- Vale 1.00 donde el cuerpo ENTERO es la carga porque cuelga de los brazos o se sostiene sobre
-- las manos: dominadas de cualquier agarre, fondos, muscle-up, levers, planches, handstands,
-- L-sit, human flag. Ahí el 1.00 es un hecho del movimiento, no una estimación.
--
-- Todo lo demás se queda NULL a propósito, y NULL significa "calcula como siempre":
--   * Una flexión mueve ~dos tercios del peso, una sentadilla a peso corporal algo más, un
--     dragon flag descarga parte del cuerpo en el banco. Poner esos porcentajes es inventar un
--     número por ejercicio que nadie puede verificar — exactamente lo que este repo ya se
--     prohibió al repartir la carga articular (ver la nota larga en skandi-joint-load.js).
--   * HABIT carga el mismo skandi-recovery.js y su `exercise_catalog` no tiene esta columna,
--     así que su figura muscular no se mueve ni un punto.
-- La consecuencia conocida: una flexión o una sentadilla lastrada siguen contando de menos.
-- Se arregla cuando haya una fracción defendible por patrón, no antes.

alter table public.skandi_exercises
  add column if not exists bodyweight_share numeric(3,2)
    check (bodyweight_share is null or bodyweight_share between 0 and 1);

comment on column public.skandi_exercises.bodyweight_share is
  'Fracción del peso corporal que mueve el ejercicio. 1.00 = el cuerpo entero cuelga o se sostiene sobre los brazos (dominada, fondos, muscle-up, levers, handstand). NULL = la carga es solo la externa y el motor calcula como antes.';

-- ── Siembra, con verificación de slugs ──────────────────────────────────────
-- La lista es literal y el bloque avisa por NOTICE de cualquier slug que no exista en el
-- catálogo, en vez de dejar que una coincidencia difusa etiquete el ejercicio equivocado.
do $$
declare
  v_slugs text[] := array[
    -- Tracción vertical y cualquier cosa que cuelgue de la barra
    'weighted-pull-up', 'wide-grip-pull-ups', 'supinated-pull-ups', 'chest-to-bar-pull-up',
    'archer-pull-up', 'typewriter-pull-up', 'explosive-pull-up', 'false-grip-pull-up',
    'scapular-pull-up', 'muscle-up-bar', 'muscle-up-negative', 'inverted-hang', 'skin-the-cat',
    'hanging-leg-raise', 'front-lever-row',
    -- Empuje vertical sobre las paralelas
    'dips',
    -- Front lever: escalones y remos/raises de la línea
    'front-lever-tuck', 'front-lever-advanced-tuck', 'front-lever-straddle',
    'front-lever-half-lay', 'front-lever-full', 'one-arm-front-lever', 'one-leg-front-lever',
    'front-lever-raises', 'tuck-front-lever-raise', 'advanced-tuck-front-lever-raise',
    'straddle-front-lever-raise',
    -- Back lever
    'back-lever-tuck', 'back-lever-advanced-tuck', 'back-lever-straddle', 'back-lever-full',
    'one-leg-back-lever',
    -- Planche y equilibrios sobre las manos (planche-lean y pseudo-planche-push-up quedan
    -- fuera: los pies siguen en el suelo, así que no es el cuerpo entero)
    'tuck-planche', 'advanced-tuck-planche', 'straddle-planche', 'full-planche', 'frog-stand',
    -- Handstand y HSPU
    'freestanding-handstand', 'wall-handstand', 'chest-to-wall-handstand', 'one-arm-handstand',
    'handstand-weight-shift', 'heel-pulls-toe-pulls', 'freestanding-hspu',
    'handstand-push-up-wall', 'deficit-wall-hspu', 'wall-hspu-negative',
    -- Otros donde el cuerpo entero se sostiene con los brazos
    'l-sit', 'human-flag'
  ];
  v_missing text[];
  v_updated integer;
begin
  update public.skandi_exercises
     set bodyweight_share = 1.00
   where slug = any(v_slugs);
  get diagnostics v_updated = row_count;

  select array_agg(s order by s) into v_missing
    from unnest(v_slugs) s
   where not exists (select 1 from public.skandi_exercises e where e.slug = s);

  raise notice 'bodyweight_share = 1.00 en % ejercicios de %', v_updated, array_length(v_slugs, 1);
  if v_missing is not null then
    raise notice 'Slugs de la lista que NO existen en el catálogo (revisar antes de darlo por bueno): %',
      array_to_string(v_missing, ', ');
  end if;
end $$;
