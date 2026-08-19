-- Skandi Fit: recurring endurance/cardio plans ("every Wednesday run 5km at Zone 2") so
-- cardio work gets the same "today's plan" treatment strength routines already have via
-- skandi_templates — plus heart rate and a link back to the plan on logged activities.

create table if not exists public.skandi_activity_templates (
  id                      uuid primary key default uuid_generate_v4(),
  user_id                 uuid references public.profiles(id) on delete cascade not null,
  activity_type           text not null check (activity_type in
                            ('running','cycling','swimming','rowing','walking','other')),
  weekday                 integer check (weekday between 0 and 6), -- null = unscheduled / library only
  target_distance_km      numeric(6,2) check (target_distance_km is null or target_distance_km between 0 and 500),
  target_duration_min     integer check (target_duration_min is null or target_duration_min between 1 and 600),
  target_pace_sec_per_km  integer check (target_pace_sec_per_km is null or target_pace_sec_per_km between 60 and 3600),
  target_zone             integer check (target_zone between 1 and 5), -- heart rate zone 1-5, manual (no device integration)
  notes                   text,
  created_at              timestamptz not null default now()
);

create index if not exists idx_skandi_activity_templates_user_weekday
  on public.skandi_activity_templates(user_id, weekday);

alter table public.skandi_activity_templates enable row level security;

drop policy if exists "Crew manage own skandi activity templates" on public.skandi_activity_templates;
create policy "Crew manage own skandi activity templates"
  on public.skandi_activity_templates for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

alter table public.skandi_external_activities
  add column if not exists avg_heart_rate integer check (avg_heart_rate is null or avg_heart_rate between 30 and 230),
  add column if not exists template_id uuid references public.skandi_activity_templates(id) on delete set null;
