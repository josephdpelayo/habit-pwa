-- Skandi Fit: medidas con cinta y fotos de progreso.
--
-- "A bordo no hay manera de pesarme de forma precisa" — una báscula normal no sirve en un
-- barco: el vaivén, la falta de una superficie firme y consistente entre puertos hacen que el
-- peso registrado (skandi_bodyweight_logs, 067) sea ruido más que señal para esta tripulación
-- en particular. La cinta métrica y la cámara sí funcionan a bordo igual que en tierra, así que
-- se vuelven el método principal de seguimiento de composición corporal, no un extra.
--
-- Dos tablas, no una: una medida (números) y una foto (evidencia visual) son dos preguntas
-- distintas — "¿cambió mi cintura?" contra "¿se ve diferente?" — y alguien puede querer
-- registrar una sin la otra el mismo día.

-- ── 1. Medidas con cinta ─────────────────────────────────────────────────────
--
-- Los siete puntos estándar de seguimiento de composición corporal. Todos opcionales (a veces
-- solo se mide cintura) menos que haya AL MENOS uno, que fuerza el trigger de abajo en vez de
-- un check aquí — un check con siete columnas opcionales conectadas por "or" es ilegible y
-- este mismo patrón (mínimo uno de varios) ya se resuelve así en otras tablas de Skandi.

create table if not exists public.skandi_body_measurements (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid references public.profiles(id) on delete cascade not null,
  measured_at  date not null default current_date,
  neck_cm      numeric(5,1) check (neck_cm is null or neck_cm between 15 and 70),
  chest_cm     numeric(5,1) check (chest_cm is null or chest_cm between 40 and 180),
  waist_cm     numeric(5,1) check (waist_cm is null or waist_cm between 40 and 180),
  hip_cm       numeric(5,1) check (hip_cm is null or hip_cm between 40 and 180),
  arm_cm       numeric(5,1) check (arm_cm is null or arm_cm between 12 and 70),
  thigh_cm     numeric(5,1) check (thigh_cm is null or thigh_cm between 20 and 100),
  calf_cm      numeric(5,1) check (calf_cm is null or calf_cm between 15 and 70),
  note         text,
  created_at   timestamptz not null default now(),
  unique(user_id, measured_at)
);

create index if not exists idx_skandi_body_measurements_user_date
  on public.skandi_body_measurements(user_id, measured_at desc);

alter table public.skandi_body_measurements enable row level security;

drop policy if exists "Crew manage own skandi body measurements" on public.skandi_body_measurements;
create policy "Crew manage own skandi body measurements"
  on public.skandi_body_measurements for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.skandi_check_measurement_has_value()
returns trigger
language plpgsql
as $$
begin
  if new.neck_cm is null and new.chest_cm is null and new.waist_cm is null
    and new.hip_cm is null and new.arm_cm is null and new.thigh_cm is null
    and new.calf_cm is null then
    raise exception 'la medida necesita al menos un número';
  end if;
  return new;
end;
$$;

drop trigger if exists skandi_measurement_has_value on public.skandi_body_measurements;
create trigger skandi_measurement_has_value
  before insert or update on public.skandi_body_measurements
  for each row execute function public.skandi_check_measurement_has_value();

-- ── 2. Fotos de progreso ─────────────────────────────────────────────────────
--
-- A diferencia de la medida (un renglón por día, unique), un mismo día puede traer varias
-- fotos — frente, lado, espalda — así que no hay unique aquí. `pose` es de qué ángulo es la
-- foto, para poder comparar la misma pose entre fechas en vez de mezclar frente con espalda.

create table if not exists public.skandi_progress_photos (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid references public.profiles(id) on delete cascade not null,
  taken_at    date not null default current_date,
  pose        text not null default 'frente' check (pose in ('frente','lado','espalda','otro')),
  photo_path  text not null,
  note        text,
  created_at  timestamptz not null default now()
);

create index if not exists idx_skandi_progress_photos_user_date
  on public.skandi_progress_photos(user_id, taken_at desc);

alter table public.skandi_progress_photos enable row level security;

drop policy if exists "Crew manage own skandi progress photos" on public.skandi_progress_photos;
create policy "Crew manage own skandi progress photos"
  on public.skandi_progress_photos for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Privado, igual que skandi-meals (073) y skandi-set-clips (079): una foto de tu cuerpo es
-- tuya y de nadie más, se sirve con signed URL.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'skandi-progress-photos',
  'skandi-progress-photos',
  false,
  10485760, -- 10 MB: la app comprime antes de subir, igual que las fotos de comida
  array['image/jpeg','image/jpg','image/png','image/webp','image/heic']
)
on conflict (id) do nothing;

-- Cada quien manda solo en su carpeta: skandi-progress-photos/{user_id}/{uuid}.jpg
drop policy if exists "Skandi progress photos are per-user" on storage.objects;
create policy "Skandi progress photos are per-user"
  on storage.objects for all
  to authenticated
  using (bucket_id = 'skandi-progress-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'skandi-progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);
