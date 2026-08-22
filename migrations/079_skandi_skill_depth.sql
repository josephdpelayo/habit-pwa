-- Skandi Fit: las seis piezas que faltaban para que una habilidad se pueda seguir por años
-- y no por semanas. Depende de 078.
--
--  1. side           — lado izquierdo/derecho por serie. En one-leg front lever, weight shift,
--                      pistol o shrimp hoy se promedian los dos lados y el débil se esconde,
--                      que es justo el que decide cuándo llega el one-arm.
--  2. eventos        — skandi_progression_events. skandi_progression_state solo guarda el
--                      escalón actual, sin memoria: no había forma de saber cuánto tardaste en
--                      el tuck. Se siembra reconstruyendo el historial ya registrado.
--  3. metas TUT      — skandi_skill_goals. En estáticos el volumen se mide en segundos bajo
--                      tensión, no en series, y no había dónde guardar el objetivo semanal.
--  4. clips          — clip_path + bucket privado skandi-set-clips. Un video de 5-10 s por
--                      serie es lo único que hace objetiva la nota 1-10.
--  5. tempo          — tempo_seconds/tempo_note por ejercicio, para el metrónomo de la app.
--  6. heel/toe pulls — sale de la línea de handstand (078 lo dejó en rank 4). Es un drill de
--                      balance por repeticiones metido en una escalera medida en segundos: no
--                      es un escalón entre chest-to-wall y el hold libre, es un accesorio.
--
-- Nota sobre "una sola curva por habilidad": no lleva columna. El nivel es
-- rank + min(1, marca / progression_target), calculado en la app — deriva de datos que ya
-- existen y no inventa coeficientes de dificultad que nadie puede verificar.

-- ---------------------------------------------------------------------------
-- 1. Columnas
-- ---------------------------------------------------------------------------

alter table public.skandi_sets
  add column if not exists side text check (side is null or side in ('left','right')),
  add column if not exists clip_path text;

alter table public.skandi_exercises
  add column if not exists unilateral boolean not null default false,
  add column if not exists tempo_seconds integer check (tempo_seconds is null or tempo_seconds between 1 and 120),
  add column if not exists tempo_note text;

comment on column public.skandi_sets.side is
  'Lado trabajado en esta serie, solo para ejercicios con unilateral = true. Null en todo lo demás.';
comment on column public.skandi_sets.clip_path is
  'Ruta en el bucket privado skandi-set-clips. El video es del dueño de la serie y de nadie más.';
comment on column public.skandi_exercises.tempo_seconds is
  'Duración objetivo de la fase lenta (excéntrica) de una repetición, en segundos. Alimenta el metrónomo; los holds usan progression_target en su lugar.';

update public.skandi_exercises set unilateral = true
where slug in (
  'one-leg-front-lever','one-arm-front-lever','handstand-weight-shift','one-arm-handstand',
  'pistol-squat','shrimp-squat','smith-machine-bulgarian-split-squat','dumbbell-single-arm-row',
  'reverse-lunge-step-up','archer-pull-up','archer-push-up','typewriter-pull-up'
);

-- Tempo de la fase excéntrica donde el criterio de 078 ya lo pide en palabras.
update public.skandi_exercises set tempo_seconds=5, tempo_note='4-5 s down, hands catch only at the end' where slug='nordic-curl-negative';
update public.skandi_exercises set tempo_seconds=4, tempo_note='4 s down, then back up without the hands' where slug in ('nordic-curl-assisted','nordic-curl','nordic-curl-weighted');
update public.skandi_exercises set tempo_seconds=3, tempo_note='1 s pause at horizontal, 2 s lowering' where progression_group='front-lever-raise';
update public.skandi_exercises set tempo_seconds=3, tempo_note='3 s through the transition' where slug='muscle-up-negative';

-- ---------------------------------------------------------------------------
-- 2. heel/toe pulls fuera de la escalera de handstand
-- ---------------------------------------------------------------------------

update public.skandi_exercises set
  progression_group=null, progression_rank=null, progression_target=null,
  progression_target_sets=1, track_quality=true,
  progression_criteria='One controlled pull per rep, heel or toe leaves the wall and comes back without falling out.'
where slug='heel-pulls-toe-pulls';

-- La línea queda de 6 escalones, todos en segundos, sin un peldaño medido en repeticiones
-- a media escalera.
update public.skandi_exercises set progression_rank=4 where slug='freestanding-handstand';
update public.skandi_exercises set progression_rank=5 where slug='handstand-weight-shift';
update public.skandi_exercises set progression_rank=6 where slug='one-arm-handstand';

