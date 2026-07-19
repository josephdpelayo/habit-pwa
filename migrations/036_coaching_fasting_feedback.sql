-- Historial de ayunos + feedback post-entreno para Coaching.

create table if not exists public.coaching_fasting_logs (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid references public.profiles(id) on delete cascade not null,
  fast_start_at timestamptz not null,
  fast_end_at   timestamptz not null,
  fast_start_ds date not null,
  fast_end_ds   date not null,
  duration_min  integer not null,
  target_hours  integer not null default 16,
  note          text,
  created_at    timestamptz not null default now()
);

create index if not exists idx_coaching_fasting_logs_user_start
  on public.coaching_fasting_logs(user_id, fast_start_ds desc);

alter table public.coaching_fasting_logs enable row level security;

drop policy if exists "Users manage own fasting logs" on public.coaching_fasting_logs;
create policy "Users manage own fasting logs"
  on public.coaching_fasting_logs for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Admin view all fasting logs" on public.coaching_fasting_logs;
create policy "Admin view all fasting logs"
  on public.coaching_fasting_logs for select
  using (exists(select 1 from public.profiles where id=auth.uid() and role='admin'));

alter table public.coaching_schedule
  add column if not exists feedback_energy text check (feedback_energy is null or feedback_energy in ('baja','normal','alta')),
  add column if not exists feedback_soreness boolean,
  add column if not exists feedback_note text;

do $$
begin
  alter table public.coaching_schedule drop constraint if exists coaching_schedule_status_check;
  alter table public.coaching_schedule
    add constraint coaching_schedule_status_check
    check (status in ('scheduled','in_progress','done','skipped'));
end $$;
