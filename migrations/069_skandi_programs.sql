-- Skandi Fit: training programs -- the layer above routines.
-- workout (session) -> routine (skandi_templates) -> program (this migration).
--
-- A program is a saved snapshot of a full week: which routine and which endurance plan sits on
-- each weekday. Loading a program re-stamps skandi_templates.weekday and
-- skandi_activity_templates.weekday, which stay the single source of truth for "my week" --
-- programs are deliberately NOT a second scheduling system, so every existing week/day code
-- path keeps working untouched and switching programs never has to migrate a session or a set.

create table if not exists public.skandi_programs (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid references public.profiles(id) on delete cascade not null,
  name        text not null,
  notes       text,
  is_active   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Exactly one program can describe the live week at a time, per member.
create unique index if not exists idx_skandi_programs_one_active
  on public.skandi_programs(user_id) where is_active;

create table if not exists public.skandi_program_days (
  id                   uuid primary key default uuid_generate_v4(),
  program_id           uuid references public.skandi_programs(id) on delete cascade not null,
  weekday              integer not null check (weekday between 0 and 6),
  -- Both nullable: a day can be strength only, endurance only, or both. A deleted routine
  -- nulls its column (set null) instead of dropping the row, so the endurance plan that shared
  -- that day survives.
  template_id          uuid references public.skandi_templates(id) on delete set null,
  activity_template_id uuid references public.skandi_activity_templates(id) on delete set null,
  unique(program_id, weekday)
);

create index if not exists idx_skandi_programs_user
  on public.skandi_programs(user_id, created_at desc);
create index if not exists idx_skandi_program_days_program
  on public.skandi_program_days(program_id, weekday);

alter table public.skandi_programs enable row level security;
alter table public.skandi_program_days enable row level security;

drop policy if exists "Crew manage own skandi programs" on public.skandi_programs;
create policy "Crew manage own skandi programs"
  on public.skandi_programs for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Day rows carry no user_id of their own: ownership is whatever their program says, so the
-- client can select them with a plain select('*') and still only ever see its own.
drop policy if exists "Crew manage own skandi program days" on public.skandi_program_days;
create policy "Crew manage own skandi program days"
  on public.skandi_program_days for all
  using (exists (select 1 from public.skandi_programs p
                  where p.id = program_id and p.user_id = auth.uid()))
  with check (exists (select 1 from public.skandi_programs p
                       where p.id = program_id and p.user_id = auth.uid()));
