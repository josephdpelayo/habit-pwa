-- 153 — La pantalla del gym, fase 2: pasar tu entreno a la pantalla (docs/PANTALLA_GYM.md).
--
-- La 152 ya enseña la rutina de quien lo activó y las series que lleva, porque eso está en la
-- base. Lo que solo sabe el teléfono es **qué serie está haciendo ahora y cuánto le queda de
-- descanso**. Transmitir es que el teléfono mande eso mientras dura el entreno:
-- gym_screen_casts, una fila por persona, que solo se escribe por RPC.
--
-- Reglas que decide el servidor, no el teléfono:
--   · Solo con el entreno propio en curso, de hoy, y con una reserva que está corriendo (desde
--     10 min antes hasta 15 min después del final). Un admin no la necesita (los coaches).
--     Una cuenta solo de Crew no tiene reservas, así que no puede transmitir.
--   · Máximo 4 por pantalla: el cupo del gym.
--   · Transmitir se elige en cada entreno y es aparte de la preferencia de Perfil: quien
--     transmite sale en la tele aunque su preferencia sea 'hidden', y solo mientras transmite.
--   · Termina sola: un trigger la borra cuando el entreno deja 'in_progress' (también desde
--     otro aparato, o cuando la cola sin conexión del teléfono sube el cierre tarde), y un
--     pg_cron cada 5 min borra lo vencido. expires_at = el menor de (último aviso + 20 min,
--     fin de la reserva + 15 min). 20 min y no 2: el teléfono se bloquea entre series y una
--     PWA dormida no avisa; la tele atenúa la tarjeta («sin señal») a los 90 s sin noticias.
--   · Lo que manda el teléfono son segundos que faltan, no horas: el servidor sella
--     rest_end_at = now() + faltan, así el reloj del teléfono y el de la tele no tienen que
--     coincidir.
-- gym_screens.casting es el interruptor del staff para apagar las transmisiones sin apagar la
-- tele.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. El interruptor
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.gym_screens add column if not exists casting boolean not null default true;
grant select (casting) on public.gym_screens to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Las transmisiones
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.gym_screen_casts (
  user_id         uuid primary key references public.profiles(id) on delete cascade,
  screen_id       text not null references public.gym_screens(id) on delete cascade,
  schedule_id     uuid not null references public.coaching_schedule(id) on delete cascade,
  -- La serie que toca: ex_key + set_idx, la misma llave que coaching_session_sets.
  focus_key       text,
  focus_idx       integer,
  rest_end_at     timestamptz,
  -- Con el entreno en pausa el descanso se congela: los segundos que faltaban.
  rest_frozen_s   integer,
  rest_total_s    integer,
  paused          boolean not null default false,
  booking_end_at  timestamptz,
  started_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  expires_at      timestamptz not null
);
create index if not exists gym_screen_casts_screen on public.gym_screen_casts (screen_id, expires_at);

alter table public.gym_screen_casts enable row level security;
revoke all on public.gym_screen_casts from public, anon, authenticated;
-- El teléfono solo lee la suya (para saber, al volver a abrir la app, si seguía transmitiendo).
grant select on public.gym_screen_casts to authenticated;
drop policy if exists "Own gym screen cast read" on public.gym_screen_casts;
create policy "Own gym screen cast read" on public.gym_screen_casts
  for select to authenticated using (user_id = auth.uid());

drop trigger if exists gym_screen_bump on public.gym_screen_casts;
create trigger gym_screen_bump after insert or update or delete on public.gym_screen_casts
for each statement execute function public.gym_screen_bump();

