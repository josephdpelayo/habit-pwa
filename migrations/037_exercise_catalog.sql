-- Biblioteca maestra de ejercicios para construir rutinas con metadata consistente.

create extension if not exists "uuid-ossp";

create table if not exists public.exercise_catalog (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  slug text not null unique,
  category text not null default 'Fuerza',
  primary_muscle text,
  secondary_muscles text[] not null default '{}',
  equipment text[] not null default '{}',
  movement_pattern text,
  default_tracking text not null default 'reps' check (default_tracking in ('reps','time')),
  difficulty text not null default 'basico',
  instructions text,
  video_url text,
  aliases text[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_exercise_catalog_primary on public.exercise_catalog(primary_muscle);
create index if not exists idx_exercise_catalog_category on public.exercise_catalog(category);
create index if not exists idx_exercise_catalog_active on public.exercise_catalog(is_active);
create index if not exists idx_exercise_catalog_aliases on public.exercise_catalog using gin(aliases);
create index if not exists idx_exercise_catalog_secondary on public.exercise_catalog using gin(secondary_muscles);
create index if not exists idx_exercise_catalog_equipment on public.exercise_catalog using gin(equipment);

alter table public.exercise_catalog enable row level security;

drop policy if exists "Auth users read exercise catalog" on public.exercise_catalog;
create policy "Auth users read exercise catalog"
  on public.exercise_catalog for select
  using (auth.uid() is not null and is_active = true);

drop policy if exists "Admin manage exercise catalog" on public.exercise_catalog;
create policy "Admin manage exercise catalog"
  on public.exercise_catalog for all
  using (exists(select 1 from public.profiles where id=auth.uid() and role='admin'))
  with check (exists(select 1 from public.profiles where id=auth.uid() and role='admin'));

insert into public.exercise_catalog
  (name, slug, category, primary_muscle, secondary_muscles, equipment, movement_pattern, default_tracking, difficulty, aliases)
values
  ('Bench press barra','bench-press-barra','Fuerza','Pecho',array['Tríceps','Hombros'],array['Barra','Banco'],'Empuje horizontal','reps','basico',array['press banca','bench press horizontal barra']),
  ('Bench press mancuernas','bench-press-mancuernas','Fuerza','Pecho',array['Tríceps','Hombros'],array['Mancuernas','Banco'],'Empuje horizontal','reps','basico',array['press pecho mancuernas']),
  ('Bench press inclinado barra','bench-press-inclinado-barra','Fuerza','Pecho',array['Hombros','Tríceps'],array['Barra','Banco inclinado'],'Empuje inclinado','reps','basico',array['press inclinado barra']),
  ('Bench press inclinado mancuernas','bench-press-inclinado-mancuernas','Fuerza','Pecho',array['Hombros','Tríceps'],array['Mancuernas','Banco inclinado'],'Empuje inclinado','reps','basico',array['press inclinado mancuernas']),
  ('Aperturas con mancuernas','aperturas-con-mancuernas','Fuerza','Pecho',array['Hombros'],array['Mancuernas','Banco'],'Aducción','reps','basico',array['fly mancuernas']),
  ('Aperturas en peck deck','aperturas-en-peck-deck','Fuerza','Pecho',array['Hombros'],array['Máquina'],'Aducción','reps','basico',array['pec deck','contractora']),
  ('Cross over polea alta','cross-over-polea-alta','Fuerza','Pecho',array['Hombros'],array['Polea'],'Aducción','reps','basico',array['cruce polea alta']),
  ('Cross over polea baja','cross-over-polea-baja','Fuerza','Pecho',array['Hombros'],array['Polea'],'Aducción','reps','basico',array['cruce polea baja']),
  ('Push up','push-up','Calistenia','Pecho',array['Tríceps','Hombros','Core'],array['Peso corporal'],'Empuje horizontal','reps','basico',array['lagartija','flexion']),
  ('Push up diamante','push-up-diamante','Calistenia','Tríceps',array['Pecho','Hombros','Core'],array['Peso corporal'],'Empuje horizontal','reps','intermedio',array['diamond push up']),
  ('Fondos en paralelas','fondos-en-paralelas','Calistenia','Tríceps',array['Pecho','Hombros'],array['Peso corporal','Paralelas'],'Empuje vertical','reps','intermedio',array['dips']),
  ('Fondos en banca','fondos-en-banca','Calistenia','Tríceps',array['Pecho','Hombros'],array['Banco','Peso corporal'],'Empuje vertical','reps','basico',array['bench dips']),
  ('Press militar barra','press-militar-barra','Fuerza','Hombros',array['Tríceps','Core'],array['Barra'],'Empuje vertical','reps','basico',array['overhead press barra']),
  ('Press militar mancuernas','press-militar-mancuernas','Fuerza','Hombros',array['Tríceps','Core'],array['Mancuernas'],'Empuje vertical','reps','basico',array['shoulder press mancuernas']),
  ('Press Arnold','press-arnold','Fuerza','Hombros',array['Tríceps'],array['Mancuernas'],'Empuje vertical','reps','intermedio',array['arnold press']),
  ('Elevaciones laterales mancuernas','elevaciones-laterales-mancuernas','Fuerza','Hombros',array[],array['Mancuernas'],'Abducción','reps','basico',array['laterales mancuernas']),
  ('Elevaciones laterales polea','elevaciones-laterales-polea','Fuerza','Hombros',array[],array['Polea'],'Abducción','reps','basico',array['laterales polea']),
  ('Elevaciones frontales','elevaciones-frontales','Fuerza','Hombros',array['Pecho'],array['Mancuernas'],'Flexión hombro','reps','basico',array['front raises']),
  ('Face pull','face-pull','Fuerza','Hombros',array['Espalda'],array['Polea'],'Jalón','reps','basico',array['jalon rostro']),
  ('Pájaros mancuernas','pajaros-mancuernas','Fuerza','Hombros',array['Espalda'],array['Mancuernas'],'Abducción posterior','reps','basico',array['reverse fly']),
  ('Dominadas pronas','dominadas-pronas','Calistenia','Espalda',array['Bíceps','Core'],array['Peso corporal','Barra fija'],'Jalón vertical','reps','intermedio',array['pull up']),
  ('Dominadas supinas','dominadas-supinas','Calistenia','Bíceps',array['Espalda','Core'],array['Peso corporal','Barra fija'],'Jalón vertical','reps','intermedio',array['chin up']),
  ('Jalón al pecho','jalon-al-pecho','Fuerza','Espalda',array['Bíceps'],array['Polea','Máquina'],'Jalón vertical','reps','basico',array['lat pulldown']),
  ('Remo con barra','remo-con-barra','Fuerza','Espalda',array['Bíceps','Core'],array['Barra'],'Jalón horizontal','reps','basico',array['barbell row']),
  ('Remo con mancuerna','remo-con-mancuerna','Fuerza','Espalda',array['Bíceps'],array['Mancuernas','Banco'],'Jalón horizontal','reps','basico',array['one arm row']),
  ('Remo sentado polea','remo-sentado-polea','Fuerza','Espalda',array['Bíceps'],array['Polea'],'Jalón horizontal','reps','basico',array['seated cable row']),
  ('Remo T bar','remo-t-bar','Fuerza','Espalda',array['Bíceps'],array['Barra','Máquina'],'Jalón horizontal','reps','intermedio',array['t bar row']),
  ('Pullover polea','pullover-polea','Fuerza','Espalda',array['Pecho','Core'],array['Polea'],'Jalón','reps','basico',array['straight arm pulldown']),
  ('Australian row','australian-row','Calistenia','Espalda',array['Bíceps','Core'],array['Peso corporal','Barra fija'],'Jalón horizontal','reps','basico',array['remo invertido']),
  ('Peso muerto convencional','peso-muerto-convencional','Fuerza','Espalda',array['Piernas','Core'],array['Barra'],'Bisagra','reps','intermedio',array['deadlift']),
  ('Sentadilla barra','sentadilla-barra','Fuerza','Piernas',array['Core','Espalda'],array['Barra'],'Sentadilla','reps','basico',array['back squat']),
  ('Sentadilla frontal','sentadilla-frontal','Fuerza','Piernas',array['Core','Espalda'],array['Barra'],'Sentadilla','reps','intermedio',array['front squat']),
  ('Prensa de pierna','prensa-de-pierna','Fuerza','Piernas',array['Glúteos'],array['Máquina'],'Sentadilla','reps','basico',array['leg press']),
  ('Extensión de cuádriceps','extension-de-cuadriceps','Fuerza','Piernas',array[],array['Máquina'],'Extensión rodilla','reps','basico',array['leg extension']),
  ('Curl femoral acostado','curl-femoral-acostado','Fuerza','Piernas',array['Glúteos'],array['Máquina'],'Flexión rodilla','reps','basico',array['leg curl acostado']),
  ('Curl femoral sentado','curl-femoral-sentado','Fuerza','Piernas',array['Glúteos'],array['Máquina'],'Flexión rodilla','reps','basico',array['seated leg curl']),
  ('Hip thrust','hip-thrust','Fuerza','Piernas',array['Core'],array['Barra','Banco'],'Extensión cadera','reps','basico',array['empuje de cadera']),
  ('Peso muerto rumano','peso-muerto-rumano','Fuerza','Piernas',array['Espalda','Core'],array['Barra','Mancuernas'],'Bisagra','reps','basico',array['romanian deadlift']),
  ('Zancadas caminando','zancadas-caminando','Fuerza','Piernas',array['Glúteos','Core'],array['Mancuernas','Peso corporal'],'Desplante','reps','basico',array['walking lunges']),
  ('Bulgarian split squat','bulgarian-split-squat','Fuerza','Piernas',array['Glúteos','Core'],array['Mancuernas','Banco'],'Desplante','reps','intermedio',array['sentadilla bulgara']),
  ('Elevación de pantorrilla parado','elevacion-de-pantorrilla-parado','Fuerza','Piernas',array[],array['Máquina','Mancuernas'],'Pantorrilla','reps','basico',array['standing calf raise']),
  ('Curl bíceps barra','curl-biceps-barra','Fuerza','Bíceps',array['Antebrazo'],array['Barra'],'Flexión codo','reps','basico',array['barbell curl']),
  ('Curl bíceps mancuernas','curl-biceps-mancuernas','Fuerza','Bíceps',array['Antebrazo'],array['Mancuernas'],'Flexión codo','reps','basico',array['dumbbell curl']),
  ('Curl martillo','curl-martillo','Fuerza','Bíceps',array['Antebrazo'],array['Mancuernas'],'Flexión codo','reps','basico',array['hammer curl']),
  ('Curl predicador','curl-predicador','Fuerza','Bíceps',array['Antebrazo'],array['Máquina','Barra Z'],'Flexión codo','reps','basico',array['preacher curl']),
  ('Curl polea baja','curl-polea-baja','Fuerza','Bíceps',array['Antebrazo'],array['Polea'],'Flexión codo','reps','basico',array['cable curl']),
  ('Extensión tríceps cuerda','extension-triceps-cuerda','Fuerza','Tríceps',array[],array['Polea'],'Extensión codo','reps','basico',array['pushdown cuerda']),
  ('Pushdown barra','pushdown-barra','Fuerza','Tríceps',array[],array['Polea','Barra'],'Extensión codo','reps','basico',array['triceps pushdown']),
  ('Extensión tríceps overhead','extension-triceps-overhead','Fuerza','Tríceps',array['Hombros'],array['Mancuernas','Polea'],'Extensión codo','reps','basico',array['overhead triceps extension']),
  ('Rompecráneos','rompecraneos','Fuerza','Tríceps',array[],array['Barra Z','Mancuernas'],'Extensión codo','reps','intermedio',array['skull crusher']),
  ('Press cerrado','press-cerrado','Fuerza','Tríceps',array['Pecho','Hombros'],array['Barra'],'Empuje horizontal','reps','intermedio',array['close grip bench press']),
  ('Crunch abdominal','crunch-abdominal','Fuerza','Core',array[],array['Peso corporal'],'Flexión tronco','reps','basico',array['crunch']),
  ('Elevación de piernas','elevacion-de-piernas','Calistenia','Core',array['Piernas'],array['Peso corporal'],'Flexión cadera','reps','basico',array['leg raises']),
  ('Plank','plank','Isométrico','Core',array['Hombros'],array['Peso corporal'],'Anti-extensión','time','basico',array['plancha']),
  ('Side plank','side-plank','Isométrico','Core',array['Hombros','Glúteos'],array['Peso corporal'],'Anti-rotación','time','basico',array['plancha lateral']),
  ('Hollow hold','hollow-hold','Isométrico','Core',array['Piernas'],array['Peso corporal'],'Anti-extensión','time','intermedio',array['hollow body hold']),
  ('Russian twist','russian-twist','Fuerza','Core',array[],array['Peso corporal','Disco','Mancuernas'],'Rotación','reps','basico',array['giros rusos']),
  ('Mountain climbers','mountain-climbers','Cardio','Core',array['Hombros','Piernas'],array['Peso corporal'],'Cardio core','time','basico',array['escaladores']),
  ('Burpees','burpees','Cardio','Full Body',array['Pecho','Piernas','Core'],array['Peso corporal'],'Acondicionamiento','reps','intermedio',array['burpee']),
  ('Jumping jacks','jumping-jacks','Cardio','Cardio',array['Piernas','Hombros'],array['Peso corporal'],'Acondicionamiento','time','basico',array['saltos tijera']),
  ('Caminadora','caminadora','Cardio','Cardio',array['Piernas'],array['Caminadora'],'Cardio','time','basico',array['treadmill']),
  ('Bicicleta estática','bicicleta-estatica','Cardio','Cardio',array['Piernas'],array['Bicicleta'],'Cardio','time','basico',array['stationary bike']),
  ('Remadora','remadora','Cardio','Full Body',array['Espalda','Piernas','Core'],array['Remadora'],'Cardio','time','basico',array['rowing machine']),
  ('Assisted handstand','assisted-handstand','Calistenia','Hombros',array['Tríceps','Core'],array['Peso corporal','Pared'],'Empuje vertical','time','intermedio',array['handstand asistido']),
  ('Handstand hold','handstand-hold','Isométrico','Hombros',array['Tríceps','Core'],array['Peso corporal','Pared'],'Empuje vertical','time','avanzado',array['parado de manos']),
  ('Pike push up','pike-push-up','Calistenia','Hombros',array['Tríceps','Core'],array['Peso corporal'],'Empuje vertical','reps','intermedio',array['flexion pike']),
  ('Handstand push up','handstand-push-up','Calistenia','Hombros',array['Tríceps','Core'],array['Peso corporal','Pared'],'Empuje vertical','reps','avanzado',array['hspu']),
  ('L-sit','l-sit','Isométrico','Core',array['Tríceps','Hombros'],array['Peso corporal','Paralelas'],'Compresión','time','avanzado',array['lsit']),
  ('Muscle up','muscle-up','Calistenia','Full Body',array['Espalda','Bíceps','Tríceps','Core'],array['Peso corporal','Barra fija'],'Jalón + empuje','reps','avanzado',array['bar muscle up']),
  ('Toes to bar','toes-to-bar','Calistenia','Core',array['Espalda'],array['Peso corporal','Barra fija'],'Flexión cadera','reps','avanzado',array['punta a barra']),
  ('Box jump','box-jump','Potencia','Piernas',array['Core'],array['Caja','Peso corporal'],'Salto','reps','intermedio',array['salto al cajon']),
  ('Kettlebell swing','kettlebell-swing','Potencia','Piernas',array['Espalda','Core'],array['Kettlebell'],'Bisagra','reps','intermedio',array['swing kettlebell'])
on conflict (slug) do update set
  name = excluded.name,
  category = excluded.category,
  primary_muscle = excluded.primary_muscle,
  secondary_muscles = excluded.secondary_muscles,
  equipment = excluded.equipment,
  movement_pattern = excluded.movement_pattern,
  default_tracking = excluded.default_tracking,
  difficulty = excluded.difficulty,
  aliases = excluded.aliases,
  is_active = true,
  updated_at = now();
