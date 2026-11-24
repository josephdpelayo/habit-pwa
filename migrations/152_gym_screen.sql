-- 152 — La pantalla del gym, fase 1: quién está entrenando y qué le toca (docs/PANTALLA_GYM.md).
--
-- La tele (/pantalla) no inicia sesión. Lee todo por UNA función, gym_screen_state(), que
-- pide la llave de esa pantalla: la llave anon de la app es pública (está en el HTML) y sin
-- una segunda llave cualquiera podría preguntar desde su casa quién va al gym hoy y a qué
-- hora. La llave vive en gym_screens.access_key, que ni anon ni los socios pueden leer.
--
-- Nadie sale en la tele hasta que lo activa (Joseph, 24 nov 2026): gym_screen_prefs.visibility
-- nace 'hidden' y una persona sin fila cuenta como 'hidden'. El filtro es del servidor: lo de
-- quien no lo activó nunca sale de la base; de esas personas solo se cuenta cuántas hay.
--
-- La rutina se manda en crudo (la copia de la sesión, la rutina, lo cambiado hoy y las series)
-- y la arma la tele con HabitScreen.effectiveExercises (habit-screen.js), que
-- scripts/check-screen.js compara con sessionExerciseList de crew.html: la regla de «qué
-- ejercicios son» vive una sola vez en JavaScript. Lo que sí se resuelve aquí es qué rutina
-- toca hoy cuando la semana aún no se estampó (el estampado corre desde el teléfono y quien
-- reservó sin abrir la app no tiene fila): la misma regla que ensure_coaching_week_from_template
-- (programa activo con fecha → su semana del ciclo; si no, la semana base).
--
-- Realtime no le avisa a anon de cambios en tablas que no puede leer. gym_screen_pings es una
-- fila sin datos personales que sí puede leer, y la tocan triggers de lo que cambia la tele;
-- la tele oye «algo cambió» y vuelve a pedir el estado.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Las pantallas
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.gym_screens (
  id          text primary key check (id ~ '^[a-z0-9-]{1,32}$'),
  name        text not null default 'Pantalla del gym',
  access_key  text not null default replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
  -- 'off' hasta que la tele exista: con 'off' la app no invita a nadie ni enseña el ajuste.
  mode        text not null default 'off' check (mode in ('on', 'off')),
  lang        text not null default 'es' check (lang in ('es', 'en')),
  updated_at  timestamptz not null default now()
);
insert into public.gym_screens (id) values ('main') on conflict (id) do nothing;

alter table public.gym_screens enable row level security;
-- Supabase da todo a anon y authenticated en cada tabla nueva; se quita y se devuelve por
-- columnas, sin access_key. Los cambios del admin van por RPC (sección 5).
revoke all on public.gym_screens from public, anon, authenticated;
grant select (id, name, mode, lang, updated_at) on public.gym_screens to anon, authenticated;
drop policy if exists "Anyone reads gym screens" on public.gym_screens;
create policy "Anyone reads gym screens" on public.gym_screens
  for select to anon, authenticated using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. «Algo cambió»: lo único que la tele escucha por Realtime
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.gym_screen_pings (
  screen_id     text primary key references public.gym_screens(id) on delete cascade,
  bumped_at     timestamptz not null default now(),
  -- El botón «Recargar tele» del control lo sube; la tele se recarga al verlo cambiar.
  reload_nonce  integer not null default 0
);
insert into public.gym_screen_pings (screen_id) values ('main') on conflict (screen_id) do nothing;

alter table public.gym_screen_pings enable row level security;
revoke all on public.gym_screen_pings from public, anon, authenticated;
grant select on public.gym_screen_pings to anon, authenticated;
drop policy if exists "Anyone reads gym screen pings" on public.gym_screen_pings;
create policy "Anyone reads gym screen pings" on public.gym_screen_pings
  for select to anon, authenticated using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Lo que cada quien decidió enseñar
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.gym_screen_prefs (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  -- hidden: no salir · name: nombre y hora · routine: nombre, hora y rutina
  visibility  text not null default 'hidden' check (visibility in ('hidden', 'name', 'routine')),
  -- Respondió la invitación (cualquier respuesta, «Ahora no» incluido): no se le vuelve a hacer.
  asked_at    timestamptz,
  updated_at  timestamptz not null default now()
);

