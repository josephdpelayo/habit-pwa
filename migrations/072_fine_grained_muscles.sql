-- Granularidad muscular fina: separar 'Piernas' en cuádriceps, femorales y
-- pantorrillas, y guardar el reparto porcentual por ejercicio.
--
-- La figura corporal (body-figure.js, compartida con Skandi Fit) pinta once
-- regiones y el motor de recuperación (skandi-recovery.js) tiene una ventana de
-- descanso distinta para cada una. Con 'Piernas' como un solo grupo, una
-- sentadilla y una elevación de pantorrilla fatigaban lo mismo y la pierna
-- entera se pintaba de un color. Esta migración le da a HABIT la misma
-- granularidad que ya tenía Skandi.
--
-- muscle_split guarda el reparto en los nombres del motor (Chest, Quads, ...)
-- con porcentajes que suman ~100, igual que skandi_exercises.muscles.

alter table public.exercise_catalog
  add column if not exists muscle_split jsonb not null default '{}'::jsonb;

-- ── 1. Los de HABIT que estaban etiquetados 'Piernas' ────────────────────────
update public.exercise_catalog c
set primary_muscle    = r.primary_muscle,
    secondary_muscles = r.secondary_muscles,
    updated_at        = now()
from (values
    ('sentadilla-barra','Cuádriceps',array['Glúteos','Femorales','Core','Espalda']::text[]),
    ('sentadilla-frontal','Cuádriceps',array['Glúteos','Core','Espalda']::text[]),
    ('prensa-de-pierna','Cuádriceps',array['Glúteos','Femorales']::text[]),
    ('extension-de-cuadriceps','Cuádriceps',array[]::text[]),
    ('curl-femoral-acostado','Femorales',array['Glúteos','Pantorrillas']::text[]),
    ('curl-femoral-sentado','Femorales',array['Glúteos']::text[]),
    ('hip-thrust','Glúteos',array['Femorales','Core']::text[]),
    ('peso-muerto-rumano','Femorales',array['Glúteos','Espalda','Core']::text[]),
    ('zancadas-caminando','Cuádriceps',array['Glúteos','Femorales','Core']::text[]),
    ('bulgarian-split-squat','Cuádriceps',array['Glúteos','Femorales','Core']::text[]),
    ('elevacion-de-pantorrilla-parado','Pantorrillas',array[]::text[]),
    ('box-jump','Cuádriceps',array['Glúteos','Pantorrillas','Core']::text[]),
    ('kettlebell-swing','Glúteos',array['Femorales','Espalda','Core']::text[])
) as r(slug, primary_muscle, secondary_muscles)
where c.slug = r.slug;

-- ── 2. 'Piernas' que quede suelto en secundarios ─────────────────────────────
-- Un solo grupo se convierte en dos: sin saber más del ejercicio, cuádriceps y
-- femorales es el reparto honesto para un secundario genérico de pierna.
update public.exercise_catalog c
set secondary_muscles = coalesce((
      select array_agg(distinct m)
        from (
          select unnest(array_remove(c.secondary_muscles, 'Piernas')) as m
          union
          select unnest(array['Cuádriceps','Femorales'])
        ) t
       where m <> c.primary_muscle
    ), '{}'::text[]),
    updated_at = now()
where 'Piernas' = any(c.secondary_muscles);

update public.exercise_catalog
set primary_muscle = 'Cuádriceps', updated_at = now()
where primary_muscle = 'Piernas';

-- ── 3. Recuperar el reparto fino de los que vinieron de Skandi ───────────────
-- La migración 071 dejó el slug de Skandi dentro de aliases, así que se puede
-- volver a la fila original, que sí trae los porcentajes por músculo.
with musc(en, es) as (values
    ('Chest','Pecho'), ('Back','Espalda'), ('Shoulders','Hombros'),
    ('Biceps','Bíceps'), ('Triceps','Tríceps'), ('Forearms','Antebrazo'),
    ('Core','Core'), ('Glutes','Glúteos'), ('Quads','Cuádriceps'),
    ('Hamstrings','Femorales'), ('Calves','Pantorrillas')
),
src as (
  select c.id,
         s.muscles,
         (select x.key from jsonb_each_text(s.muscles) x
           order by x.value::numeric desc, x.key limit 1) as primary_en
    from public.exercise_catalog c
    join public.skandi_exercises s on s.slug = any(c.aliases)
   where s.muscles <> '{}'::jsonb
)
update public.exercise_catalog c
set muscle_split   = src.muscles,
    primary_muscle = coalesce((select es from musc where en = src.primary_en), c.primary_muscle),
    secondary_muscles = coalesce((
      select array_agg(distinct m.es)
        from jsonb_each_text(src.muscles) x
        join musc m on m.en = x.key
       where x.key <> src.primary_en
    ), '{}'::text[]),
    updated_at = now()
from src
where c.id = src.id;

-- ── 4. Para el resto, derivar el reparto de principal + secundarios ──────────
-- Sin porcentajes en la fuente, el principal se lleva 60 y los secundarios se
-- reparten el 40 restante en partes iguales. Es una suposición explícita, no un
-- dato medido, pero mantiene proporcionada la fatiga entre un ejercicio con un
-- solo músculo y uno compuesto.
with musc(es, en) as (values
    ('Pecho','Chest'), ('Espalda','Back'), ('Hombros','Shoulders'),
    ('Bíceps','Biceps'), ('Tríceps','Triceps'), ('Antebrazo','Forearms'),
    ('Core','Core'), ('Glúteos','Glutes'), ('Cuádriceps','Quads'),
    ('Femorales','Hamstrings'), ('Pantorrillas','Calves')
),
calc as (
  select c.id,
         (select en from musc where es = c.primary_muscle) as primary_en,
         coalesce((select array_agg(m.en) from unnest(c.secondary_muscles) sm
                     join musc m on m.es = sm
                    where m.en is distinct from (select en from musc where es = c.primary_muscle)),
                  '{}'::text[]) as secondary_en
    from public.exercise_catalog c
   where c.muscle_split = '{}'::jsonb
)
update public.exercise_catalog c
set muscle_split = (
      select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)
        from (
          select calc.primary_en as k, 60 as v
          union all
          select s, (40 / greatest(array_length(calc.secondary_en, 1), 1))
            from unnest(calc.secondary_en) s
        ) parts
       where k is not null
    ),
    updated_at = now()
from calc
where c.id = calc.id and calc.primary_en is not null;
