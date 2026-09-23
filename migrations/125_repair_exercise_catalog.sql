-- Reparar el catálogo de ejercicios: fichas pisadas, ejercicios sin músculo y
-- duplicados que el coach guardó con otro nombre.
--
-- Revisando exercise_catalog ejercicio por ejercicio (23 sep 2026) salieron
-- tres problemas:
--
-- 1. FICHAS PISADAS. "HIP THRUST", "PESO MUERTO RUMANO", "CURL MARTILLO",
--    "BENCH PRESS INCLINADO MANCUERNAS" y "REMADORA" no eran duplicados: eran
--    las fichas originales de la 037. Al escribir el coach el mismo nombre en
--    una rutina, saveExerciseCatalogFromBoardExercise() hacía un upsert por
--    slug que les ponía el nombre de la rutina y les vaciaba el músculo, los
--    secundarios, el equipo, los alias y las instrucciones (arreglado en la app
--    en 85128ce: ya no reescribe una ficha que existe). Se salvó muscle_split,
--    que el upsert no tocaba, y el video, que es el de YouTube del gym.
--    Aquí se restaura lo que falte, sin pisar nada que tenga valor: primero
--    desde muscle_split (como la 072), luego desde los datos de la 037 (con el
--    reparto de pierna de la 072, no el 'Piernas' original), y luego desde
--    skandi_exercises con la misma traducción de la 071. El nombre original
--    vuelve solo si el actual es el mismo con otras mayúsculas o acentos; el
--    de la rutina queda como alias.
--
-- 2. SIN MÚSCULO. Los ejercicios que el coach escribió a mano entraron sin
--    grupo muscular: no salían en la ficha del músculo y, sobre todo, no
--    cargaban ningún músculo en el motor de recuperación. Se les asigna el
--    suyo (solo si siguen vacíos).
--
-- 3. DUPLICADOS con otro nombre que la identidad de nombres de la app no
--    junta: errores de dedo ("EXTENCION", "CRUADRICEP") y sinónimos ("ELEVACION
--    DE TALON" = elevación de pantorrilla, "PLANCHA ESTATICA" = plank). Se
--    fusionan con merge_exercise_catalog() (123/124) hacia la ficha del
--    catálogo: queda su nombre, gana el mejor video (el YouTube del coach), y
--    las rutinas pasan a apuntar a ella sin cambiar el nombre que el coach
--    escribió. Solo los claros; los dudosos (¿"PRESS MILITAR" es con barra o
--    con mancuernas?) se quedan como ejercicio propio, con su músculo, para
--    decidirlos en Admin → Ejercicios.
--
-- Todo se imprime en los mensajes del SQL Editor.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1a. Principal y secundarios desde muscle_split (lo que sobrevivió al upsert)
-- ─────────────────────────────────────────────────────────────────────────────
with musc(en, es) as (values
    ('Chest','Pecho'), ('Back','Espalda'), ('Shoulders','Hombros'),
    ('Biceps','Bíceps'), ('Triceps','Tríceps'), ('Forearms','Antebrazo'),
    ('Core','Core'), ('Glutes','Glúteos'), ('Quads','Cuádriceps'),
    ('Hamstrings','Femorales'), ('Calves','Pantorrillas')
),
src as (
  select c.id, c.muscle_split,
         (select x.key from jsonb_each_text(c.muscle_split) x
           order by x.value::numeric desc, x.key limit 1) as primary_en
    from public.exercise_catalog c
   where c.is_active
     and nullif(btrim(c.primary_muscle), '') is null
     and c.muscle_split <> '{}'::jsonb
)
update public.exercise_catalog c
   set primary_muscle = (select es from musc where en = src.primary_en),
       secondary_muscles = case when cardinality(c.secondary_muscles) > 0 then c.secondary_muscles else coalesce((
         select array_agg(distinct m.es)
           from jsonb_each_text(src.muscle_split) x
           join musc m on m.en = x.key
          where x.key <> src.primary_en), '{}'::text[]) end,
       updated_at = now()
  from src
 where c.id = src.id
   and exists (select 1 from musc where en = src.primary_en);

-- ─────────────────────────────────────────────────────────────────────────────
-- 1b. Desde los datos de la 037 (con el reparto de pierna de la 072)
-- ─────────────────────────────────────────────────────────────────────────────
with seed(name, slug, category, primary_muscle, secondary_muscles, equipment,
          movement_pattern, default_tracking, difficulty, aliases) as (values
  ('Bench press barra','bench-press-barra','Fuerza','Pecho',array['Tríceps','Hombros']::text[],array['Barra','Banco'],'Empuje horizontal','reps','basico',array['press banca','bench press horizontal barra']),
  ('Bench press mancuernas','bench-press-mancuernas','Fuerza','Pecho',array['Tríceps','Hombros']::text[],array['Mancuernas','Banco'],'Empuje horizontal','reps','basico',array['press pecho mancuernas']),
  ('Bench press inclinado barra','bench-press-inclinado-barra','Fuerza','Pecho',array['Hombros','Tríceps']::text[],array['Barra','Banco inclinado'],'Empuje inclinado','reps','basico',array['press inclinado barra']),
  ('Bench press inclinado mancuernas','bench-press-inclinado-mancuernas','Fuerza','Pecho',array['Hombros','Tríceps']::text[],array['Mancuernas','Banco inclinado'],'Empuje inclinado','reps','basico',array['press inclinado mancuernas']),
  ('Aperturas con mancuernas','aperturas-con-mancuernas','Fuerza','Pecho',array['Hombros']::text[],array['Mancuernas','Banco'],'Aducción','reps','basico',array['fly mancuernas']),
  ('Aperturas en peck deck','aperturas-en-peck-deck','Fuerza','Pecho',array['Hombros']::text[],array['Máquina'],'Aducción','reps','basico',array['pec deck','contractora']),
  ('Cross over polea alta','cross-over-polea-alta','Fuerza','Pecho',array['Hombros']::text[],array['Polea'],'Aducción','reps','basico',array['cruce polea alta']),
  ('Cross over polea baja','cross-over-polea-baja','Fuerza','Pecho',array['Hombros']::text[],array['Polea'],'Aducción','reps','basico',array['cruce polea baja']),
  ('Push up','push-up','Calistenia','Pecho',array['Tríceps','Hombros','Core']::text[],array['Peso corporal'],'Empuje horizontal','reps','basico',array['lagartija','flexion']),
  ('Push up diamante','push-up-diamante','Calistenia','Tríceps',array['Pecho','Hombros','Core']::text[],array['Peso corporal'],'Empuje horizontal','reps','intermedio',array['diamond push up']),
  ('Fondos en paralelas','fondos-en-paralelas','Calistenia','Tríceps',array['Pecho','Hombros']::text[],array['Peso corporal','Paralelas'],'Empuje vertical','reps','intermedio',array['dips']),
  ('Fondos en banca','fondos-en-banca','Calistenia','Tríceps',array['Pecho','Hombros']::text[],array['Banco','Peso corporal'],'Empuje vertical','reps','basico',array['bench dips']),
  ('Press militar barra','press-militar-barra','Fuerza','Hombros',array['Tríceps','Core']::text[],array['Barra'],'Empuje vertical','reps','basico',array['overhead press barra']),
  ('Press militar mancuernas','press-militar-mancuernas','Fuerza','Hombros',array['Tríceps','Core']::text[],array['Mancuernas'],'Empuje vertical','reps','basico',array['shoulder press mancuernas']),
  ('Press Arnold','press-arnold','Fuerza','Hombros',array['Tríceps']::text[],array['Mancuernas'],'Empuje vertical','reps','intermedio',array['arnold press']),
  ('Elevaciones laterales mancuernas','elevaciones-laterales-mancuernas','Fuerza','Hombros',array[]::text[],array['Mancuernas'],'Abducción','reps','basico',array['laterales mancuernas']),
  ('Elevaciones laterales polea','elevaciones-laterales-polea','Fuerza','Hombros',array[]::text[],array['Polea'],'Abducción','reps','basico',array['laterales polea']),
  ('Elevaciones frontales','elevaciones-frontales','Fuerza','Hombros',array['Pecho']::text[],array['Mancuernas'],'Flexión hombro','reps','basico',array['front raises']),
  ('Face pull','face-pull','Fuerza','Hombros',array['Espalda']::text[],array['Polea'],'Jalón','reps','basico',array['jalon rostro']),
  ('Pájaros mancuernas','pajaros-mancuernas','Fuerza','Hombros',array['Espalda']::text[],array['Mancuernas'],'Abducción posterior','reps','basico',array['reverse fly']),
  ('Dominadas pronas','dominadas-pronas','Calistenia','Espalda',array['Bíceps','Core']::text[],array['Peso corporal','Barra fija'],'Jalón vertical','reps','intermedio',array['pull up']),
  ('Dominadas supinas','dominadas-supinas','Calistenia','Bíceps',array['Espalda','Core']::text[],array['Peso corporal','Barra fija'],'Jalón vertical','reps','intermedio',array['chin up']),
  ('Jalón al pecho','jalon-al-pecho','Fuerza','Espalda',array['Bíceps']::text[],array['Polea','Máquina'],'Jalón vertical','reps','basico',array['lat pulldown']),
  ('Remo con barra','remo-con-barra','Fuerza','Espalda',array['Bíceps','Core']::text[],array['Barra'],'Jalón horizontal','reps','basico',array['barbell row']),
  ('Remo con mancuerna','remo-con-mancuerna','Fuerza','Espalda',array['Bíceps']::text[],array['Mancuernas','Banco'],'Jalón horizontal','reps','basico',array['one arm row']),
  ('Remo sentado polea','remo-sentado-polea','Fuerza','Espalda',array['Bíceps']::text[],array['Polea'],'Jalón horizontal','reps','basico',array['seated cable row']),
  ('Remo T bar','remo-t-bar','Fuerza','Espalda',array['Bíceps']::text[],array['Barra','Máquina'],'Jalón horizontal','reps','intermedio',array['t bar row']),
  ('Pullover polea','pullover-polea','Fuerza','Espalda',array['Pecho','Core']::text[],array['Polea'],'Jalón','reps','basico',array['straight arm pulldown']),
  ('Australian row','australian-row','Calistenia','Espalda',array['Bíceps','Core']::text[],array['Peso corporal','Barra fija'],'Jalón horizontal','reps','basico',array['remo invertido']),
  ('Peso muerto convencional','peso-muerto-convencional','Fuerza','Espalda',array['Core','Cuádriceps','Femorales']::text[],array['Barra'],'Bisagra','reps','intermedio',array['deadlift']),
  ('Sentadilla barra','sentadilla-barra','Fuerza','Cuádriceps',array['Glúteos','Femorales','Core','Espalda']::text[],array['Barra'],'Sentadilla','reps','basico',array['back squat']),
  ('Sentadilla frontal','sentadilla-frontal','Fuerza','Cuádriceps',array['Glúteos','Core','Espalda']::text[],array['Barra'],'Sentadilla','reps','intermedio',array['front squat']),
  ('Prensa de pierna','prensa-de-pierna','Fuerza','Cuádriceps',array['Glúteos','Femorales']::text[],array['Máquina'],'Sentadilla','reps','basico',array['leg press']),
  ('Extensión de cuádriceps','extension-de-cuadriceps','Fuerza','Cuádriceps',array[]::text[],array['Máquina'],'Extensión rodilla','reps','basico',array['leg extension']),
  ('Curl femoral acostado','curl-femoral-acostado','Fuerza','Femorales',array['Glúteos','Pantorrillas']::text[],array['Máquina'],'Flexión rodilla','reps','basico',array['leg curl acostado']),
  ('Curl femoral sentado','curl-femoral-sentado','Fuerza','Femorales',array['Glúteos']::text[],array['Máquina'],'Flexión rodilla','reps','basico',array['seated leg curl']),
  ('Hip thrust','hip-thrust','Fuerza','Glúteos',array['Femorales','Core']::text[],array['Barra','Banco'],'Extensión cadera','reps','basico',array['empuje de cadera']),
  ('Peso muerto rumano','peso-muerto-rumano','Fuerza','Femorales',array['Glúteos','Espalda','Core']::text[],array['Barra','Mancuernas'],'Bisagra','reps','basico',array['romanian deadlift']),
  ('Zancadas caminando','zancadas-caminando','Fuerza','Cuádriceps',array['Glúteos','Femorales','Core']::text[],array['Mancuernas','Peso corporal'],'Desplante','reps','basico',array['walking lunges']),
  ('Bulgarian split squat','bulgarian-split-squat','Fuerza','Cuádriceps',array['Glúteos','Femorales','Core']::text[],array['Mancuernas','Banco'],'Desplante','reps','intermedio',array['sentadilla bulgara']),
  ('Elevación de pantorrilla parado','elevacion-de-pantorrilla-parado','Fuerza','Pantorrillas',array[]::text[],array['Máquina','Mancuernas'],'Pantorrilla','reps','basico',array['standing calf raise']),
  ('Curl bíceps barra','curl-biceps-barra','Fuerza','Bíceps',array['Antebrazo']::text[],array['Barra'],'Flexión codo','reps','basico',array['barbell curl']),
  ('Curl bíceps mancuernas','curl-biceps-mancuernas','Fuerza','Bíceps',array['Antebrazo']::text[],array['Mancuernas'],'Flexión codo','reps','basico',array['dumbbell curl']),
  ('Curl martillo','curl-martillo','Fuerza','Bíceps',array['Antebrazo']::text[],array['Mancuernas'],'Flexión codo','reps','basico',array['hammer curl']),
  ('Curl predicador','curl-predicador','Fuerza','Bíceps',array['Antebrazo']::text[],array['Máquina','Barra Z'],'Flexión codo','reps','basico',array['preacher curl']),
  ('Curl polea baja','curl-polea-baja','Fuerza','Bíceps',array['Antebrazo']::text[],array['Polea'],'Flexión codo','reps','basico',array['cable curl']),
  ('Extensión tríceps cuerda','extension-triceps-cuerda','Fuerza','Tríceps',array[]::text[],array['Polea'],'Extensión codo','reps','basico',array['pushdown cuerda']),
  ('Pushdown barra','pushdown-barra','Fuerza','Tríceps',array[]::text[],array['Polea','Barra'],'Extensión codo','reps','basico',array['triceps pushdown']),
  ('Extensión tríceps overhead','extension-triceps-overhead','Fuerza','Tríceps',array['Hombros']::text[],array['Mancuernas','Polea'],'Extensión codo','reps','basico',array['overhead triceps extension']),
  ('Rompecráneos','rompecraneos','Fuerza','Tríceps',array[]::text[],array['Barra Z','Mancuernas'],'Extensión codo','reps','intermedio',array['skull crusher']),
  ('Press cerrado','press-cerrado','Fuerza','Tríceps',array['Pecho','Hombros']::text[],array['Barra'],'Empuje horizontal','reps','intermedio',array['close grip bench press']),
  ('Crunch abdominal','crunch-abdominal','Fuerza','Core',array[]::text[],array['Peso corporal'],'Flexión tronco','reps','basico',array['crunch']),
  ('Elevación de piernas','elevacion-de-piernas','Calistenia','Core',array['Cuádriceps','Femorales']::text[],array['Peso corporal'],'Flexión cadera','reps','basico',array['leg raises']),
  ('Plank','plank','Isométrico','Core',array['Hombros']::text[],array['Peso corporal'],'Anti-extensión','time','basico',array['plancha']),
  ('Side plank','side-plank','Isométrico','Core',array['Hombros','Glúteos']::text[],array['Peso corporal'],'Anti-rotación','time','basico',array['plancha lateral']),
  ('Hollow hold','hollow-hold','Isométrico','Core',array['Cuádriceps','Femorales']::text[],array['Peso corporal'],'Anti-extensión','time','intermedio',array['hollow body hold']),
  ('Russian twist','russian-twist','Fuerza','Core',array[]::text[],array['Peso corporal','Disco','Mancuernas'],'Rotación','reps','basico',array['giros rusos']),
  ('Mountain climbers','mountain-climbers','Cardio','Core',array['Cuádriceps','Femorales','Hombros']::text[],array['Peso corporal'],'Cardio core','time','basico',array['escaladores']),
  ('Burpees','burpees','Cardio','Full Body',array['Core','Cuádriceps','Femorales','Pecho']::text[],array['Peso corporal'],'Acondicionamiento','reps','intermedio',array['burpee']),
  ('Jumping jacks','jumping-jacks','Cardio','Cardio',array['Cuádriceps','Femorales','Hombros']::text[],array['Peso corporal'],'Acondicionamiento','time','basico',array['saltos tijera']),
  ('Caminadora','caminadora','Cardio','Cardio',array['Cuádriceps','Femorales']::text[],array['Caminadora'],'Cardio','time','basico',array['treadmill']),
  ('Bicicleta estática','bicicleta-estatica','Cardio','Cardio',array['Cuádriceps','Femorales']::text[],array['Bicicleta'],'Cardio','time','basico',array['stationary bike']),
  ('Remadora','remadora','Cardio','Full Body',array['Core','Cuádriceps','Espalda','Femorales']::text[],array['Remadora'],'Cardio','time','basico',array['rowing machine']),
  ('Assisted handstand','assisted-handstand','Calistenia','Hombros',array['Tríceps','Core']::text[],array['Peso corporal','Pared'],'Empuje vertical','time','intermedio',array['handstand asistido']),
  ('Handstand hold','handstand-hold','Isométrico','Hombros',array['Tríceps','Core']::text[],array['Peso corporal','Pared'],'Empuje vertical','time','avanzado',array['parado de manos']),
  ('Pike push up','pike-push-up','Calistenia','Hombros',array['Tríceps','Core']::text[],array['Peso corporal'],'Empuje vertical','reps','intermedio',array['flexion pike']),
  ('Handstand push up','handstand-push-up','Calistenia','Hombros',array['Tríceps','Core']::text[],array['Peso corporal','Pared'],'Empuje vertical','reps','avanzado',array['hspu']),
  ('L-sit','l-sit','Isométrico','Core',array['Tríceps','Hombros']::text[],array['Peso corporal','Paralelas'],'Compresión','time','avanzado',array['lsit']),
  ('Muscle up','muscle-up','Calistenia','Full Body',array['Espalda','Bíceps','Tríceps','Core']::text[],array['Peso corporal','Barra fija'],'Jalón + empuje','reps','avanzado',array['bar muscle up']),
  ('Toes to bar','toes-to-bar','Calistenia','Core',array['Espalda']::text[],array['Peso corporal','Barra fija'],'Flexión cadera','reps','avanzado',array['punta a barra']),
  ('Box jump','box-jump','Potencia','Cuádriceps',array['Glúteos','Pantorrillas','Core']::text[],array['Caja','Peso corporal'],'Salto','reps','intermedio',array['salto al cajon']),
  ('Kettlebell swing','kettlebell-swing','Potencia','Glúteos',array['Femorales','Espalda','Core']::text[],array['Kettlebell'],'Bisagra','reps','intermedio',array['swing kettlebell'])
)
update public.exercise_catalog c set
  name = case when lower(translate(c.name, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) = lower(translate(s.name, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) then s.name else c.name end,
  aliases = (
    select coalesce(array_agg(distinct a order by a), '{}')
    from unnest(c.aliases || s.aliases || array[lower(c.name)]) a
    where a is not null and btrim(a) <> ''
      and a <> lower(case when lower(translate(c.name, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) = lower(translate(s.name, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) then s.name else c.name end)
  ),
  -- Una ficha pisada se reconoce porque perdió el músculo: solo entonces se le
  -- devuelven también categoría y registro (el upsert ponía 'Fuerza' y 'reps').
  category = case when nullif(btrim(c.primary_muscle), '') is null then s.category else c.category end,
  default_tracking = case when nullif(btrim(c.primary_muscle), '') is null then s.default_tracking else c.default_tracking end,
  primary_muscle = coalesce(nullif(btrim(c.primary_muscle), ''), s.primary_muscle),
  secondary_muscles = case when cardinality(c.secondary_muscles) = 0 then s.secondary_muscles else c.secondary_muscles end,
  equipment = case when cardinality(c.equipment) = 0 then s.equipment else c.equipment end,
  movement_pattern = coalesce(nullif(btrim(c.movement_pattern), ''), s.movement_pattern),
  updated_at = now()
from seed s
where c.slug = s.slug and c.is_active;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1c. Desde skandi_exercises, con la traducción de la 071
-- ─────────────────────────────────────────────────────────────────────────────
-- Recupera las instrucciones, el equipo y los alias en inglés que el upsert
-- vació en las fichas importadas de Skandi. Solo llena lo que está vacío.
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
update public.exercise_catalog c set
  name = case when lower(translate(c.name, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) = lower(translate(p.name, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) then p.name else c.name end,
  aliases = (
    select coalesce(array_agg(distinct a order by a), '{}')
    from unnest(c.aliases || p.aliases || array[lower(c.name)]) a
    where a is not null and btrim(a) <> ''
      and a <> lower(case when lower(translate(c.name, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) = lower(translate(p.name, 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')) then p.name else c.name end)
  ),
  primary_muscle = coalesce(nullif(btrim(c.primary_muscle), ''), p.primary_muscle),
  secondary_muscles = case when cardinality(c.secondary_muscles) = 0 then p.secondary_muscles else c.secondary_muscles end,
  equipment = case when cardinality(c.equipment) = 0 then p.equipment else c.equipment end,
  instructions = coalesce(nullif(btrim(c.instructions), ''), p.instructions),
  video_url = coalesce(nullif(btrim(c.video_url), ''), p.video_url),
  updated_at = now()
from prepared p
where c.slug = p.slug and c.is_active;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Músculo para los que el coach escribió a mano (solo si siguen vacíos)
-- ─────────────────────────────────────────────────────────────────────────────
update public.exercise_catalog c set
  primary_muscle = v.primary_muscle,
  secondary_muscles = case when cardinality(c.secondary_muscles) = 0 then v.secondary_muscles else c.secondary_muscles end,
  category = coalesce(v.category, c.category),
  updated_at = now()
from (values
  ('1 min CLIMBERS o 2 min REMADORA', 'Cardio',     array['Core']::text[],                          'Cardio'),
  ('ABS ALTERNADO',                   'Core',       array[]::text[],                                null),
  ('CURL DE BICEP CONCENTRADO',       'Bíceps',     array['Antebrazo']::text[],                     null),
  ('CURL DE BICEPS',                  'Bíceps',     array['Antebrazo']::text[],                     null),
  ('DESPLANTES ESTATICOS',            'Cuádriceps', array['Glúteos','Femorales']::text[],           null),
  ('ELEVACION FRONTAL CON DISCO',     'Hombros',    array[]::text[],                                null),
  ('EXTENCION UNILATERAL TRICEP',     'Tríceps',    array[]::text[],                                null),
  ('EXTENSION DE TRICEP AGARRE PRONO','Tríceps',    array[]::text[],                                null),
  ('EXTENSION FEMORAL MAQUINA',       'Femorales',  array[]::text[],                                null),
  ('JALON EN POLEA CERRADO',          'Espalda',    array['Bíceps']::text[],                        null),
  ('JALON UNILATERAL EN POLEA',       'Espalda',    array['Bíceps']::text[],                        null),
  ('PATADA DE GLUTEO EN POLEA',       'Glúteos',    array['Femorales']::text[],                     null),
  ('PATADA LATERAL EN POLEA',         'Glúteos',    array[]::text[],                                null),
  ('PRESS INCLINADO',                 'Pecho',      array['Hombros','Tríceps']::text[],             null),
  ('PRESS MILITAR',                   'Hombros',    array['Tríceps']::text[],                       null),
  ('PUSH UPS CON ELEVACION PIERNAS',  'Pecho',      array['Hombros','Tríceps','Core']::text[],      'Calistenia'),
  ('REMO',                            'Espalda',    array['Bíceps']::text[],                        null),
  ('REMO CON BARRA AGARRE INVERTIDO', 'Espalda',    array['Bíceps']::text[],                        null),
  ('REMO EN MÁQUINA AGARRE PRONO',    'Espalda',    array['Bíceps','Hombros']::text[],              null),
  ('REMO UNILATERAL EN BANCO INCLINADO','Espalda',  array['Bíceps']::text[],                        null),
  ('Saltos con cuerda',               'Cardio',     array['Pantorrillas']::text[],                  'Cardio'),
  ('SENTADILLA',                      'Cuádriceps', array['Glúteos','Femorales','Core']::text[],    null),
  ('SMASH BALL',                      'Full Body',  array['Core','Hombros']::text[],                'Potencia')
) as v(name, primary_muscle, secondary_muscles, category)
where lower(c.name) = lower(v.name)
  and c.is_active
  and nullif(btrim(c.primary_muscle), '') is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Fusionar los duplicados claros hacia la ficha del catálogo
-- ─────────────────────────────────────────────────────────────────────────────
-- La que queda se busca por slug, por nombre o por alias (si el admin ya la
-- fusionó en otra, se sigue hasta esa). La que se va, por nombre.
do $$
declare
  r record;
  k uuid;
  d uuid;
  v_res jsonb;
  v_done integer := 0;
begin
  for r in select * from (values
    ('remadora',                         '40 REMADAS'),
    ('remadora',                         '50 REMADAS'),
    ('elevacion-de-piernas',             'ABS ELEVACION DE PIERNAS'),
    ('bench-press-inclinado-mancuernas', 'BENCH PRESS CON MANCUERNAS BANCA INCLINADA 30•'),
    ('curl-polea-baja',                  'BÍCEPS EN POLEA BAJA BARRA CORTA'),
    ('cruce-de-poleas',                  'CROSS OVER'),
    ('elevacion-de-pantorrilla-parado',  'ELEVACION DE TALON'),
    ('elevaciones-laterales-mancuernas', 'ELEVACIONES LATERALES'),
    ('extension-triceps-cuerda',         'EXTENCION DE TRICEP CUERDA'),
    ('EXTENSIÓN CUADRICEPS',             'EXTENSION CRUADRICEP MAQUINA'),
    ('plank',                            'PLANCHA ESTATICA'),
    ('bench-press-barra',                'PRESS BANCA'),
    ('press-militar-barra',              'PRESS DE HOMBRO CON BARRA'),
    ('jalon-al-pecho',                   'JALON EN POLEA'),
    ('remo-con-mancuerna',               'REMO UNILATERAL EN BANCO'),
    ('dominadas-supinas',                'CHIN UPS'),
    ('sentadilla-en-multipower',         'SQUAT MÁQUINA SMITH')
  ) as m(keep_ref, drop_name)
  loop
    select id into k from public.exercise_catalog
     where is_active and (slug = r.keep_ref or lower(name) = lower(r.keep_ref) or r.keep_ref = any(aliases))
     order by (slug = r.keep_ref) desc, (lower(name) = lower(r.keep_ref)) desc
     limit 1;
    select id into d from public.exercise_catalog
     where is_active and lower(name) = lower(r.drop_name)
     limit 1;
    if k is null or d is null or k = d then
      raise notice 'SIN FUSIONAR → % en % (%)', r.drop_name, r.keep_ref,
        case when d is null then 'no está: ¿ya se fusionó?'
             when k is null then 'no encontré la ficha que se queda'
             else 'ya son la misma' end;
      continue;
    end if;
    v_res := public.merge_exercise_catalog(k, d);
    raise notice 'FUSIONADO → «%» ahora incluye «%» (% rutinas repuntadas)',
      v_res->>'kept', v_res->>'merged', v_res->>'boards';
    v_done := v_done + 1;
  end loop;
  raise notice 'Total fusionados: %', v_done;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Lo que quede sin músculo, para asignarlo en Admin → Ejercicios
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select name from public.exercise_catalog
     where is_active and nullif(btrim(primary_muscle), '') is null
     order by name
  loop
    raise notice 'SIN MÚSCULO → %', r.name;
    n := n + 1;
  end loop;
  raise notice 'Quedan % ejercicios sin músculo.', n;
end $$;

commit;
