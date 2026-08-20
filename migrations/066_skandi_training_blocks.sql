-- Skandi Fit: training blocks (N progressive-load weeks + 1 deload week), per
-- Plan_Hibrido_Final_v3's "Semana 4 - descarga" page. build_weeks is user-configurable
-- (the plan itself mentions both 4+1 and 5+1 cadences) rather than hardcoded.
--
-- No "closed"/status column: the current block is just the row with the latest start_date
-- for that user. Past blocks stay as history. A new row is only ever inserted when the
-- member explicitly starts the next block (see openReport/finishWorkout's deload
-- criteria) — the app never auto-repeats a block by calendar alone.

create table if not exists public.skandi_training_blocks (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid references public.profiles(id) on delete cascade not null,
  start_date   date not null,
  build_weeks  integer not null default 4 check (build_weeks between 1 and 8),
  note         text,
  created_at   timestamptz not null default now()
);

create index if not exists idx_skandi_training_blocks_user_start
  on public.skandi_training_blocks(user_id, start_date desc);

alter table public.skandi_training_blocks enable row level security;

drop policy if exists "Crew manage own skandi training blocks" on public.skandi_training_blocks;
create policy "Crew manage own skandi training blocks"
  on public.skandi_training_blocks for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
