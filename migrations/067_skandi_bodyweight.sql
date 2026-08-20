-- Skandi Fit: bodyweight log. Not tied to a session — you weigh in whenever, not necessarily
-- every workout. Needed for relative-strength framing (Front Lever/Planche are a % of
-- bodyweight, not an absolute load) and to interpret running pace/HR trends correctly.

create table if not exists public.skandi_bodyweight_logs (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid references public.profiles(id) on delete cascade not null,
  logged_at   date not null default current_date,
  weight_kg   numeric(5,2) not null check (weight_kg between 20 and 300),
  note        text,
  created_at  timestamptz not null default now(),
  unique(user_id, logged_at)
);

create index if not exists idx_skandi_bodyweight_logs_user_date
  on public.skandi_bodyweight_logs(user_id, logged_at desc);

alter table public.skandi_bodyweight_logs enable row level security;

drop policy if exists "Crew manage own skandi bodyweight logs" on public.skandi_bodyweight_logs;
create policy "Crew manage own skandi bodyweight logs"
  on public.skandi_bodyweight_logs for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
