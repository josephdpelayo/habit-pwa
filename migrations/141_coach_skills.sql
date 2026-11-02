-- Escaleras de skills de calistenia en HABIT, para el coaching 1:1.
--
-- Trae a HABIT lo que ya funciona en Skandi Fit (migraciones 078 y 079) con dos cambios de
-- fondo, porque aquí la relación es 1:1 y la revisión del video pasa por WhatsApp:
--
--   · En Skandi el escalón lo decide la app sola: series en el objetivo con calidad 8+/10 en
--     dos sesiones seguidas. HABIT no tiene nota de calidad por serie, y sobre todo la forma
--     de un front lever no la juzga quien lo hace. **Aquí el escalón lo mueve el coach**
--     (coach_student_skills), con lo que vio en el video. La app calcula el estándar y lo
--     sugiere; no lo aplica.
--   · La marca sí sale de lo que registra el alumno (coaching_session_sets.actual_seconds /
--     actual_reps, migración 117), así que la curva de progreso no pide pantalla nueva.
--
-- Lo que SÍ se copia tal cual de Skandi, porque es lo que hace que la escalera sirva:
--   progression_group + progression_rank  — el orden de la línea
--   progression_target + _target_sets     — el estándar para subir: N series en el objetivo,
--                                           no una serie con suerte
--   progression_criteria                  — qué significa "limpio" EN ESTE escalón, en una
--                                           frase, mostrada durante el entrenamiento
--
-- Y una cosa que Skandi no tiene: **animation_url**, un GIF o un MP4 corto en bucle por
-- escalón y por skill, para que el alumno vea la posición en lugar de leerla. Es columna
-- aparte de video_url a propósito: videoKindRank() pone YouTube/Drive por encima de un GIF,
-- así que si la animación viviera en video_url, pegar el video de técnica la borraría de la
-- escalera. Son dos cosas distintas y se eligen por separado.
--
-- Cada escalón ES un ejercicio del exercise_catalog (como en Skandi): así entra en rutinas,
-- se le registran series, tiene músculos, ficha y "La vez pasada" sin escribir nada nuevo.
--
-- Requiere: 037 (exercise_catalog), 071 (la calistenia de Skandi ya traducida),
--           117 (actual_seconds por serie).

begin;

-- ---------------------------------------------------------------------------
-- 1. La escalera, en el catálogo
-- ---------------------------------------------------------------------------

alter table public.exercise_catalog
  add column if not exists progression_group text,
  add column if not exists progression_rank integer check (progression_rank is null or progression_rank between 1 and 30),
  add column if not exists progression_target integer check (progression_target is null or progression_target > 0),
  add column if not exists progression_target_sets integer not null default 1 check (progression_target_sets between 1 and 10),
  add column if not exists progression_criteria text,
  add column if not exists progression_criteria_en text,
  add column if not exists animation_url text;

comment on column public.exercise_catalog.progression_group is
  'Slug de la línea de skill a la que pertenece este escalón (= coach_skills.slug). Null = no es parte de una escalera.';
comment on column public.exercise_catalog.progression_rank is
  'Posición dentro de la línea, 1 = el más fácil. Único por línea.';
comment on column public.exercise_catalog.progression_target is
  'El estándar de este escalón: segundos si default_tracking=time, repeticiones si reps. Null en el último escalón de la línea, que no tiene a dónde subir.';
comment on column public.exercise_catalog.progression_target_sets is
  'Cuántas series hay que clavar en el objetivo para considerar el escalón dominado. Una sola serie buena no es dominar (migración 078 de Skandi).';
comment on column public.exercise_catalog.progression_criteria is
  'Qué es una repetición limpia EN ESTE escalón, en una frase. Se muestra durante el entrenamiento, que es cuando importa.';
comment on column public.exercise_catalog.animation_url is
  'GIF o MP4 corto en bucle que muestra la posición. Aparte de video_url: el video de técnica no debe pisar la animación de la escalera.';

-- Un escalón por posición en cada línea. Índice parcial: la enorme mayoría del catálogo no
-- es parte de ninguna escalera y tiene las dos columnas en null.
create unique index if not exists idx_exercise_catalog_progression
  on public.exercise_catalog(progression_group, progression_rank)
  where progression_group is not null;

