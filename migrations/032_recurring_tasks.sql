-- Tareas diarias recurrentes (ayuno intermitente, 2L de agua, meditación, etc.)
-- Se añade is_recurring a coaching_tasks (due_date/is_done se ignoran para
-- estas filas) y una tabla de logs por día para que el cliente pueda
-- palomear cada tarea recurrente día a día sin perder el historial.

alter table public.coaching_tasks
  add column if not exists is_recurring boolean not null default false;

create table if not exists public.coaching_task_logs (
  id           uuid primary key default uuid_generate_v4(),
  task_id      uuid references public.coaching_tasks(id) on delete cascade not null,
  user_id      uuid references public.profiles(id) on delete cascade not null,
  ds           date not null,
  completed_at timestamptz not null default now(),
  unique(task_id, ds)
);
create index if not exists idx_coaching_task_logs_user_ds on public.coaching_task_logs(user_id, ds);

alter table public.coaching_task_logs enable row level security;

drop policy if exists "Users manage own task logs" on public.coaching_task_logs;
create policy "Users manage own task logs"
  on public.coaching_task_logs for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Admin view all task logs" on public.coaching_task_logs;
create policy "Admin view all task logs"
  on public.coaching_task_logs for select
  using (exists(select 1 from public.profiles where id=auth.uid() and role='admin'));
