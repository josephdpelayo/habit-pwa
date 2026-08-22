-- Skandi Fit: Strava (Fase 4 del roadmap). El reloj Garmin sincroniza solo a Strava, y de
-- Strava jalamos nosotros: la carrera se registra sola en `skandi_external_activities` y el
-- motor de fatiga la ve sin que nadie teclee nada.
--
-- Por qué Strava y no Garmin directo: el Garmin Connect Developer Program exige entidad legal
-- y rechaza el uso personal (§3.1 de docs/PROYECTO_SKANDI_V2.md). Strava sí es self-service.
--
-- Tres piezas: dónde viven los tokens (nadie más que el servidor los toca), qué columnas
-- necesita una actividad importada para no duplicarse, y la frecuencia cardiaca máxima, que
-- es lo único que convierte unas pulsaciones en un esfuerzo comparable entre personas.

-- ── 1. Tokens de la integración ─────────────────────────────────────────────
-- RLS SIN NINGUNA POLÍTICA, a propósito: con RLS activa y cero políticas, Postgres niega
-- todo select/insert/update/delete a `authenticated`. La única llave que entra aquí es la
-- service-role de las funciones serverless. El cliente jamás ve un access_token, y para
-- saber si está conectado pregunta a skandi_strava_status(), que devuelve lo que sí puede
-- saber y nada más.

create table if not exists public.skandi_integrations (
  user_id       uuid references public.profiles(id) on delete cascade not null,
  provider      text not null default 'strava' check (provider in ('strava')),
  athlete_id    text not null,
  access_token  text not null,
  refresh_token text not null,
  expires_at    timestamptz not null,
  scope         text,
  connected_at  timestamptz not null default now(),
  last_sync_at  timestamptz,
  last_error    text,
  primary key (user_id, provider)
);

-- Un atleta de Strava solo puede estar amarrado a un miembro. Sin esto, el webhook recibe un
-- owner_id y no sabe a quién pertenece la carrera: la ambigüedad se prohíbe en la base, no
-- se resuelve adivinando en el código.
create unique index if not exists idx_skandi_integrations_athlete
  on public.skandi_integrations(provider, athlete_id);

alter table public.skandi_integrations enable row level security;

-- ── 2. La actividad importada ───────────────────────────────────────────────

alter table public.skandi_external_activities
  add column if not exists external_source   text
    check (external_source is null or external_source in ('strava')),
  add column if not exists external_id       text,
  add column if not exists external_type     text,
  add column if not exists elevation_gain_m  numeric(7,1)
    check (elevation_gain_m is null or elevation_gain_m between 0 and 20000),
  add column if not exists max_heart_rate    integer
    check (max_heart_rate is null or max_heart_rate between 30 and 230),
  add column if not exists calories          integer
    check (calories is null or calories between 0 and 20000),
  add column if not exists intensity_source  text not null default 'manual'
    check (intensity_source in ('manual','heart_rate','default'));

comment on column public.skandi_external_activities.external_type is
  'sport_type crudo de Strava (TrailRun, GravelRide...). activity_type es nuestra reducción a seis; esto guarda lo que se perdió al reducir';
comment on column public.skandi_external_activities.intensity_source is
  'de dónde salió intensity: manual = la puso una persona (o el RPE que el atleta capturó en Strava), heart_rate = derivada de %FCmáx, default = no se pudo saber y vale 5 hasta que alguien la corrija';

-- La deduplicación. Es lo único que permite que el webhook y el jalón manual convivan sin
-- pisarse: los dos resuelven contra este índice.
--
-- No lleva `where external_source is not null` aunque solo importe a las filas importadas:
-- en Postgres los NULL son distintos entre sí, así que las capturadas a mano (con las tres
-- columnas en null) no chocan nunca entre ellas. Y un índice parcial no puede ser árbitro de
-- un ON CONFLICT que no repita su predicado, cosa que PostgREST no emite.
create unique index if not exists idx_skandi_external_activities_external
  on public.skandi_external_activities(user_id, external_source, external_id);

create index if not exists idx_skandi_external_activities_source
  on public.skandi_external_activities(user_id, external_source, performed_at desc);

-- ── 3. Lo que el cliente sí puede saber ─────────────────────────────────────
-- Va DESPUÉS de las columnas de arriba y no antes: `skandi_strava_status()` es
-- `language sql`, y Postgres valida ese cuerpo al crearlo (a diferencia de plpgsql, que
-- lo difiere). Creándola primero, el select contra `external_source` falla con 42703
-- porque la columna todavía no existe.
-- Cero filas = no conectado. Nunca devuelve tokens.

create or replace function public.skandi_strava_status()
returns table (
  athlete_id   text,
  scope        text,
  connected_at timestamptz,
  last_sync_at timestamptz,
  last_error   text,
  imported     integer
)
language sql
security definer
set search_path = public
stable
as $$
  select i.athlete_id, i.scope, i.connected_at, i.last_sync_at, i.last_error,
         (select count(*)::int
            from public.skandi_external_activities a
           where a.user_id = i.user_id
             and a.external_source = 'strava')
    from public.skandi_integrations i
   where i.user_id = auth.uid()
     and i.provider = 'strava';
$$;

revoke all on function public.skandi_strava_status() from public;
grant execute on function public.skandi_strava_status() to authenticated;

-- ── 4. Los topes de la captura manual no sirven para importar ───────────────
-- 046 puso duración <= 600 min y distancia <= 500 km pensando en un formulario donde nadie
-- teclea una barbaridad. Importando, un rebase del check no es un error del usuario: es una
-- actividad que desaparece sin que nadie se entere. Se sube el techo a lo que un humano
-- puede hacer de verdad (un día entero, un ultra).

alter table public.skandi_external_activities
  drop constraint if exists skandi_external_activities_duration_min_check;
alter table public.skandi_external_activities
  add constraint skandi_external_activities_duration_min_check
  check (duration_min between 1 and 1440);

alter table public.skandi_external_activities
  drop constraint if exists skandi_external_activities_distance_km_check;
alter table public.skandi_external_activities
  add constraint skandi_external_activities_distance_km_check
  check (distance_km is null or distance_km between 0 and 1000);

-- ── 5. Frecuencia cardiaca máxima ───────────────────────────────────────────
-- 130 bpm no significan lo mismo en dos personas. Sin FCmáx, el motor de recuperación usa
-- bandas absolutas de bpm (que equivalen a suponer FCmáx ≈ 190); con ella, el mismo esfuerzo
-- relativo da el mismo estímulo en cualquier cuerpo.
--
-- Va en su propia tabla y no en `profiles` porque profiles lo lee CUALQUIER usuario
-- autenticado del gimnasio (política "Authenticated users read profiles", migración 007), y
-- esto es un dato de salud del miembro.

create table if not exists public.skandi_settings (
  user_id        uuid primary key references public.profiles(id) on delete cascade,
  max_heart_rate integer check (max_heart_rate is null or max_heart_rate between 120 and 230),
  updated_at     timestamptz not null default now()
);

alter table public.skandi_settings enable row level security;

drop policy if exists "Crew manage own skandi settings" on public.skandi_settings;
create policy "Crew manage own skandi settings"
  on public.skandi_settings for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