create index if not exists idx_exercise_catalog_progression_group
  on public.exercise_catalog(progression_group)
  where progression_group is not null;

-- ---------------------------------------------------------------------------
-- 2. La línea misma
-- ---------------------------------------------------------------------------

create table if not exists public.coach_skills (
  slug          text primary key,
  name_es       text not null,
  name_en       text not null,
  family        text not null default 'otro'
                  check (family in ('tiron','empuje','handstand','pierna','core','otro')),
  summary_es    text,
  summary_en    text,
  animation_url text,
  sort_order    integer not null default 100,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.coach_skills is
  'Una línea de skill (front lever, planche, handstand...). Los escalones viven en exercise_catalog.progression_group = este slug.';

alter table public.coach_skills enable row level security;

-- Las escaleras son material de estudio: cualquier cuenta las lee, tenga coach o no. Eso es
-- justo lo que las hace útiles en HABIT Crew, donde nadie tiene coach todavía.
drop policy if exists "Auth users read coach skills" on public.coach_skills;
create policy "Auth users read coach skills"
  on public.coach_skills for select
  to authenticated
  using (true);

drop policy if exists "Admin manage coach skills" on public.coach_skills;
create policy "Admin manage coach skills"
  on public.coach_skills for all
  to authenticated
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- ---------------------------------------------------------------------------
-- 3. En qué escalón va cada alumno
-- ---------------------------------------------------------------------------

create table if not exists public.coach_student_skills (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  skill_slug  text not null references public.coach_skills(slug) on delete cascade,
  rank        integer not null check (rank between 1 and 30),
  target_rank integer check (target_rank is null or target_rank between 1 and 30),
  coach_note  text,
  set_by      uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, skill_slug)
);

comment on table public.coach_student_skills is
  'El escalón que el COACH le asignó al alumno en una línea. El alumno no se mueve solo: la forma de un skill la juzga quien ve el video.';
comment on column public.coach_student_skills.coach_note is
  'Qué le falta para el siguiente escalón, en palabras del coach. Es lo que el alumno lee en la escalera.';

create index if not exists idx_coach_student_skills_user
  on public.coach_student_skills(user_id);

alter table public.coach_student_skills enable row level security;

-- El alumno lee lo suyo y nada más. No hay política de lectura entre alumnos: un alumno
-- nunca ve el escalón de otro.
drop policy if exists "Students read own skills" on public.coach_student_skills;
create policy "Students read own skills"
  on public.coach_student_skills for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Admin manage student skills" on public.coach_student_skills;
create policy "Admin manage student skills"
  on public.coach_student_skills for all
  to authenticated
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- ---------------------------------------------------------------------------
-- 4. El historial de escalones
-- ---------------------------------------------------------------------------

