-- Garmin complementa una sesión de fuerza de Skandi; no crea una segunda actividad.
-- Las series/repeticiones/RIR siguen siendo la fuente muscular. Estos campos agregan la
-- duración y las métricas fisiológicas que midió el reloj.

alter table public.skandi_sessions
  add column if not exists duration_source text not null default 'timer'
    check (duration_source in ('timer','manual','garmin')),
  add column if not exists garmin_external_id text,
  add column if not exists garmin_started_at timestamptz,
  add column if not exists garmin_duration_sec integer
    check (garmin_duration_sec is null or garmin_duration_sec between 1 and 86400),
  add column if not exists garmin_avg_heart_rate integer
    check (garmin_avg_heart_rate is null or garmin_avg_heart_rate between 30 and 230),
  add column if not exists garmin_max_heart_rate integer
    check (garmin_max_heart_rate is null or garmin_max_heart_rate between 30 and 230),
  add column if not exists garmin_calories integer
    check (garmin_calories is null or garmin_calories between 0 and 20000),
  add column if not exists garmin_intensity numeric(3,1)
    check (garmin_intensity is null or garmin_intensity between 1 and 10),
  add column if not exists garmin_intensity_source text
    check (garmin_intensity_source is null or garmin_intensity_source in ('manual','heart_rate','default')),
  add column if not exists garmin_device_name text,
  add column if not exists garmin_activity_name text,
  add column if not exists garmin_synced_at timestamptz;

create unique index if not exists idx_skandi_sessions_garmin_activity
  on public.skandi_sessions(user_id, garmin_external_id)
  where garmin_external_id is not null;

comment on column public.skandi_sessions.duration_source is
  'timer = cronómetro Skandi, manual = corrección del usuario (nunca se pisa), garmin = duración del reloj';
comment on column public.skandi_sessions.garmin_external_id is
  'Actividad de fuerza de Intervals.icu/Garmin enlazada a esta sesión; no se inserta en actividades externas para evitar doble fatiga';