alter table public.gym_screen_prefs enable row level security;
revoke all on public.gym_screen_prefs from public, anon, authenticated;
grant select, insert, update on public.gym_screen_prefs to authenticated;
drop policy if exists "Own gym screen prefs read" on public.gym_screen_prefs;
create policy "Own gym screen prefs read" on public.gym_screen_prefs
  for select to authenticated using (user_id = auth.uid() or public.is_habit_admin());
drop policy if exists "Own gym screen prefs insert" on public.gym_screen_prefs;
create policy "Own gym screen prefs insert" on public.gym_screen_prefs
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "Own gym screen prefs update" on public.gym_screen_prefs;
create policy "Own gym screen prefs update" on public.gym_screen_prefs
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.gym_screen_prefs_touch()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists gym_screen_prefs_touch on public.gym_screen_prefs;
create trigger gym_screen_prefs_touch before update on public.gym_screen_prefs
for each row execute function public.gym_screen_prefs_touch();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Los avisos a la tele
-- ─────────────────────────────────────────────────────────────────────────────
-- Por sentencia, no por fila: marcar todas las series de un ejercicio es un solo aviso. Solo
-- se tocan las pantallas encendidas, y un error aquí nunca tumba lo que lo disparó: una serie
-- que no se guarda porque la tele no se enteró sería un pésimo cambio.
create or replace function public.gym_screen_bump()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    if tg_table_name = 'gym_screens' then
      update public.gym_screen_pings set bumped_at = now();
    else
      update public.gym_screen_pings p set bumped_at = now()
        from public.gym_screens s
       where s.id = p.screen_id and s.mode = 'on';
    end if;
  exception when others then
    null;
  end;
  return null;
end;
$$;

drop trigger if exists gym_screen_bump on public.bookings;
create trigger gym_screen_bump after insert or update or delete on public.bookings
for each statement execute function public.gym_screen_bump();
drop trigger if exists gym_screen_bump on public.booking_guest_passes;
create trigger gym_screen_bump after insert or update or delete on public.booking_guest_passes
for each statement execute function public.gym_screen_bump();
drop trigger if exists gym_screen_bump on public.coaching_schedule;
create trigger gym_screen_bump after insert or update or delete on public.coaching_schedule
for each statement execute function public.gym_screen_bump();
drop trigger if exists gym_screen_bump on public.coaching_session_sets;
create trigger gym_screen_bump after insert or update or delete on public.coaching_session_sets
for each statement execute function public.gym_screen_bump();
drop trigger if exists gym_screen_bump on public.gym_screen_prefs;
create trigger gym_screen_bump after insert or update or delete on public.gym_screen_prefs
for each statement execute function public.gym_screen_bump();
drop trigger if exists gym_screen_bump on public.gym_screens;
create trigger gym_screen_bump after update on public.gym_screens
for each statement execute function public.gym_screen_bump();

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Lo que lee la tele
-- ─────────────────────────────────────────────────────────────────────────────
-- Solo lo que la tele pinta de cada ejercicio: ni notas del coach, ni videos, ni cues.
create or replace function public.gym_screen_trim(p jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'id', e->'id', '_exKey', e->'_exKey', 'ex_key', e->'ex_key',
           'replaces', e->'replaces', 'removed', e->'removed',
           'name', e->'name', 'sets', e->'sets', 'reps', e->'reps', 'repsType', e->'repsType',
           'rest', e->'rest', 'metricType', e->'metricType', 'supersetGroup', e->'supersetGroup'
         )) order by t.o), '[]'::jsonb)
  from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end)
       with ordinality as t(e, o)
  where jsonb_typeof(t.e) = 'object';
$$;

