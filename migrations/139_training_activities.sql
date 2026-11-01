-- 139 · Entrenos de fuera de la app (HABIT Crew → Actividad)
--
-- Correr, bici, nadar, caminar, fuerza en otro gym, una clase de cardio: lo que entrenas sin
-- abrir la hoja de entreno. Junto con los entrenos de la app (coaching_schedule, status
-- 'done') llenan la sección Actividad, y cada uno se comparte como sticker
-- (docs/HISTORIAS_INSTAGRAM.md, docs/HABIT_PARA_TODOS.md).
--
-- Hoy se registran a mano. `source` + `external_id` dejan lugar para importarlos (Strava,
-- después Apple Salud con la app nativa) sin otra tabla: el índice único es normal, no
-- parcial, porque un índice parcial no puede arbitrar el `on conflict` que manda PostgREST, y
-- los NULL son distintos entre sí, así que lo registrado a mano nunca choca (misma lección que
-- skandi_external_activities, 081).
--
-- Es privada: cada quien ve, corrige y borra lo suyo. Compartir es el sticker, no la tabla.

create table if not exists public.training_activities (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind          text not null
                check (kind in ('run','bike','swim','walk','strength','cardio','yoga','sport','other')),
  title         text check (title is null or char_length(title) <= 80),
  ds            date not null,
  duration_sec  integer check (duration_sec is null or duration_sec between 60 and 86400),
  distance_m    integer check (distance_m is null or distance_m between 1 and 1000000),
  elevation_m   integer check (elevation_m is null or elevation_m between 0 and 20000),
  avg_hr        smallint check (avg_hr is null or avg_hr between 30 and 250),
  kcal          integer check (kcal is null or kcal between 0 and 20000),
  effort        smallint check (effort is null or effort between 1 and 10),
  notes         text check (notes is null or char_length(notes) <= 500),
  source        text not null default 'manual'
                check (source in ('manual','strava','apple_health','garmin')),
  external_id   text,
  external_type text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- Sin tiempo ni distancia no hay nada que contar (ni que poner en un sticker).
  constraint training_activities_has_measure check (duration_sec is not null or distance_m is not null)
);

create unique index if not exists training_activities_external_uidx
  on public.training_activities (user_id, source, external_id);
create index if not exists training_activities_user_ds_idx
  on public.training_activities (user_id, ds desc);

create or replace function public.training_activities_touch()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists training_activities_touch on public.training_activities;
create trigger training_activities_touch
  before update on public.training_activities
  for each row execute function public.training_activities_touch();

alter table public.training_activities enable row level security;

drop policy if exists "training_activities: ver lo propio" on public.training_activities;
create policy "training_activities: ver lo propio"
  on public.training_activities for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "training_activities: registrar lo propio" on public.training_activities;
create policy "training_activities: registrar lo propio"
  on public.training_activities for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "training_activities: corregir lo propio" on public.training_activities;
create policy "training_activities: corregir lo propio"
  on public.training_activities for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "training_activities: borrar lo propio" on public.training_activities;
create policy "training_activities: borrar lo propio"
  on public.training_activities for delete to authenticated
  using (user_id = auth.uid());

-- Supabase da permisos a `anon` en cada tabla nueva de public; la RLS ya lo deja sin filas,
-- pero no hay nada aquí que alguien sin sesión deba poder pedir.
revoke all on table public.training_activities from anon;
grant select, insert, update, delete on table public.training_activities to authenticated;