-- coach_student_skills solo guarda el escalón de hoy. Sin esto no hay forma de contestar
-- "¿cómo ha avanzado?", que es la mitad de para qué existe el coaching; y es lo que permite
-- más adelante un sticker de "subí de escalón" con su fecha. Lo escribe un trigger, no la
-- app: un historial que depende de que el cliente se acuerde de insertar no es un historial.
create table if not exists public.coach_skill_events (
  id         uuid primary key default uuid_generate_v4(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  skill_slug text not null,
  rank       integer not null,
  note       text,
  set_by     uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_coach_skill_events_user
  on public.coach_skill_events(user_id, skill_slug, created_at desc);

alter table public.coach_skill_events enable row level security;

drop policy if exists "Students read own skill events" on public.coach_skill_events;
create policy "Students read own skill events"
  on public.coach_skill_events for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Admin read skill events" on public.coach_skill_events;
create policy "Admin read skill events"
  on public.coach_skill_events for select
  to authenticated
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- Nadie inserta a mano: ni el alumno ni el admin. La fila la pone el trigger de abajo.

create or replace function public.coach_skill_log_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Solo cuando el escalón de verdad se mueve. Editar la nota del coach no es un evento.
  if tg_op = 'UPDATE' and new.rank = old.rank then
    return new;
  end if;
  insert into public.coach_skill_events (user_id, skill_slug, rank, note, set_by)
  values (new.user_id, new.skill_slug, new.rank, new.coach_note, new.set_by);
  return new;
end;
$$;

drop trigger if exists trg_coach_skill_log_event on public.coach_student_skills;
create trigger trg_coach_skill_log_event
  after insert or update of rank on public.coach_student_skills
  for each row execute function public.coach_skill_log_event();

-- ---------------------------------------------------------------------------
-- 5. Los escalones que HABIT no tenía
-- ---------------------------------------------------------------------------

-- La 071 trajo la calistenia de Skandi traducida, pero corrió ANTES de la 078, que es la que
-- arregló las líneas: el escalón de entrada del front lever, el half lay (donde está el salto
-- más grande de la línea), las elevaciones como línea propia, los dos escalones de pared que
-- construyen la parada de manos, y el curl nórdico escalonado. Esos faltan aquí.

insert into public.exercise_catalog
  (name, slug, category, primary_muscle, secondary_muscles, equipment, movement_pattern, default_tracking, difficulty, aliases, instructions)
values
  ('Colgado invertido','colgado-invertido','Calistenia','Espalda',array['Core','Hombros','Bíceps'],array['Peso corporal','Barra fija'],'Isométrico','time','basico',
   array['inverted hang','colgada invertida'],
   'Cuélgate de la barra con agarre prono al ancho de hombros. Sube las rodillas y rueda la cadera hasta quedar de cabeza. Estira las dos piernas hacia arriba, cuerpo vertical y brazos bloqueados. Aguanta apretando glúteo y hundiendo las costillas: una sola línea.'),
  ('Front lever half lay','front-lever-half-lay','Calistenia','Espalda',array['Core','Bíceps','Hombros'],array['Peso corporal','Barra fija'],'Isométrico','time','avanzado',
   array['front lever half lay','half lay'],
   'Colócate como en el front lever straddle, brazos bloqueados y torso horizontal. Junta las piernas y dobla las rodillas a unos 90 grados. Mantén la cadera completamente abierta, muslos en línea con el torso. Aguanta peleando para que la cadera no caiga por debajo de los hombros.'),
  ('Elevación a front lever tuck','elevacion-a-front-lever-tuck','Calistenia','Espalda',array['Core','Bíceps','Hombros'],array['Peso corporal','Barra fija'],'Jalón vertical','reps','intermedio',
   array['tuck front lever raise'],
   'Arranca colgado con brazos estirados y escápulas hundidas. Jala las rodillas al pecho y rueda atrás hasta el front lever tuck. Haz una pausa de un segundo en la horizontal. Baja al colgado con control, brazos todavía bloqueados.'),
  ('Elevación a front lever tuck avanzado','elevacion-a-front-lever-tuck-avanzado','Calistenia','Espalda',array['Core','Bíceps','Hombros'],array['Peso corporal','Barra fija'],'Jalón vertical','reps','avanzado',
   array['advanced tuck front lever raise'],
   'Cuélgate con brazos estirados y escápulas hundidas. Jala hasta el front lever tuck avanzado, cadera abierta y rodillas dobladas. Un segundo de pausa con el torso horizontal. Baja al colgado con los brazos bloqueados.'),
  ('Elevación a front lever straddle','elevacion-a-front-lever-straddle','Calistenia','Espalda',array['Core','Bíceps','Hombros'],array['Peso corporal','Barra fija'],'Jalón vertical','reps','avanzado',
   array['straddle front lever raise'],
   'Cuélgate con brazos estirados y escápulas hundidas. Jala hasta el front lever straddle, piernas abiertas y estiradas. Un segundo de pausa en la horizontal, cadera a la altura de los hombros. Baja al colgado con control.'),
  ('Plancha en pared 45 grados','plancha-en-pared-45-grados','Calistenia','Hombros',array['Core','Tríceps','Antebrazo'],array['Peso corporal','Pared'],'Isométrico','time','basico',
   array['wall plank hold','plank en pared'],
   'Empieza en plancha con los pies contra la base de la pared. Camina los pies por la pared mientras acercas las manos a ella. Detente con el cuerpo a unos 45 grados, hombros abiertos sobre las muñecas. Aguanta con las costillas hundidas y el glúteo apretado.'),
  ('Parada de manos de frente a la pared','parada-de-manos-de-frente-a-la-pared','Calistenia','Hombros',array['Core','Antebrazo','Tríceps'],array['Peso corporal','Pared'],'Isométrico','time','intermedio',
   array['chest to wall handstand','parada de frente a la pared'],
   'De frente a la pared, camina por ella hasta la parada de manos con pecho y muslos tocándola. Apila hombros sobre muñecas, manos a 10-15 cm de la pared. Empuja el piso, costillas hundidas, puntas estiradas y glúteo apretado. Baja una pierna a la vez con control.'),
  ('Traspaso de peso en parada de manos','traspaso-de-peso-en-parada-de-manos','Calistenia','Hombros',array['Core','Antebrazo'],array['Peso corporal','Pared'],'Isométrico','time','avanzado',
   array['handstand weight shift'],
   'Sube a una parada de manos que aguantes cómodo, en pared o libre. Pasa el peso a una mano manteniendo el hombro apilado sobre esa muñeca. Descarga la otra mano hasta que solo apoyen las puntas de los dedos. Aguanta el traspaso, vuelve a dos manos y cambia de lado.'),
  ('Curl nórdico negativo','curl-nordico-negativo','Calistenia','Piernas',array['Glúteos','Core'],array['Peso corporal'],'Flexión rodilla','reps','basico',
   array['nordic curl negative','nórdico negativo'],
   'Arrodíllate con los tobillos anclados, cadera extendida y torso en línea con los muslos. Baja al frente lo más despacio que puedas controlar, resistiendo con el isquio. Atájate con las manos solo cuando ya no puedas frenar la bajada. Empuja con los brazos para volver y repite.'),
  ('Curl nórdico asistido','curl-nordico-asistido','Calistenia','Piernas',array['Glúteos','Core'],array['Peso corporal','Banda'],'Flexión rodilla','reps','intermedio',
   array['assisted nordic curl','nórdico asistido'],
   'Ancla una banda arriba o a un rack detrás de ti y pásala por el pecho. Arrodíllate con los tobillos anclados y la cadera extendida. Baja con control hasta el piso y súbete usando el isquio. Usa la menor tensión de banda que todavía te deje subir sin manos.'),
  ('Curl nórdico con peso','curl-nordico-con-peso','Calistenia','Piernas',array['Glúteos','Core'],array['Peso corporal','Disco'],'Flexión rodilla','reps','avanzado',
   array['weighted nordic curl','nórdico con peso'],
   'Sostén un disco contra el pecho, o usa chaleco con peso. Arrodíllate con los tobillos anclados y la cadera completamente extendida. Baja con control hasta el piso, sin manos. Súbete de vuelta al inicio, tampoco empujando.')
on conflict (slug) do nothing;

-- ---------------------------------------------------------------------------
-- 6. Las líneas
-- ---------------------------------------------------------------------------

insert into public.coach_skills (slug, name_es, name_en, family, summary_es, summary_en, sort_order)
values
  ('front-lever','Front lever','Front Lever','tiron',
   'El cuerpo horizontal colgado de la barra, de frente al techo y con los brazos estirados. Se construye con fuerza escapular de brazo recto y un core que no deja caer la cadera.',
   'The body held horizontal under the bar, facing up, arms locked straight. Built on straight-arm scapular strength and a core that refuses to let the hips drop.',
   10),
  ('front-lever-raise','Elevaciones a front lever','Front Lever Raises','tiron',
   'La parte dinámica de la línea: jalar hasta la horizontal y bajar con control, siempre con los brazos bloqueados. Es lo que convierte el aguante en fuerza utilizable.',
   'The dynamic half of the line: pull up to horizontal and lower under control, arms locked throughout. This is what turns a hold into usable strength.',
   20),
  ('planche','Planche','Planche','empuje',
   'El cuerpo horizontal sobre las manos, con los hombros por delante de las muñecas. La línea más lenta de todas: el progreso se mide en grados de inclinación, no en meses.',
   'The body held horizontal above the hands, shoulders leaning well past the wrists. The slowest line of all: progress is measured in degrees of lean, not in months.',
   30),
  ('handstand','Parada de manos','Handstand','handstand',
   'De la pared al equilibrio libre. La fuerza llega antes que el balance, y la pared de frente es la única posición que obliga a la línea correcta.',
   'From the wall to free balance. Strength arrives before balance, and the chest-to-wall position is the only one that forces the correct line.',
   40),
  ('muscle-up','Muscle-up','Muscle Up','tiron',
   'Pasar de colgado a apoyo arriba de la barra en un solo movimiento. La transición es el ejercicio; la dominada es solo el requisito de entrada.',
   'Going from a hang to support above the bar in one movement. The transition is the exercise; the pull-up is only the entry requirement.',
   50),
  ('back-lever','Back lever','Back Lever','tiron',
   'El cuerpo horizontal de espaldas al piso, brazos estirados. Pide más apertura de hombro que fuerza, y por eso se gana con paciencia y no con intensidad.',
   'The body held horizontal facing the floor, arms straight. It asks for shoulder openness more than strength, so it is won with patience rather than intensity.',
   60),
  ('nordic-curl','Curl nórdico','Nordic Curl','pierna',
   'Bajar y subir el cuerpo solo con el isquiotibial, con los tobillos anclados. El único escalón de pierna aquí, y el que protege la rodilla en todo lo demás.',
   'Lowering and raising the body with the hamstrings alone, ankles anchored. The only leg line here, and the one that protects the knee in everything else.',
   70)
on conflict (slug) do update set
  name_es = excluded.name_es,
  name_en = excluded.name_en,
  family = excluded.family,
  summary_es = excluded.summary_es,
  summary_en = excluded.summary_en,
  sort_order = excluded.sort_order,
  updated_at = now();

-- ---------------------------------------------------------------------------
-- 7. Los escalones de cada línea
-- ---------------------------------------------------------------------------

-- Los objetivos de front lever, elevaciones, handstand y nórdico son los de la 078 de Skandi,
-- ya probados contra el entrenamiento real. Los de planche, muscle-up y back lever los pone
-- esta migración (Skandi solo les había puesto criterio y series), así que son un punto de
-- partida razonable y no una medida: se editan desde Admin → Skills cuando el coach quiera.

create temporary table _rungs(
  grp text, rank integer, slug text, tracking text, target integer, target_sets integer,
  criteria_es text, criteria_en text
) on commit drop;

insert into _rungs values
  -- Front lever (holds)
  ('front-lever',1,'colgado-invertido','time',45,1,
   'Cuerpo vertical y quieto, brazos bloqueados, sin balanceo ni hombros encogidos.',
   'Body vertical and still, arms locked, no swinging or shoulder shrugging.'),
  ('front-lever',2,'front-lever-tuck','time',15,3,
   'Torso horizontal, espalda plana, brazos estirados y bloqueados, rodillas pegadas al pecho.',
   'Torso horizontal, back flat, arms locked straight, knees stay glued to the chest.'),
  ('front-lever',3,'front-lever-tuck-avanzado','time',15,2,
   'Cadera abierta con los muslos despegados del pecho, lumbar plana, torso todavía horizontal.',
   'Hips open with thighs off the chest, lower back flat, torso still horizontal.'),
  ('front-lever',4,'front-lever-a-una-pierna','time',12,2,
   'Una pierna completamente estirada y horizontal, cadera a la altura de los hombros. Alterna la pierna que trabaja entre series.',
   'One leg fully straight and horizontal, hips level with the shoulders. Alternate the working leg between sets.'),
  ('front-lever',5,'front-lever-straddle','time',12,2,
   'Las dos piernas estiradas en straddle, cadera a la altura de los hombros, sin romper en la cadera.',
   'Both legs straight in a straddle, hips level with the shoulders, no piking.'),
  ('front-lever',6,'front-lever-half-lay','time',10,2,
   'Piernas juntas con las rodillas a 90 grados, cadera completamente abierta y a la altura de los hombros.',
   'Legs together with knees bent 90 degrees, hips fully open and level with the shoulders.'),
  ('front-lever',7,'front-lever-completo','time',10,2,
   'Todo el cuerpo horizontal en una sola línea, brazos bloqueados, sin caída en la cadera.',
   'Whole body horizontal in one line, arms locked, no sag at the hips.'),
  ('front-lever',8,'front-lever-a-un-brazo','time',null,1,
   'Último escalón de la línea. Cuerpo horizontal sobre un brazo, cadera cuadrada al techo.',
   'Final rank of the line. Full body horizontal on one arm, hips square to the ceiling.'),
  -- Front lever raises
  ('front-lever-raise',1,'elevacion-a-front-lever-tuck','reps',8,2,
   'Jalado a la posición con brazos estirados, un segundo de pausa en la horizontal, sin kipping.',
   'Pulled into position with straight arms, one second pause at horizontal, no kipping.'),
  ('front-lever-raise',2,'elevacion-a-front-lever-tuck-avanzado','reps',6,2,
   'La cadera se abre en la subida, no al llegar; un segundo de pausa arriba y bajada controlada.',
   'Hips open on the way up, one second pause at horizontal, controlled lowering.'),
  ('front-lever-raise',3,'elevacion-a-front-lever-straddle','reps',5,2,
   'Piernas estiradas en straddle, cadera a la altura de los hombros arriba, sin balanceo abajo.',
   'Legs straight in a straddle, hips level with the shoulders at the top, no swing at the bottom.'),
  ('front-lever-raise',4,'elevaciones-a-front-lever','reps',null,1,
   'Último escalón de la línea. Piernas juntas y estiradas, pausa en la horizontal, bajada con control.',
   'Final rank of the line. Legs together and straight, pause at horizontal, lowered under control.'),
  -- Planche
  ('planche',1,'planche-lean','time',30,2,
   'Hombros claramente por delante de las muñecas, escápulas protraídas, cadera a nivel.',
   'Shoulders clearly ahead of the wrists, scapulae protracted, hips level.'),
  ('planche',2,'plancha-tuck','time',20,2,
   'Pies despegados del piso, rodillas al pecho, brazos bloqueados y hombros por delante de las muñecas.',
   'Feet off the floor, knees tucked, arms locked, shoulders leaning past the wrists.'),
  ('planche',3,'plancha-tuck-avanzada','time',15,2,
   'Cadera abierta con la espalda plana, brazos bloqueados, sin rebote en el hombro.',
   'Hips open with the back flat, arms locked, no bounce at the shoulder.'),
  ('planche',4,'plancha-straddle','time',12,2,
   'Piernas estiradas en straddle, cadera a la altura de los hombros, brazos bloqueados.',
   'Legs straight in a straddle, hips level with the shoulders, arms locked.'),
  ('planche',5,'plancha-completa','time',null,1,
   'Último escalón de la línea. Cuerpo horizontal y recto, brazos bloqueados.',
   'Final rank of the line. Body horizontal and straight, arms locked.'),
  -- Handstand
  ('handstand',1,'plancha-en-pared-45-grados','time',45,1,
   'Hombros abiertos sobre las muñecas, costillas hundidas, sin arco en la lumbar.',
   'Shoulders open over the wrists, ribs down, no arch in the lower back.'),
  ('handstand',2,'parada-de-manos-en-pared','time',45,1,
   'Talones apoyados en la pared, hombros apilados, sin plátano en la espalda.',
   'Heels resting on the wall, shoulders stacked, no banana in the back.'),
  ('handstand',3,'parada-de-manos-de-frente-a-la-pared','time',60,1,
   'Pecho y muslos tocando la pared todo el aguante, manos a 10-15 cm, puntas estiradas.',
   'Chest and thighs touching the wall the whole hold, hands 10-15 cm out, toes pointed.'),
  ('handstand',4,'heel-pulls-toe-pulls','reps',10,2,
   'Un jalón controlado por repetición: el talón o la punta se despega de la pared y vuelve sin caerse.',
   'One controlled pull per rep, heel or toe leaves the wall and comes back without falling out.'),
  ('handstand',5,'parada-de-manos-libre','time',30,2,
   'En equilibrio sobre los dedos sin pared, sin caminar con las manos, y saliste cuando quisiste.',
   'Balanced on fingers with no wall, no walking on the hands, exited on your own terms.'),
  ('handstand',6,'traspaso-de-peso-en-parada-de-manos','time',20,2,
   'El peso completamente sobre un hombro, la otra mano solo con las puntas, cadera cuadrada.',
   'Weight fully over one shoulder, other hand on fingertips only, hips square.'),
  ('handstand',7,'parada-de-manos-a-un-brazo','time',null,1,
   'Último escalón de la línea. La segunda mano despegada del piso y el cuerpo todavía apilado.',
   'Final rank of the line. Second hand fully off the floor, body still stacked.'),
  -- Muscle-up
  ('muscle-up',1,'dominada-al-pecho','reps',8,2,
   'El pecho toca la barra, sin kipping, bajada controlada hasta el colgado muerto.',
   'Chest touches the bar, no kipping, controlled descent to a dead hang.'),
  ('muscle-up',2,'dominada-con-agarre-falso','reps',6,2,
   'Agarre falso sostenido toda la repetición, las muñecas llegan a la altura de la barra.',
   'False grip held the whole rep, wrists reach bar height.'),
  ('muscle-up',3,'muscle-up-negativo','reps',5,2,
   'La bajada por la transición dura 3 segundos o más sin dejarse caer.',
   'Descent through the transition takes 3+ seconds without dropping.'),
  ('muscle-up',4,'muscle-up-en-barra','reps',null,1,
   'Último escalón de la línea. Sin kipping, sin chicken wing, bloqueo completo arriba.',
   'Final rank of the line. No kipping, no chicken wing, lockout at the top.'),
  -- Back lever
  ('back-lever',1,'back-lever-tuck','time',20,2,
   'Rodillas al pecho, brazos bloqueados, cuerpo horizontal y quieto.',
   'Knees tucked to the chest, arms locked, body horizontal and still.'),
  ('back-lever',2,'back-lever-straddle','time',15,2,
   'Piernas estiradas en straddle, brazos bloqueados, hombros abiertos y sin doblar el codo.',
   'Legs straight in a straddle, arms locked, shoulders open with no elbow bend.'),
  ('back-lever',3,'back-lever-completo','time',null,1,
   'Último escalón de la línea. Todo el cuerpo horizontal y recto, brazos bloqueados.',
   'Final rank of the line. Whole body horizontal and straight, arms locked.'),
  -- Nordic curl
  ('nordic-curl',1,'curl-nordico-negativo','reps',5,3,
   'La bajada dura 4-5 segundos con la cadera abierta; las manos solo atajan al final.',
   'Descent lasts 4-5 seconds with the hips open, hands only catch at the very end.'),
  ('nordic-curl',2,'curl-nordico-asistido','reps',6,3,
   'Subes sin manos, cadera extendida todo el recorrido, con la menor tensión de banda posible.',
   'Back up without the hands, hips extended throughout, band tension as low as possible.'),
  ('nordic-curl',3,'curl-nordico','reps',5,2,
   'Bajada y subida completas sin banda y sin empujar con las manos, cadera abierta toda la repetición.',
   'Full descent and full return with no band and no hand push, hips open the whole rep.'),
  ('nordic-curl',4,'curl-nordico-con-peso','reps',null,1,
   'Último escalón de la línea. El mismo estándar que la versión con peso corporal, con el disco en el pecho.',
   'Final rank of the line. Same standard as the bodyweight version, with the plate held on the chest.');

-- Antes de escribir: avisar de lo que no se va a poder marcar. Un slug que no exista deja un
-- hueco en la escalera, y un hueco en la escalera no se ve en la app (simplemente falta un
-- escalón), así que es mejor leerlo aquí que descubrirlo entrenando.
do $$
declare
  r record;
  faltan integer := 0;
begin
  for r in
    select g.grp, g.rank, g.slug from _rungs g
    where not exists (select 1 from public.exercise_catalog c where c.slug = g.slug)
    order by g.grp, g.rank
  loop
    raise notice 'FALTA en exercise_catalog: % (escalón % de %)', r.slug, r.rank, r.grp;
    faltan := faltan + 1;
  end loop;
  -- Un ejercicio escondido (is_active = false) se escondió a propósito: puede ser el lado
  -- perdedor de un merge_exercise_catalog (123). Esta migración NO lo reactiva —eso
  -- desharía en silencio una decisión del admin— pero su escalón no saldría en la escalera,
  -- así que se avisa para que se resuelva desde Admin → Ejercicios.
  for r in
    select c.slug, c.name, g.grp, g.rank
    from _rungs g join public.exercise_catalog c on c.slug = g.slug
    where c.is_active = false
    order by g.grp, g.rank
  loop
    raise notice 'ESCONDIDO: "%" (%) es el escalón % de %, pero is_active = false: no saldrá en la escalera.',
      r.name, r.slug, r.rank, r.grp;
    faltan := faltan + 1;
  end loop;
  if faltan = 0 then
    raise notice 'Las 7 líneas tienen todos sus escalones en el catálogo.';
  else
    raise notice '% escalón(es) sin ejercicio activo: la línea queda incompleta pero la migración sigue.', faltan;
  end if;
end $$;

-- La escalera apunta a los ejercicios que trajo la 071 (los que tienen el GIF, las
-- instrucciones y la línea completa de Skandi). Pero la 037 ya había sembrado algunos del
-- mismo movimiento con otro nombre, y la 071 no los unió: si una rutina usa el de la 037, su
-- historial no cuenta para la escalera. No se unen aquí a propósito —unir es una decisión
-- sobre datos y para eso está merge_exercise_catalog() de la 123, desde Admin → Ejercicios →
-- "Posibles repetidos"—, pero sí se avisan, que es lo que nadie iba a notar solo.
do $$
declare
  r record;
begin
  for r in
    select c.slug, c.name, k.keep_slug
    from (values
      ('muscle-up','muscle-up-en-barra'),
      ('handstand-hold','parada-de-manos-libre'),
      ('assisted-handstand','parada-de-manos-en-pared')
    ) as k(dup_slug, keep_slug)
    join public.exercise_catalog c on c.slug = k.dup_slug
    where exists (select 1 from _rungs g where g.slug = k.keep_slug)
  loop
    raise notice 'POSIBLE REPETIDO: "%" (%) es el mismo movimiento que el escalón %. Únelos en Admin → Ejercicios.',
      r.name, r.slug, r.keep_slug;
  end loop;
end $$;

-- Limpiar cualquier marca previa de estas líneas antes de reescribirlas: así volver a correr
-- la migración después de renumerar una línea no deja un escalón viejo colgado con un rank
-- que ya no existe (y el índice único no lo permitiría).
update public.exercise_catalog
  set progression_group = null, progression_rank = null, progression_target = null,
      progression_target_sets = 1, progression_criteria = null, progression_criteria_en = null
where progression_group in (select distinct grp from _rungs);

update public.exercise_catalog c
  set progression_group = g.grp,
      progression_rank = g.rank,
      progression_target = g.target,
      progression_target_sets = g.target_sets,
      progression_criteria = g.criteria_es,
      progression_criteria_en = g.criteria_en,
      default_tracking = g.tracking,
      updated_at = now()
from _rungs g
where c.slug = g.slug;

-- ---------------------------------------------------------------------------
-- 8. El bucket de las animaciones
-- ---------------------------------------------------------------------------

-- Público de leer, como skandi-exercise-media (058): una animación de un escalón no es
-- privada, es material de estudio, y si fuera privada cada miniatura de la escalera pediría
-- una URL firmada. Escribir y borrar es solo del admin: el catálogo es del gym.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('skill-media','skill-media', true, 15728640,
        array['image/gif','image/webp','image/png','image/jpeg','video/mp4','video/webm'])
on conflict (id) do update set
  public = true,
  file_size_limit = 15728640,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Skill media es pública" on storage.objects;
create policy "Skill media es pública"
on storage.objects for select
to public
using (bucket_id = 'skill-media');

drop policy if exists "Admin sube skill media" on storage.objects;
create policy "Admin sube skill media"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'skill-media'
  and exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
);

drop policy if exists "Admin borra skill media" on storage.objects;
create policy "Admin borra skill media"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'skill-media'
  and exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
);

drop policy if exists "Admin actualiza skill media" on storage.objects;
create policy "Admin actualiza skill media"
on storage.objects for update
to authenticated
using (
  bucket_id = 'skill-media'
  and exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
);

commit;
