-- Migra el catálogo de ejercicios de Skandi Fit al catálogo de HABIT.
--
-- REQUIERE la migración 037 corrida antes que esta. 037 crea exercise_catalog y
-- siembra los 72 ejercicios base de HABIT; hasta que se corra, la app usa la
-- copia hardcodeada EXERCISE_CATALOG_FALLBACK de app.html y esta migración
-- falla con "relation public.exercise_catalog does not exist".
-- El orden importa: 037 pisa aliases con los suyos, así que correrla DESPUÉS
-- de esta borraría los alias en inglés que deja este import.
--
-- Las dos apps comparten el mismo proyecto de Supabase, así que esto es una
-- copia dentro de la misma base: skandi_exercises -> exercise_catalog. Lo que
-- vale de ese catálogo no son los nombres (Skandi está en inglés) sino los GIFs
-- de técnica, el desglose de músculos y las instrucciones, y sobre todo toda la
-- línea de calistenia (front lever, planche, muscle-up) que HABIT no tenía.
--
-- Los nombres se traducen al español porque HABIT es una app en español, y el
-- nombre en inglés queda como alias para que el buscador encuentre los dos.
-- De los 98 ejercicios, 32 ya existían en HABIT con otro nombre: esos NO se
-- duplican, se enriquecen con el GIF y las instrucciones de Skandi sin pisar
-- nada de lo que HABIT ya tuviera.