-- El fin de la reserva que permite transmitir ahora mismo, o null si no hay.
create or replace function public.gym_screen_booking_end(p_uid uuid)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  with mine as (
    select b.ds, b.start_idx, b.slots_used from public.bookings b
    where b.user_id = p_uid and b.status <> 'cancelled'
      and b.ds between (now() at time zone 'America/Mazatlan')::date - 1 and (now() at time zone 'America/Mazatlan')::date
    union all
    select b.ds, b.start_idx, b.slots_used from public.booking_guest_passes g
    join public.bookings b on b.id = g.booking_id
    where g.guest_user_id = p_uid and g.status = 'active' and b.status <> 'cancelled'
      and b.ds between (now() at time zone 'America/Mazatlan')::date - 1 and (now() at time zone 'America/Mazatlan')::date
  )
  select max(public.habit_slot_start(m.ds, m.start_idx + greatest(coalesce(m.slots_used, 3), 1)))
  from mine m
  where now() >= public.habit_slot_start(m.ds, m.start_idx) - interval '10 minutes'
    and now() <  public.habit_slot_start(m.ds, m.start_idx + greatest(coalesce(m.slots_used, 3), 1)) + interval '15 minutes';
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Empezar, avisar, terminar
-- ─────────────────────────────────────────────────────────────────────────────
-- Devuelve {ok:true} o {ok:false, error:CÓDIGO}; los códigos los traduce habit-screen.js.
create or replace function public.start_gym_cast(p_schedule uuid, p_screen text default 'main')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_row    public.coaching_schedule%rowtype;
  v_screen public.gym_screens%rowtype;
  v_end    timestamptz;
  v_admin  boolean;
  v_others integer;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'error', 'NO_AUTH'); end if;

  select * into v_screen from public.gym_screens where id = p_screen;
  if not found or v_screen.mode <> 'on' or not v_screen.casting then
    return jsonb_build_object('ok', false, 'error', 'SCREEN_OFF');
  end if;

  select * into v_row from public.coaching_schedule where id = p_schedule;
  if not found or v_row.user_id <> v_uid or v_row.status <> 'in_progress'
     or v_row.ds <> (now() at time zone 'America/Mazatlan')::date then
    return jsonb_build_object('ok', false, 'error', 'NO_SESSION');
  end if;

  v_admin := public.is_habit_admin();
  v_end := public.gym_screen_booking_end(v_uid);
  if v_end is null and not v_admin then
    return jsonb_build_object('ok', false, 'error', 'NO_BOOKING');
  end if;

  -- Cuántos transmiten ya en esa pantalla, sin contar a esta persona (puede estar
  -- retomando la suya). El candado evita que dos lleguen a la vez al quinto lugar.
  perform pg_advisory_xact_lock(hashtext('gym_screen_casts:' || p_screen));
  select count(*) into v_others from public.gym_screen_casts
  where screen_id = p_screen and expires_at > now() and user_id <> v_uid;
  if v_others >= 4 then return jsonb_build_object('ok', false, 'error', 'SCREEN_FULL'); end if;

  insert into public.gym_screen_casts (user_id, screen_id, schedule_id, booking_end_at, started_at, updated_at, expires_at)
  values (v_uid, p_screen, p_schedule, v_end, now(), now(),
          least(now() + interval '20 minutes', coalesce(v_end + interval '15 minutes', now() + interval '20 minutes')))
  on conflict (user_id) do update set
    screen_id = excluded.screen_id, schedule_id = excluded.schedule_id, booking_end_at = excluded.booking_end_at,
    focus_key = null, focus_idx = null, rest_end_at = null, rest_frozen_s = null, rest_total_s = null,
    paused = false, started_at = now(), updated_at = now(), expires_at = excluded.expires_at;

  return jsonb_build_object('ok', true);
end;
$$;

-- Lo que el teléfono sabe y la base no. Devuelve false si ya no hay transmisión (venció, se
-- cerró el entreno o el staff la apagó): el teléfono deja de mandar.
create or replace function public.update_gym_cast(
  p_focus_key text, p_focus_idx integer, p_rest_remaining_s integer, p_rest_total_s integer, p_paused boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_rest integer := least(greatest(coalesce(p_rest_remaining_s, 0), 0), 3600);
begin
  if v_uid is null then return false; end if;
  update public.gym_screen_casts c set
    focus_key     = case when p_focus_key is null or length(p_focus_key) > 200 then null else p_focus_key end,
    focus_idx     = case when p_focus_idx between 0 and 200 then p_focus_idx end,
    paused        = coalesce(p_paused, false),
    rest_end_at   = case when v_rest > 0 and not coalesce(p_paused, false) then now() + make_interval(secs => v_rest) end,
    rest_frozen_s = case when v_rest > 0 and coalesce(p_paused, false) then v_rest end,
    rest_total_s  = case when v_rest > 0 then least(greatest(coalesce(p_rest_total_s, v_rest), v_rest), 3600) end,
    updated_at    = now(),
    expires_at    = least(now() + interval '20 minutes',
                          coalesce(c.booking_end_at + interval '15 minutes', now() + interval '20 minutes'))
  where c.user_id = v_uid and c.expires_at > now();
  return found;
end;
$$;

create or replace function public.stop_gym_cast()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.gym_screen_casts where user_id = auth.uid();
$$;

-- El entreno terminó (o se canceló y volvió a 'scheduled'): fuera de la pantalla.
create or replace function public.gym_screen_cast_end_with_session()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'in_progress' and new.status is distinct from 'in_progress' then
    delete from public.gym_screen_casts where schedule_id = new.id;
  end if;
  return null;
end;
$$;
drop trigger if exists gym_screen_cast_end_with_session on public.coaching_schedule;
create trigger gym_screen_cast_end_with_session after update of status on public.coaching_schedule
for each row execute function public.gym_screen_cast_end_with_session();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Lo que lee la tele: la 152 más quien transmite
-- ─────────────────────────────────────────────────────────────────────────────
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
    union all
    -- Quien transmite sin reserva (un admin) también está en el gym mientras transmite.
    select c.user_id, c.started_at, c.expires_at
    from public.gym_screen_casts c
    where c.screen_id = p_screen and c.expires_at > v_now and v_screen.casting
  ), cur as (
    select distinct on (w.user_id) w.user_id, w.start_at, w.end_at
    from win w
    where w.end_at > v_now
    order by w.user_id, w.start_at
  ), vis as (
    select c.*,
           cs.user_id is not null as casting,
           -- Transmitir enseña la rutina aunque la preferencia de Perfil diga otra cosa.
           case when cs.user_id is not null then 'routine' else coalesce(p.visibility, 'hidden') end as visibility,
           cs.focus_key, cs.focus_idx, cs.rest_end_at, cs.rest_frozen_s, cs.rest_total_s,
           cs.paused as cast_paused, cs.updated_at as cast_updated_at
    from cur c
    left join public.gym_screen_prefs p on p.user_id = c.user_id
    left join public.gym_screen_casts cs
      on cs.user_id = c.user_id and cs.screen_id = p_screen and cs.expires_at > v_now and v_screen.casting
  )
  select
    count(*) filter (where v.visibility = 'hidden' and v_now >= v.start_at - interval '10 minutes'),
    coalesce(jsonb_agg(jsonb_build_object(
      'key', left(md5(v.user_id::text || v_today::text), 12),
      'name', public.gym_screen_short_name(pr.name),
      'start_at', v.start_at,
      'end_at', v.end_at,
      'visibility', v.visibility,
      'routine', case when v.visibility = 'routine' then public.gym_screen_routine(v.user_id, v_today) end,
      'live', case when v.casting then jsonb_build_object(
        'focus_key', v.focus_key, 'focus_idx', v.focus_idx,
        'rest_end_at', v.rest_end_at, 'rest_frozen_s', v.rest_frozen_s, 'rest_total_s', v.rest_total_s,
        'paused', v.cast_paused, 'updated_at', v.cast_updated_at) end
    ) order by v.casting desc, v.start_at, pr.name) filter (where v.visibility <> 'hidden'), '[]'::jsonb)
  into v_hidden, v_people
  from vis v
  join public.profiles pr on pr.id = v.user_id;

  return jsonb_build_object('ok', true, 'mode', v_screen.mode, 'name', v_screen.name, 'lang', v_screen.lang,
    'casting', v_screen.casting, 'now', v_now, 'today', v_today, 'people', v_people,
    'hidden_now', coalesce(v_hidden, 0));
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. El control: el interruptor de las transmisiones
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
    'lang', v_screen.lang, 'casting', v_screen.casting, 'access_key', v_screen.access_key,
    'updated_at', v_screen.updated_at,
    'casts_now', (select count(*) from public.gym_screen_casts c where c.screen_id = p_screen and c.expires_at > now()));
