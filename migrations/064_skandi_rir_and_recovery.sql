-- Skandi Fit: RIR per set + two recovery-report fields, per Plan_Hibrido_Final_v3.
-- The plan bases all strength/hypertrophy progression decisions on RIR 1-2 per compound
-- (see "Progresion: que debe mejorar y cuando NO subir carga") — skandi_sets tracked
-- weight_kg/reps/seconds but had no field for it. The recovery section of the plan also
-- calls for sleep and whether today underperformed because of the prior session; neither
-- had a home on skandi_sessions.report_*.

alter table public.skandi_sets
  add column if not exists rir integer check (rir is null or rir between 0 and 10);

alter table public.skandi_sessions
  add column if not exists report_sleep_hours numeric(3,1) check (report_sleep_hours is null or report_sleep_hours between 0 and 24),
  add column if not exists report_felt_worse boolean not null default false;
