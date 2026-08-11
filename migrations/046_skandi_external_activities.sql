-- Skandi Fit: manual external activity logging (running, cycling, swimming, rowing,
-- walking, other) feeding the muscle recovery engine. Manual entry only (v1) --
-- no HealthKit/Apple Watch integration.

create table if not exists public.skandi_external_activities (
  id             uuid primary key default uuid_generate_v4(),
  user_id        uuid references public.profiles(id) on delete cascade not null,
  activity_type  text not null check (activity_type in
                   ('running','cycling','swimming','rowing','walking','other')),
  performed_at   timestamptz not null default now(),
  duration_min   integer not null check (duration_min between 1 and 600),
  distance_km    numeric(6,2) check (distance_km is null or distance_km between 0 and 500),
  intensity      integer not null check (intensity between 1 and 10), -- RPE 1-10
  note           text,
  created_at     timestamptz not null default now()
);

create index if not exists idx_skandi_external_activities_user_performed
  on public.skandi_external_activities(user_id, performed_at desc);

alter table public.skandi_external_activities enable row level security;

drop policy if exists "Crew manage own skandi external activities" on public.skandi_external_activities;
create policy "Crew manage own skandi external activities"
  on public.skandi_external_activities for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
