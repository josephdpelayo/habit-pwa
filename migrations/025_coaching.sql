-- ═══════════════════════════════════════════════════════════
-- Coaching (beta oculta) — Fase 1: Coaching + Hoy
-- Gated por-usuario via profiles.coaching_beta (default false).
-- duration_sec/completed_at en coaching_schedule se dejan listos
-- para que una fase futura de "minutos entrenados" solo tenga
-- que sumarlos.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS coaching_beta boolean NOT NULL DEFAULT false;

-- ── TABLA: coaching_schedule (rutina asignada a un cliente en un día) ──
create table if not exists public.coaching_schedule (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid references public.profiles(id) on delete cascade not null,
  board_id      uuid references public.boards(id) on delete set null,
  board_name    text not null,          -- snapshot: sobrevive si el board se renombra/borra
  board_color   text not null default '#2563eb',
  ds            date not null,
  status        text not null default 'scheduled' check (status in ('scheduled','in_progress','done')),
  started_at    timestamptz,
  completed_at  timestamptz,
  duration_sec  integer,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  unique(user_id, ds)
);
create index if not exists idx_coaching_schedule_user_ds on public.coaching_schedule(user_id, ds);

-- ── TABLA: coaching_tasks (tareas sueltas asignadas por el coach) ──
create table if not exists public.coaching_tasks (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid references public.profiles(id) on delete cascade not null,
  title         text not null,
  due_date      date,
  is_done       boolean not null default false,
  completed_at  timestamptz,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists idx_coaching_tasks_user_due on public.coaching_tasks(user_id, due_date);

alter table public.coaching_schedule enable row level security;
alter table public.coaching_tasks enable row level security;

-- ── POLÍTICAS: coaching_schedule ──
create policy "Users read own coaching schedule"
  on public.coaching_schedule for select using (auth.uid() = user_id);
create policy "Users update own coaching schedule"
  on public.coaching_schedule for update using (auth.uid() = user_id);
create policy "Admin manage coaching schedule"
  on public.coaching_schedule for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );

-- ── POLÍTICAS: coaching_tasks ──
create policy "Users read own coaching tasks"
  on public.coaching_tasks for select using (auth.uid() = user_id);
create policy "Users update own coaching tasks"
  on public.coaching_tasks for update using (auth.uid() = user_id);
create policy "Admin manage coaching tasks"
  on public.coaching_tasks for all using (
    exists(select 1 from public.profiles where id=auth.uid() and role='admin')
  );
