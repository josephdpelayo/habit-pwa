-- Rutinas del socio, programas semanales, RIR por serie y ejercicios de sesión.
--
-- Trae a HABIT la organización que ya funciona en Skandi Fit (rutina → semana →
-- programa) sin romper el modelo del coach: los pizarrones que ya existen se
-- quedan exactamente como están y siguen siendo del gym.

-- ─────────────────────────────────────────────────────────────────────────────
-- (a) boards: rutinas con dueño
-- ─────────────────────────────────────────────────────────────────────────────
-- owner_id null = pizarrón del gym/coach. Todas las filas que ya existen quedan
-- así, así que la visibilidad de lo que hay hoy no cambia.
alter table public.boards
  add column if not exists owner_id         uuid references public.profiles(id) on delete cascade,
  add column if not exists forked_from      uuid references public.boards(id) on delete set null,
  add column if not exists forked_from_name text,
  add column if not exists updated_at       timestamptz not null default now();

create index if not exists idx_boards_owner on public.boards(owner_id);

-- La política vieja dejaba a cualquier autenticado leer TODOS los boards, lo
-- cual con rutinas personales significaría que cada socio ve las de los demás.
-- Se sustituye por: los del gym (owner_id null) los ve todo el mundo, y los
-- personales solo su dueño. La política de admin no se toca, así que el coach
-- sigue viendo y editando todo.
drop policy if exists "Auth users read boards" on public.boards;
create policy "Auth users read boards"
  on public.boards for select using (
    auth.uid() is not null and (owner_id is null or owner_id = auth.uid())
  );

drop policy if exists "Users manage own boards" on public.boards;
create policy "Users manage own boards"
  on public.boards for all
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- (b) coaching_week_templates: que el socio edite su propia semana
-- ─────────────────────────────────────────────────────────────────────────────
-- La tabla y el RPC ensure_coaching_week_from_template ya existen (migración
-- 039) pero solo el admin podía escribirlos. El RPC ya autoriza al propio
-- usuario, así que solo falta la política de escritura.
drop policy if exists "Users manage own week template" on public.coaching_week_templates;
create policy "Users manage own week template"
  on public.coaching_week_templates for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- (c) Programas: una semana guardada con nombre
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.coaching_programs (
  id         uuid primary key default uuid_generate_v4(),
  user_id    uuid references public.profiles(id) on delete cascade not null,
  name       text not null,
  notes      text,
  is_active  boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Un solo programa activo por socio: activar otro obliga a desactivar el
-- anterior primero, que es justo lo que hace applyProgram del lado cliente.
create unique index if not exists idx_coaching_programs_one_active
  on public.coaching_programs(user_id) where is_active;

create index if not exists idx_coaching_programs_user
  on public.coaching_programs(user_id);

create table if not exists public.coaching_program_days (
  id          uuid primary key default uuid_generate_v4(),
  program_id  uuid references public.coaching_programs(id) on delete cascade not null,
  dow         integer not null check (dow between 0 and 6),  -- 0 = lunes
  board_id    uuid references public.boards(id) on delete cascade,
  board_name  text not null,          -- snapshot, igual que coaching_schedule
  board_color text not null default '#2563eb',
  unique(program_id, dow)
);

create index if not exists idx_coaching_program_days_program
  on public.coaching_program_days(program_id, dow);

alter table public.coaching_programs     enable row level security;
alter table public.coaching_program_days enable row level security;

drop policy if exists "Users manage own programs" on public.coaching_programs;
create policy "Users manage own programs"
  on public.coaching_programs for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Admin view all programs" on public.coaching_programs;
create policy "Admin view all programs"
  on public.coaching_programs for select
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

drop policy if exists "Users manage own program days" on public.coaching_program_days;
create policy "Users manage own program days"
  on public.coaching_program_days for all
  using (exists(
    select 1 from public.coaching_programs p
    where p.id = program_id and p.user_id = auth.uid()
  ))
  with check (exists(
    select 1 from public.coaching_programs p
    where p.id = program_id and p.user_id = auth.uid()
  ));

drop policy if exists "Admin view all program days" on public.coaching_program_days;
create policy "Admin view all program days"
  on public.coaching_program_days for select
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- ─────────────────────────────────────────────────────────────────────────────
-- (d) RIR por serie
-- ─────────────────────────────────────────────────────────────────────────────
-- target_rir viene de la rutina (boards.exercises[].targetRir) y se siembra
-- SOLO cuando se crea la fila; rir es lo que el socio realmente dejó en el
-- tanque. Resembrar target_rir en cada sesión pisaría el ajuste del socio.
alter table public.coaching_session_sets
  add column if not exists rir        smallint check (rir is null or rir between 0 and 10),
  add column if not exists target_rir smallint check (target_rir is null or target_rir between 0 and 10);

-- ─────────────────────────────────────────────────────────────────────────────
-- (e) Ejercicios metidos o sustituidos a media sesión
-- ─────────────────────────────────────────────────────────────────────────────
-- Cambiar o agregar un ejercicio durante el entreno NO debe tocar
-- boards.exercises: esa rutina puede ser del coach o estar compartida. El
-- ejercicio suplente vive solo en esta sesión, aquí. Cada entrada guarda el
-- mismo shape JSON que boards.exercises más:
--   ex_key       clave con la que se guardan sus series en coaching_session_sets
--   replaces     ex_key del ejercicio que sustituye (null si es un agregado)
--   after_ex_key ex_key después del cual se muestra en la hoja
-- No necesita RLS nueva: las filas de coaching_schedule ya son del socio.
alter table public.coaching_schedule
  add column if not exists session_exercises jsonb not null default '[]';