with tr(sk_slug, es_name, es_slug) as (values
    ('advanced-tuck-planche','Plancha tuck avanzada','plancha-tuck-avanzada'),
    ('archer-pull-up','Dominada arquero','dominada-arquero'),
    ('archer-push-up','Lagartija arquero','lagartija-arquero'),
    ('back-lever-full','Back lever completo','back-lever-completo'),
    ('back-lever-straddle','Back lever straddle','back-lever-straddle'),
    ('back-lever-tuck','Back lever tuck','back-lever-tuck'),
    ('barbell-bench-press','Bench press barra','bench-press-barra'),
    ('barbell-squat','Sentadilla barra','sentadilla-barra'),
    ('bosu-ball-squat','Sentadilla en bosu','sentadilla-en-bosu'),
    ('broad-jump','Salto horizontal','salto-horizontal'),
    ('cable-bicep-curl','Curl polea baja','curl-polea-baja'),
    ('cable-crossover-fly','Cruce de poleas','cruce-de-poleas'),
    ('cable-face-pull','Face pull','face-pull'),
    ('cable-lat-pulldown','Jalón al pecho','jalon-al-pecho'),
    ('cable-lateral-raise','Elevaciones laterales polea','elevaciones-laterales-polea'),
    ('cable-pull-through','Pull-through en polea','pull-through-en-polea'),
    ('cable-seated-row','Remo sentado polea','remo-sentado-polea'),
    ('cable-skull-crushes','Rompecráneos en polea','rompecraneos-en-polea'),
    ('cable-standing-chest-press','Press de pecho de pie en polea','press-de-pecho-de-pie-en-polea'),
    ('cable-triceps-pushdown','Pushdown barra','pushdown-barra'),
    ('cable-woodchopper','Leñador en polea','lenador-en-polea'),
    ('chest-to-bar-pull-up','Dominada al pecho','dominada-al-pecho'),
    ('cmj-vertical-jump','Salto vertical (CMJ)','salto-vertical-cmj'),
    ('decline-sit-up','Abdominal en banco declinado','abdominal-en-banco-declinado'),
    ('dips','Fondos en paralelas','fondos-en-paralelas'),
    ('dragon-flag','Dragon flag','dragon-flag'),
    ('dumbbell-bench-press','Bench press mancuernas','bench-press-mancuernas'),
    ('dumbbell-curl','Curl bíceps mancuernas','curl-biceps-mancuernas'),
    ('dumbbell-front-raise','Elevaciones frontales','elevaciones-frontales'),
    ('dumbbell-goblet-squat','Sentadilla goblet','sentadilla-goblet'),
    ('dumbbell-hammer-curl','Curl martillo','curl-martillo'),
    ('dumbbell-incline-bench-press','Bench press inclinado mancuernas','bench-press-inclinado-mancuernas'),
    ('dumbbell-lateral-raise','Elevaciones laterales mancuernas','elevaciones-laterales-mancuernas'),
    ('dumbbell-shoulder-press','Press militar mancuernas','press-militar-mancuernas'),
    ('dumbbell-single-arm-row','Remo con mancuerna','remo-con-mancuerna'),
    ('dumbbell-walking-lunge','Zancadas caminando','zancadas-caminando'),
    ('explosive-pull-up','Dominada explosiva al pecho','dominada-explosiva-al-pecho'),
    ('false-grip-pull-up','Dominada con agarre falso','dominada-con-agarre-falso'),
    ('freestanding-handstand','Parada de manos libre','parada-de-manos-libre'),
    ('frog-stand','Parada de rana','parada-de-rana'),
    ('front-lever-advanced-tuck','Front lever tuck avanzado','front-lever-tuck-avanzado'),
    ('front-lever-full','Front lever completo','front-lever-completo'),
    ('front-lever-raises','Elevaciones a front lever','elevaciones-a-front-lever'),
    ('front-lever-row','Remo en front lever','remo-en-front-lever'),
    ('front-lever-straddle','Front lever straddle','front-lever-straddle'),
    ('front-lever-tuck','Front lever tuck','front-lever-tuck'),
    ('full-planche','Plancha completa','plancha-completa'),
    ('handstand-push-up-wall','Flexión en parada de manos (pared)','flexion-en-parada-de-manos-pared'),
    ('hanging-leg-raise','Elevación de piernas colgado','elevacion-de-piernas-colgado'),
    ('heel-pulls-toe-pulls','Heel pulls / toe pulls','heel-pulls-toe-pulls'),
    ('hip-thrust','Hip thrust','hip-thrust'),
    ('hollow-body-hold','Hollow hold','hollow-hold'),
    ('human-flag','Bandera humana','bandera-humana'),
    ('incline-dumbbell-curl','Curl inclinado con mancuernas','curl-inclinado-con-mancuernas'),
    ('jump-squat','Sentadilla con salto','sentadilla-con-salto'),
    ('l-sit','L-sit','l-sit'),
    ('leg-extension-machine','Extensión de cuádriceps','extension-de-cuadriceps'),
    ('muscle-up-bar','Muscle-up en barra','muscle-up-en-barra'),
    ('muscle-up-negative','Muscle-up negativo','muscle-up-negativo'),
    ('nordic-curl','Curl nórdico','curl-nordico'),
    ('one-arm-front-lever','Front lever a un brazo','front-lever-a-un-brazo'),
    ('one-arm-handstand','Parada de manos a un brazo','parada-de-manos-a-un-brazo'),
    ('one-leg-front-lever','Front lever a una pierna','front-lever-a-una-pierna'),
    ('pike-push-up','Lagartija pike','lagartija-pike'),
    ('pistol-squat','Sentadilla pistol','sentadilla-pistol'),
    ('planche-lean','Planche lean','planche-lean'),
    ('plank','Plank','plank'),
    ('pogo-jumps','Saltos pogo','saltos-pogo'),
    ('pseudo-planche-push-up','Lagartija pseudo planche','lagartija-pseudo-planche'),
    ('push-up','Push up','push-up'),
    ('push-up-bosu-ball','Lagartija en bosu','lagartija-en-bosu'),
    ('reverse-fly','Pájaros mancuernas','pajaros-mancuernas'),
    ('reverse-lunge-step-up','Zancada atrás / step-up','zancada-atras-step-up'),
    ('romanian-deadlift','Peso muerto rumano','peso-muerto-rumano'),
    ('rope-triceps-extension','Extensión tríceps cuerda','extension-triceps-cuerda'),
    ('scapular-pull-up','Dominada escapular','dominada-escapular'),
    ('seated-calf-raise','Elevación de pantorrilla sentado','elevacion-de-pantorrilla-sentado'),
    ('seated-leg-curl-machine','Curl femoral sentado','curl-femoral-sentado'),
    ('shoulder-press','Press militar barra','press-militar-barra'),
    ('shrimp-squat','Sentadilla shrimp','sentadilla-shrimp'),
    ('skin-the-cat','Skin the cat','skin-the-cat'),
    ('smith-machine-bench-press','Bench press en multipower','bench-press-en-multipower'),
    ('smith-machine-bent-over-row','Remo inclinado en multipower','remo-inclinado-en-multipower'),
    ('smith-machine-bulgarian-split-squat','Bulgarian split squat en multipower','bulgarian-split-squat-en-multipower'),
    ('smith-machine-incline-bench-press','Press inclinado en multipower','press-inclinado-en-multipower'),
    ('smith-machine-shoulder-press','Press militar en multipower','press-militar-en-multipower'),
    ('smith-machine-squat','Sentadilla en multipower','sentadilla-en-multipower'),
    ('standing-calf-raise','Elevación de pantorrilla parado','elevacion-de-pantorrilla-parado'),
    ('straddle-planche','Plancha straddle','plancha-straddle'),
    ('straight-arm-pulldown','Jalón con brazos rectos','jalon-con-brazos-rectos'),
    ('supinated-pull-ups','Dominadas supinas','dominadas-supinas'),
    ('t-bar-row','Remo T bar','remo-t-bar'),
    ('tuck-planche','Plancha tuck','plancha-tuck'),
    ('typewriter-pull-up','Dominada typewriter','dominada-typewriter'),
    ('v-up','V-up','v-up'),
    ('wall-handstand','Parada de manos en pared','parada-de-manos-en-pared'),
    ('weighted-pull-up','Dominada con lastre','dominada-con-lastre'),
    ('wide-grip-pull-ups','Dominada agarre abierto','dominada-agarre-abierto')
),
musc(en, es) as (values
    ('Chest','Pecho'),
    ('Back','Espalda'),
    ('Shoulders','Hombros'),
    ('Biceps','Bíceps'),
    ('Triceps','Tríceps'),
    ('Forearms','Antebrazo'),
    ('Core','Core'),
    ('Glutes','Glúteos'),
    ('Quads','Piernas'),
    ('Hamstrings','Piernas'),
    ('Calves','Piernas'),
    ('Hip Flexors','Core')
),
eq(en, es) as (values
    ('Bodyweight','Peso corporal'),
    ('Pull-up bar','Barra de dominadas'),
    ('Dumbbells','Mancuernas'),
    ('Bench','Banco'),
    ('Barbell','Barra'),
    ('Cable Machine','Polea'),
    ('Cable','Polea'),
    ('Smith Machine','Multipower'),
    ('Parallettes','Paralelas'),
    ('Parallel bars','Paralelas'),
    ('Rope','Cuerda'),
    ('Wall','Pared'),
    ('Rack','Rack'),
    ('Bosu Ball','Bosu'),
    ('Machine','Máquina'),
    ('Straight Bar','Barra recta'),
    ('V Bar','Barra V'),
    ('EZ Bar','Barra Z'),
    ('Leg Extension Machine','Máquina de cuádriceps'),
    ('Leg Curl Machine','Máquina de femoral'),
    ('Decline Bench','Banco declinado'),
    ('Pole','Poste'),
    ('Weight belt','Cinturón de lastre'),
    ('Box','Cajón')
),
src as (
  select
    s.*,
    tr.es_name,
    tr.es_slug,
    -- El músculo principal es el de mayor porcentaje en el jsonb de Skandi
    -- ('{"Chest":60,"Triceps":25,...}'); el resto quedan como secundarios.
    (select x.key
       from jsonb_each_text(s.muscles) x
      order by x.value::numeric desc, x.key
      limit 1) as primary_en
  from public.skandi_exercises s
  join tr on tr.sk_slug = s.slug
),
prepared as (
  select
    src.es_name as name,
    src.es_slug as slug,
    case
      when src.log_mode = 'seconds' then 'Isométrico'
      when src.equipment && array['Bodyweight','Pull-up bar','Parallettes','Parallel bars','Wall','Pole']::text[]
        then 'Calistenia'
      else 'Fuerza'
    end as category,
    coalesce((select m.es from musc m where m.en = src.primary_en), 'Full Body') as primary_muscle,
    coalesce((
      select array_agg(distinct m.es)
        from jsonb_each_text(src.muscles) x
        join musc m on m.en = x.key
       where x.key <> src.primary_en
         and m.es <> coalesce((select m2.es from musc m2 where m2.en = src.primary_en), '')
    ), '{}'::text[]) as secondary_muscles,
    coalesce((
      select array_agg(distinct coalesce(e.es, u))
        from unnest(src.equipment) u
        left join eq e on e.en = u
    ), '{}'::text[]) as equipment,
    case when src.log_mode = 'seconds' then 'time' else 'reps' end as default_tracking,
    -- Todo lo que pertenece a una línea de progresión (front lever, planche,
    -- handstand, muscle-up) entra marcado como avanzado.
    case when src.progression_group is not null then 'avanzado' else 'basico' end as difficulty,
    nullif(array_to_string(src.instructions, E'\n'), '') as instructions,
    nullif(src.media_url, '') as video_url,
    array_remove(array[lower(src.english_name), src.slug], null) as aliases
  from src
)
insert into public.exercise_catalog
  (name, slug, category, primary_muscle, secondary_muscles, equipment,
   default_tracking, difficulty, instructions, video_url, aliases, is_active)
select
  name, slug, category, primary_muscle, secondary_muscles, equipment,
  default_tracking, difficulty, instructions, video_url, aliases, true
from prepared
on conflict (slug) do update set
  -- Enriquecer, nunca pisar: si el ejercicio de HABIT ya tenía video o
  -- instrucciones propias, esas mandan.
  video_url    = coalesce(nullif(exercise_catalog.video_url, ''),    excluded.video_url),
  instructions = coalesce(nullif(exercise_catalog.instructions, ''), excluded.instructions),
  -- aliases es not null: array_agg sobre un conjunto vacío devuelve NULL, así
  -- que el coalesce evita romper la fila si ninguno de los dos traía alias.
  aliases      = coalesce((select array_agg(distinct a)
                             from unnest(exercise_catalog.aliases || excluded.aliases) a), '{}'::text[]),
  updated_at   = now();