end;
$$;

-- Un argumento más que en la 152: se retira la firma vieja para que PostgREST no tenga dos
-- candidatas (lo mismo que la 115 con apply_coaching_program).
drop function if exists public.gym_screen_configure(text, text, text, boolean, boolean);
create or replace function public.gym_screen_configure(
  p_screen text, p_mode text default null, p_lang text default null,
  p_rotate_key boolean default false, p_reload boolean default false, p_casting boolean default null)
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
    casting = coalesce(p_casting, casting),
    access_key = case when p_rotate_key
      then replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')
      else access_key end,
    updated_at = now()
  where id = p_screen;
  if not found then raise exception 'NO_SCREEN'; end if;
  -- Apagar las transmisiones las termina: no se quedan esperando a que vuelva a encenderse.
  if p_casting = false then
    delete from public.gym_screen_casts where screen_id = p_screen;
  end if;
  if p_reload then
    update public.gym_screen_pings set reload_nonce = reload_nonce + 1, bumped_at = now()
    where screen_id = p_screen;
  end if;
  return public.gym_screen_admin(p_screen);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Permisos (lección de la 124 y la 154)
-- ─────────────────────────────────────────────────────────────────────────────
revoke all on function public.gym_screen_booking_end(uuid) from public, anon, authenticated;
revoke all on function public.start_gym_cast(uuid, text) from public, anon, authenticated;
revoke all on function public.update_gym_cast(text, integer, integer, integer, boolean) from public, anon, authenticated;
revoke all on function public.stop_gym_cast() from public, anon, authenticated;
revoke all on function public.gym_screen_cast_end_with_session() from public, anon, authenticated;
revoke all on function public.gym_screen_state(text, text) from public, anon, authenticated;
revoke all on function public.gym_screen_admin(text) from public, anon, authenticated;
revoke all on function public.gym_screen_configure(text, text, text, boolean, boolean, boolean) from public, anon, authenticated;

grant execute on function public.gym_screen_state(text, text) to anon, authenticated;
grant execute on function public.start_gym_cast(uuid, text) to authenticated;
grant execute on function public.update_gym_cast(text, integer, integer, integer, boolean) to authenticated;
grant execute on function public.stop_gym_cast() to authenticated;
grant execute on function public.gym_screen_admin(text) to authenticated;
grant execute on function public.gym_screen_configure(text, text, text, boolean, boolean, boolean) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Limpieza de lo vencido (pg_cron, como la 150)
-- ─────────────────────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'habit-gym-screen-casts') then
      perform cron.unschedule('habit-gym-screen-casts');
    end if;
    perform cron.schedule('habit-gym-screen-casts', '*/5 * * * *',
      $job$delete from public.gym_screen_casts where expires_at < now()$job$);
  end if;
end $$;

commit;