-- ---------------------------------------------------------------------------
-- 3. Historial de progresión
-- ---------------------------------------------------------------------------

create table if not exists public.skandi_progression_events (
  id                uuid primary key default uuid_generate_v4(),
  user_id           uuid references public.profiles(id) on delete cascade not null,
  progression_group text not null,
  from_exercise_id  uuid references public.skandi_exercises(id) on delete set null,
  to_exercise_id    uuid references public.skandi_exercises(id) on delete cascade not null,
  direction         text not null default 'up' check (direction in ('up','down')),
  note              text,
  created_at        timestamptz not null default now()
);

create index if not exists idx_skandi_prog_events_user
  on public.skandi_progression_events(user_id, progression_group, created_at desc);

alter table public.skandi_progression_events enable row level security;

drop policy if exists "Crew read skandi progression events" on public.skandi_progression_events;
create policy "Crew read skandi progression events"
  on public.skandi_progression_events for select using (auth.role() = 'authenticated');

drop policy if exists "Crew manage own skandi progression events" on public.skandi_progression_events;
create policy "Crew manage own skandi progression events"
  on public.skandi_progression_events for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Semilla: la primera vez que cada variante aparece en un entrenamiento terminado ES el
-- momento en que se cambió de escalón. Solo para grupos que todavía no tienen ningún evento,
-- así correr la migración dos veces no duplica el historial.
with first_seen as (
  select s.user_id, e.progression_group, e.id as exercise_id, min(ss.completed_at) as at
  from public.skandi_sets s
  join public.skandi_exercises e on e.id = s.exercise_id
  join public.skandi_sessions ss on ss.id = s.session_id
  where e.progression_group is not null and s.done and ss.completed_at is not null
  group by s.user_id, e.progression_group, e.id
),
ordered as (
  select f.*,
    lag(f.exercise_id) over (partition by f.user_id, f.progression_group order by f.at) as prev_id
  from first_seen f
)
insert into public.skandi_progression_events
  (user_id, progression_group, from_exercise_id, to_exercise_id, direction, note, created_at)
select o.user_id, o.progression_group, o.prev_id, o.exercise_id, 'up',
       'Reconstruido del historial de entrenamientos', o.at
from ordered o
where not exists (
  select 1 from public.skandi_progression_events pe
  where pe.user_id = o.user_id and pe.progression_group = o.progression_group
);

-- ---------------------------------------------------------------------------
-- 4. Meta semanal de tiempo bajo tensión por habilidad
-- ---------------------------------------------------------------------------

create table if not exists public.skandi_skill_goals (
  user_id           uuid references public.profiles(id) on delete cascade not null,
  progression_group text not null,
  weekly_tut_sec    integer not null check (weekly_tut_sec between 0 and 7200),
  updated_at        timestamptz not null default now(),
  primary key (user_id, progression_group)
);

alter table public.skandi_skill_goals enable row level security;

drop policy if exists "Crew read skandi skill goals" on public.skandi_skill_goals;
create policy "Crew read skandi skill goals"
  on public.skandi_skill_goals for select using (auth.role() = 'authenticated');

drop policy if exists "Crew manage own skandi skill goals" on public.skandi_skill_goals;
create policy "Crew manage own skandi skill goals"
  on public.skandi_skill_goals for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 5. Bucket privado para los clips de serie
-- ---------------------------------------------------------------------------

-- Privado, a diferencia de skandi-exercise-media (058): ese es el catálogo compartido de
-- técnica, esto es el video de TU serie. Cada quien ve solo la suya, igual que skandi-meals.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'skandi-set-clips',
  'skandi-set-clips',
  false,
  26214400, -- 25 MB: 5-10 s de video de celular caben de sobra
  array['video/mp4','video/quicktime','video/webm']
)
on conflict (id) do nothing;

-- La primera carpeta de la ruta es el uid del dueño; las políticas se apoyan en eso.
drop policy if exists "Skandi set clips: subir los propios" on storage.objects;
create policy "Skandi set clips: subir los propios"
on storage.objects for insert to authenticated
with check (bucket_id = 'skandi-set-clips' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Skandi set clips: ver los propios" on storage.objects;
create policy "Skandi set clips: ver los propios"
on storage.objects for select to authenticated
using (bucket_id = 'skandi-set-clips' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Skandi set clips: borrar los propios" on storage.objects;
create policy "Skandi set clips: borrar los propios"
on storage.objects for delete to authenticated
using (bucket_id = 'skandi-set-clips' and (storage.foldername(name))[1] = auth.uid()::text);