-- «Ana P.» del nombre del perfil. Sin nombre, vacío: la tele pone «Socio».
create or replace function public.gym_screen_short_name(p_name text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when coalesce(btrim(p_name), '') = '' then ''
    else initcap(split_part(regexp_replace(btrim(p_name), '\s+', ' ', 'g'), ' ', 1))
      || coalesce(' ' || upper(left(nullif(split_part(regexp_replace(btrim(p_name), '\s+', ' ', 'g'), ' ', 2), ''), 1)) || '.', '')
  end;
$$;

-- Qué rutina tiene hoy una persona. La sesión del día si existe (en curso, luego por hacer,
-- luego hecha); si hay fila pero solo 'skipped', ese día descansa; si no hay ninguna, la
-- semana todavía no se estampó y se resuelve como lo haría ensure_coaching_week_from_template.
create or replace function public.gym_screen_routine(p_uid uuid, p_today date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row     public.coaching_schedule%rowtype;
  v_any     boolean;
  v_monday  date := p_today - (extract(isodow from p_today)::int - 1);
  v_program uuid;
  v_index   integer := 0;
  v_slot    record;
begin
  select * into v_row
  from public.coaching_schedule s
  where s.user_id = p_uid and s.ds = p_today and s.status in ('in_progress', 'scheduled', 'done')
  order by case s.status when 'in_progress' then 0 when 'scheduled' then 1 else 2 end,
           s.completed_at desc nulls last, s.created_at desc
  limit 1;

  if found then
    return jsonb_build_object(
      'source', 'session',
      'title', coalesce(nullif(btrim(v_row.title), ''), v_row.board_name),
      'color', v_row.board_color,
      'status', v_row.status,
      'board_id', v_row.board_id,
      'started_at', v_row.started_at,
      'completed_at', v_row.completed_at,
      -- Para el cronómetro de la tele: lo mismo que wsElapsedSec en la app.
      'paused_at', v_row.paused_at,
      'paused_seconds', coalesce(v_row.paused_seconds, 0),
      'exercises', public.gym_screen_trim(case
        when jsonb_array_length(coalesce(v_row.exercise_snapshot, '[]'::jsonb)) > 0 then v_row.exercise_snapshot
        else (select b.exercises from public.boards b where b.id = v_row.board_id) end),
      'overlay', public.gym_screen_trim(v_row.session_exercises),
      'sets', (select coalesce(jsonb_agg(jsonb_build_object(
                 'k', c.ex_key, 'i', c.set_idx, 'd', c.done, 't', c.reps_target,
                 'r', c.actual_reps, 'w', c.weight, 's', c.actual_seconds) order by c.ex_key, c.set_idx), '[]'::jsonb)
               from public.coaching_session_sets c where c.schedule_id = v_row.id)
    );
  end if;

  select exists(select 1 from public.coaching_schedule s where s.user_id = p_uid and s.ds = p_today) into v_any;
  if v_any then return null; end if;

  select p.id into v_program
  from public.coaching_programs p
  where p.user_id = p_uid and p.is_active and p.start_date is not null
  limit 1;
  if v_program is not null then
    v_index := public.coaching_program_week_index(v_program, v_monday);
    if v_index = 0 then v_program := null; end if;
  end if;

  select w.board_id, w.board_name, w.board_color into v_slot
  from public.coaching_week_slots(p_uid, v_program, v_index) w
  where w.dow = (p_today - v_monday) and w.board_id is not null
  limit 1;
  if not found then return null; end if;

  return jsonb_build_object(
    'source', 'plan',
    'title', v_slot.board_name,
    'color', v_slot.board_color,
    'status', 'planned',
    'board_id', v_slot.board_id,
    'exercises', public.gym_screen_trim((select b.exercises from public.boards b where b.id = v_slot.board_id)),
    'overlay', '[]'::jsonb,
    'sets', '[]'::jsonb
  );
end;
$$;

-- El estado completo de una pantalla. Con la llave equivocada no dice nada más que eso.
create or replace function public.gym_screen_state(p_screen text, p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_screen public.gym_screens%rowtype;
  v_now    timestamptz := now();
  v_today  date := (now() at time zone 'America/Mazatlan')::date;
  v_people jsonb;
  v_hidden integer;
begin
  select * into v_screen from public.gym_screens where id = p_screen;
  if not found or p_key is null or v_screen.access_key <> p_key then
    return jsonb_build_object('ok', false, 'error', 'KEY', 'now', v_now);
  end if;

  if v_screen.mode = 'off' then
    return jsonb_build_object('ok', true, 'mode', 'off', 'name', v_screen.name, 'lang', v_screen.lang,
      'now', v_now, 'today', v_today, 'people', '[]'::jsonb, 'hidden_now', 0);
  end if;

  with att as (
    select b.user_id, b.ds, b.start_idx, b.slots_used
    from public.bookings b
    where b.ds = v_today and b.status <> 'cancelled'
    union all
    -- Los invitados de una sesión grupal tienen cuenta y su propia rutina.
    select g.guest_user_id, b.ds, b.start_idx, b.slots_used
    from public.booking_guest_passes g
    join public.bookings b on b.id = g.booking_id
    where b.ds = v_today and b.status <> 'cancelled' and g.status = 'active'
  ), win as (
    select a.user_id,
           public.habit_slot_start(a.ds, a.start_idx) as start_at,
           public.habit_slot_start(a.ds, a.start_idx + greatest(coalesce(a.slots_used, 3), 1)) as end_at
    from att a
    where a.user_id is not null
  ), cur as (
    -- Una sola fila por persona: su próxima reserva que no ha terminado.
    select distinct on (w.user_id) w.user_id, w.start_at, w.end_at
    from win w
    where w.end_at > v_now
    order by w.user_id, w.start_at
  ), vis as (
    select c.*, coalesce(p.visibility, 'hidden') as visibility
    from cur c
    left join public.gym_screen_prefs p on p.user_id = c.user_id
  )
  select
    count(*) filter (where v.visibility = 'hidden' and v_now >= v.start_at - interval '10 minutes'),
    coalesce(jsonb_agg(jsonb_build_object(
      -- Una llave que no es el id de la persona y cambia cada día: la tele solo la usa para
      -- no repintar lo que no cambió.
      'key', left(md5(v.user_id::text || v_today::text), 12),
      'name', public.gym_screen_short_name(pr.name),
      'start_at', v.start_at,
      'end_at', v.end_at,
      'visibility', v.visibility,
      'routine', case when v.visibility = 'routine' then public.gym_screen_routine(v.user_id, v_today) end
    ) order by v.start_at, pr.name) filter (where v.visibility <> 'hidden'), '[]'::jsonb)
  into v_hidden, v_people
  from vis v
  join public.profiles pr on pr.id = v.user_id;

  return jsonb_build_object('ok', true, 'mode', v_screen.mode, 'name', v_screen.name, 'lang', v_screen.lang,
    'now', v_now, 'today', v_today, 'people', v_people, 'hidden_now', coalesce(v_hidden, 0));
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. El control del admin (/pantalla?control)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.gym_screen_admin(p_screen text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_screen public.gym_screens%rowtype;
begin
  if auth.uid() is null or not public.is_habit_admin() then
    raise exception 'NOT_ADMIN';
  end if;
  select * into v_screen from public.gym_screens where id = p_screen;
  if not found then return null; end if;
  return jsonb_build_object('id', v_screen.id, 'name', v_screen.name, 'mode', v_screen.mode,
    'lang', v_screen.lang, 'access_key', v_screen.access_key, 'updated_at', v_screen.updated_at);
end;
$$;

-- p_mode / p_lang null = no cambiar; p_rotate_key cambia la llave (la tele vieja deja de ver);
-- p_reload hace que la tele se recargue.
create or replace function public.gym_screen_configure(
  p_screen text, p_mode text default null, p_lang text default null,
  p_rotate_key boolean default false, p_reload boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_habit_admin() then
    raise exception 'NOT_ADMIN';
  end if;
  update public.gym_screens set
    mode = coalesce(p_mode, mode),
    lang = coalesce(p_lang, lang),
    access_key = case when p_rotate_key
      then replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')
      else access_key end,
    updated_at = now()
  where id = p_screen;
  if not found then raise exception 'NO_SCREEN'; end if;
  if p_reload then
    update public.gym_screen_pings set reload_nonce = reload_nonce + 1, bumped_at = now()
    where screen_id = p_screen;
  end if;
  return public.gym_screen_admin(p_screen);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Permisos de las funciones (lección de la 124 y la 154)
-- ─────────────────────────────────────────────────────────────────────────────
-- Toda función nace con EXECUTE para PUBLIC y, en Supabase, además para anon y authenticated
-- explícitos: se quitan los tres y se da solo lo que toca.
revoke all on function public.gym_screen_prefs_touch() from public, anon, authenticated;
revoke all on function public.gym_screen_bump() from public, anon, authenticated;
revoke all on function public.gym_screen_trim(jsonb) from public, anon, authenticated;
revoke all on function public.gym_screen_short_name(text) from public, anon, authenticated;
revoke all on function public.gym_screen_routine(uuid, date) from public, anon, authenticated;
revoke all on function public.gym_screen_state(text, text) from public, anon, authenticated;
revoke all on function public.gym_screen_admin(text) from public, anon, authenticated;
revoke all on function public.gym_screen_configure(text, text, text, boolean, boolean) from public, anon, authenticated;

grant execute on function public.gym_screen_state(text, text) to anon, authenticated;
grant execute on function public.gym_screen_admin(text) to authenticated;
grant execute on function public.gym_screen_configure(text, text, text, boolean, boolean) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Realtime
-- ─────────────────────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'gym_screen_pings') then
      alter publication supabase_realtime add table public.gym_screen_pings;
    end if;
  end if;
end $$;

commit;
