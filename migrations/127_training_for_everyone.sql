-- HABIT para todos, Fase 0 (docs/HABIT_PARA_TODOS.md): Entrenar abierto a cualquier cuenta.
--
-- Hasta aquí toda cuenta de HABIT era un socio del gym, con o sin plan vigente. Desde ahora
-- alguien puede registrarse para entrenar por su cuenta —en otro gym, en casa, en un parque— y
-- eso tiene que quedar dicho en la base por tres razones: el admin no debe recibir un push de
-- "Nuevo socio" por cada descarga, sus conteos no deben llamar socio a quien nunca pisó
-- Mazatlán, y las rutinas básicas del gym (pensadas con su equipo) no le sirven a quien
-- entrena con dos mancuernas.
--
--   1. profiles.joined_as ('gym' | 'app'): por dónde entró. No es un permiso. Lo que deja
--      reservar y abrir la puerta sigue siendo la membresía (book_my_slot, 120), así que una
--      cuenta 'app' que compra un plan es socia como cualquiera, y su joined_as sigue diciendo
--      que llegó por la app (es la métrica "app → gym"). Se llama joined_as y no
--      signup_source para no confundirla con profiles.source (055), que dice qué app creó el
--      perfil (habit / skandi).
--   2. training_profiles: objetivo, nivel, equipo y días del onboarding. Tabla privada, no
--      columnas en profiles: es el mismo criterio que skandi_settings (081) — otros socios
--      leen profiles por profile_cards, y esto no es de nadie más.
--   3. El perfil nace con su joined_as. Lo crea handle_new_user (trigger sobre auth.users,
--      117) con los metadatos del signUp, antes de que la app llegue a llamar
--      ensure_habit_profile — que solo es el respaldo si ese trigger falló. Los dos lo leen,
--      y el trigger de rutinas básicas (122), que corre justo después del insert, ya no se
--      las asigna a quien entra como 'app': ellos eligen programa (Fase 1).
--      Leer joined_as de raw_user_meta_data está bien aunque lo controle quien se registra
--      (la lección de la 117 con `role`): joined_as no autoriza nada.
--
-- Orden de despliegue: ANTES de publicar la app nueva. No cambia nada para la app publicada
-- (su llamada de dos argumentos a ensure_habit_profile sigue funcionando y el perfil sin
-- joined_as es 'gym', como hoy). Al revés también funciona —la app nueva cae al
-- ensure_habit_profile de dos argumentos y no guarda el onboarding—, pero cada cuenta
-- "Por mi cuenta" creada en ese hueco queda como 'gym' y con las rutinas básicas asignadas.
--
-- Requiere la 117 (is_habit_admin, ensure_habit_profile) y la 122 (el trigger que se extiende).

begin;

do $$
begin
  if to_regprocedure('public.is_habit_admin()') is null then
    raise exception 'Falta la migración 117 (public.is_habit_admin). Córrela antes que esta.';
  end if;
  if to_regprocedure('public.default_member_board_ids()') is null then
    raise exception 'Falta la migración 122 (default_member_board_ids). Córrela antes que esta.';
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Por dónde entró
-- ─────────────────────────────────────────────────────────────────────────────
-- Todo perfil que ya existe es del gym: hasta hoy no había otra forma de entrar.
alter table public.profiles
  add column if not exists joined_as text not null default 'gym';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_joined_as_check' and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_joined_as_check check (joined_as in ('gym', 'app'));
  end if;
end $$;

