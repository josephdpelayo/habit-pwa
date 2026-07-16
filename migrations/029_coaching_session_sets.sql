-- Tracking de series individuales durante una sesión de entreno activa
-- (checkmarks por serie, reps reales, "+Agregar serie") — referencia Everfit.
-- Se siembra con las series configuradas del ejercicio al iniciar la sesión
-- (startCoachingSessionSb), así que las filas siempre existen de antemano;
-- no hay estado "virtual" del lado cliente.

create table if not exists public.coaching_session_sets (
  id           uuid primary key default uuid_generate_v4(),
  schedule_id  uuid references public.coaching_schedule(id) on delete cascade not null,
  user_id      uuid references public.profiles(id) on delete cascade not null,
  ex_key       text not null,
  set_idx      integer not null,
  reps_target  text,
  actual_reps  text,
  done         boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique(schedule_id, ex_key, set_idx)
);
create index if not exists idx_coaching_session_sets_schedule on public.coaching_session_sets(schedule_id, ex_key);

alter table public.coaching_session_sets enable row level security;

create policy "Users manage own session sets"
  on public.coaching_session_sets for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Admin view all session sets"
  on public.coaching_session_sets for select
  using (exists(select 1 from public.profiles where id=auth.uid() and role='admin'));
