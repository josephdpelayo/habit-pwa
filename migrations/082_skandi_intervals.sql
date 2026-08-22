-- Skandi Fit: Garmin Connect -> Intervals.icu -> Skandi.
--
-- Intervals.icu da a cada atleta una API key personal. Se guarda cifrada por la función
-- serverless y esta tabla no tiene políticas RLS: el navegador no puede leerla ni escribirla.

create table if not exists public.skandi_intervals_credentials (
  user_id            uuid primary key references public.profiles(id) on delete cascade,
  athlete_id          text not null,
  api_key_ciphertext  text not null,
  connected_at        timestamptz not null default now(),
  last_sync_at        timestamptz,
  last_error          text
);

create unique index if not exists idx_skandi_intervals_athlete
  on public.skandi_intervals_credentials(athlete_id);

alter table public.skandi_intervals_credentials enable row level security;

-- 081 creó este check aceptando solamente Strava. Intervals es una segunda procedencia
-- importada y comparte el mismo índice (usuario, fuente, id) para deduplicar.
alter table public.skandi_external_activities
  drop constraint if exists skandi_external_activities_external_source_check;
alter table public.skandi_external_activities
  add constraint skandi_external_activities_external_source_check
  check (external_source is null or external_source in ('strava','intervals'));

comment on table public.skandi_intervals_credentials is
  'Credenciales cifradas de Intervals.icu. RLS sin políticas: solo service-role.';