create index if not exists idx_profiles_joined_as on public.profiles(joined_as);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. El onboarding
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.training_profiles (
  user_id        uuid primary key references public.profiles(id) on delete cascade,
  goal           text check (goal in ('fuerza','masa','perder_grasa','resistencia','calistenia','salud')),
  level          text check (level in ('principiante','intermedio','avanzado')),
  equipment      text[] not null default '{}'
    check (equipment <@ array['gym_completo','mancuernas','barra_dominadas','peso_corporal','ligas','caminadora']::text[]),
  days_per_week  smallint check (days_per_week between 1 and 7),
  disciplines    text[] not null default '{}'
    check (disciplines <@ array['pesas','funcional','calistenia','carrera','hyrox']::text[]),
  onboarded_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table public.training_profiles enable row level security;

drop policy if exists "Users manage own training profile" on public.training_profiles;
create policy "Users manage own training profile"
  on public.training_profiles for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- El admin lo lee para métricas y para que el coach sepa con qué equipo cuenta un cliente.
-- Escribirlo es del socio.
drop policy if exists "Admin reads training profiles" on public.training_profiles;
create policy "Admin reads training profiles"
  on public.training_profiles for select
  using (public.is_habit_admin());

-- Supabase le da a anon todo sobre las tablas nuevas de public; la RLS ya lo frena (sin
-- auth.uid() ninguna política pasa), pero no hay razón para que lo tenga.
revoke all on table public.training_profiles from anon;
grant select, insert, update, delete on table public.training_profiles to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Crear el perfil diciendo por dónde entró
-- ─────────────────────────────────────────────────────────────────────────────
-- Cuerpo de la 117 tal cual (role siempre 'user', source por metadatos), más joined_as.
-- El trigger on_auth_user_created que la llama no cambia.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  loop
    v_code := lpad(floor(random()*9000+1000)::text, 4, '0');
    exit when not exists(select 1 from public.profiles where access_code = v_code);
  end loop;

  insert into public.profiles (id, name, phone, role, access_code, source, joined_as)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)),
    new.raw_user_meta_data->>'phone',
    'user',
    v_code,
    case when new.raw_user_meta_data->>'app' = 'skandi' then 'skandi' else 'habit' end,
    case when new.raw_user_meta_data->>'joined_as' = 'app' then 'app' else 'gym' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Se borra la versión de dos argumentos en vez de sumar una sobrecarga: con las dos, una
-- llamada con (p_name, p_phone) casa con ambas y Postgres contesta "function is not unique".
-- La app publicada llama con dos argumentos y sigue funcionando: el tercero tiene default.
drop function if exists public.ensure_habit_profile(text, text);

create or replace function public.ensure_habit_profile(
  p_name text,
  p_phone text default null,
  p_joined_as text default 'gym'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_code text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if exists(select 1 from public.profiles where id = auth.uid()) then return; end if;
  loop
    v_code := lpad(floor(random() * 9000 + 1000)::text, 4, '0');
    exit when not exists(select 1 from public.profiles where access_code = v_code);
  end loop;
  insert into public.profiles(id, name, phone, role, access_code, source, joined_as)
  values(auth.uid(), coalesce(nullif(trim(p_name), ''), 'Socio'), nullif(trim(p_phone), ''),
         'user', v_code, 'habit',
         case when p_joined_as = 'app' then 'app' else 'gym' end)
  on conflict(id) do nothing;
end;
$$;

-- Lección de la 124: revocar a public no le quita EXECUTE a anon en Supabase.
revoke all on function public.ensure_habit_profile(text, text, text) from public, anon;
grant execute on function public.ensure_habit_profile(text, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Rutinas básicas solo para quien entra por el gym
-- ─────────────────────────────────────────────────────────────────────────────
-- Cuerpo de la 122 tal cual, más la condición de joined_as. El trigger que la llama no
-- cambia (after insert on profiles), así que no se vuelve a crear.
create or replace function public.assign_default_member_boards_on_profile_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role = 'user'
     and coalesce(new.source, 'habit') = 'habit'
     and coalesce(new.joined_as, 'gym') = 'gym' then
    begin
      insert into public.board_assignments (board_id, user_id)
      select d.board_id, new.id
      from public.default_member_board_ids() d
      on conflict do nothing;
    exception when others then
      raise warning 'No se asignaron las rutinas básicas a %: %', new.id, sqlerrm;
    end;
  end if;
  return new;
end;
$$;

commit;
