-- HABIT: las reservas y los créditos se deciden en el servidor.
--
-- Hasta aquí el socio escribía directo en `bookings`, `slot_occupancy` y en su
-- propia fila de `profiles`, y era la app la que descontaba y devolvía la
-- visita. Con la llave anon —que viaja dentro de app.html— cualquiera con la
-- consola del navegador podía darse créditos o membresía
-- (`profiles.update({credits:999, plan_expiry:…})`) o insertar una reserva sin
-- pagar, y la puerta solo mira reservas. La 117 cerró `role`, pero no el plan.
-- Además reservar y cancelar eran tres o cuatro escrituras sueltas sin revisar
-- errores: con mala señal, una cancelación podía devolver la visita y dejar la
-- reserva activa, y una reserva podía entrar sin descontar nada.
--
-- Ahora:
--   · book_my_slot / cancel_my_booking / reschedule_my_booking hacen cada
--     operación completa en una transacción, con las mismas reglas que la app
--     (cupo de 4, bloqueos del admin, una reserva por día, 7 días de
--     anticipación, plan vigente para ese día, cancelación con 12 h de
--     anticipación o dentro de las 2 h de haber reservado) y con un candado por
--     día, para que dos socios no se queden a la vez con el último lugar.
--   · `bookings.credit_charged` dice si esa reserva cobró visita: cancelar
--     devuelve lo que cobró, no lo que el plan de hoy haría suponer.
--   · El socio ya no puede insertar ni modificar reservas u ocupación, ni
--     registrar pagos, y un trigger le impide cambiar créditos o plan en su
--     perfil. El admin sigue escribiendo directo como hasta ahora, y el
--     service-role (Stripe, api/*) también.
--
-- Orden de despliegue: primero la app —usa estos RPC si existen y, si no, el
-- camino de antes— y después esta migración. Al revés, la app publicada se
-- queda sin poder reservar hasta que llega la nueva.
--
-- Requiere la 117 (public.is_habit_admin).

begin;

do $$
begin
  if to_regprocedure('public.is_habit_admin()') is null then
    raise exception 'Falta la migración 117 (public.is_habit_admin). Córrela antes que esta.';
  end if;
end $$;

-- Es la columna de la 024. El trigger de perfiles la lee, así que tiene que
-- existir aunque esa migración no se haya corrido.
alter table public.profiles
  add column if not exists plan_is_courtesy boolean not null default false;

-- null = reserva anterior a esta migración: no se sabe si cobró, y al
-- cancelarla se decide como lo hacía la app (por el plan vigente).
alter table public.bookings
  add column if not exists credit_charged boolean;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Tiempo y cupo, igual que la app
-- ─────────────────────────────────────────────────────────────────────────────

-- Inicio de un slot. Mazatlán es UTC−7 fijo, igual que MAZ_UTC_OFFSET_H en la
-- app y en lib/_slots.js. El índice puede pasar de 47: una reserva de las 23:00
-- termina en el slot 50, que es la 01:00 del día siguiente.
create or replace function public.habit_slot_start(p_ds date, p_idx integer)
returns timestamptz
language sql
immutable
as $$
  select (p_ds::timestamp + make_interval(hours => 7, mins => 30 * p_idx)) at time zone 'UTC';
$$;

-- 'HH:MM' de un índice, dando la vuelta después de las 23:30 (fmtSlot en la app).
create or replace function public.habit_fmt_slot(p_idx integer)
returns text
language sql
immutable
as $$
  select lpad(((((p_idx % 48) + 48) % 48) * 30 / 60)::text, 2, '0') || ':'
      || lpad(((((p_idx % 48) + 48) % 48) * 30 % 60)::text, 2, '0');
$$;

-- Cuántos de los 4 lugares de un slot están tomados, y si está cerrado entero
-- (bloqueado por el admin o tomado por una reserva grupal). Es la misma cuenta
-- que getSlotOccupancy() en la app: los bloqueos suman sus `spots`, una
-- reserva grupal suma sus `grupal_spots` y cada socio individual cuenta uno.
-- Solo cuenta ocupación de reservas activas, así que nunca ve más ocupado que
-- la app (una fila huérfana de una cancelación a medias no cierra el slot).
create or replace function public.habit_slot_state(
  p_ds date,
  p_idx integer,
  p_exclude_booking uuid default null
)
returns table(taken integer, closed boolean)
language plpgsql
stable
set search_path = public
as $$
declare
  c_cap constant integer := 4;
  v_blocked integer;
  v_group integer;
  v_people integer;
begin
  select coalesce(sum(spots), 0) into v_blocked
  from public.slot_blocks
  where ds = p_ds and slot_idx = p_idx;
  if v_blocked >= c_cap then
    taken := c_cap; closed := true; return next; return;
  end if;

  select
    coalesce(sum(least(c_cap, coalesce(nullif(b.grupal_spots, 0), c_cap))) filter (where o.is_group), 0),
    count(distinct o.user_id) filter (where not o.is_group)
  into v_group, v_people
  from public.slot_occupancy o
  join public.bookings b on b.id = o.booking_id
  where o.ds = p_ds and o.slot_idx = p_idx
    and b.status = 'active'
    and (p_exclude_booking is null or o.booking_id <> p_exclude_booking);

  if v_group >= c_cap then
    taken := c_cap; closed := true; return next; return;
  end if;
  taken := least(c_cap, v_blocked + v_group + v_people);
  closed := false;
  return next;
end;
$$;
revoke all on function public.habit_slot_state(date, integer, uuid) from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Reservar
-- ─────────────────────────────────────────────────────────────────────────────

-- Los errores salen como códigos (NO_CREDITS, SLOT_FULL…) que la app traduce;
-- ver BOOKING_RPC_ERRORS en app.html.
create or replace function public.book_my_slot(
  p_ds date,
  p_start_idx integer,
  p_slots_used integer default 3
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_cap constant integer := 4;
  c_advance_days constant integer := 7;
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_unlimited boolean;
  v_group boolean;
  v_today date;
  v_now_slot timestamptz;
  v_start timestamptz;
  v_end timestamptz;
  v_state record;
  v_min_free integer := c_cap;
  v_spots integer;
  v_booking public.bookings%rowtype;
  v_credits integer;
  i integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_ds is null or p_start_idx is null or p_start_idx < 0 or p_start_idx > 47
     or p_slots_used is null or p_slots_used not in (2, 3) then
    raise exception 'BOOKING_INVALID';
  end if;

  -- El perfil primero y con candado: es la fila de la que sale la visita, y
  -- serializa las reservas del mismo socio (doble toque, dos teléfonos).
  select * into v_profile from public.profiles where id = v_uid for update;
  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;

  -- hasActive() y el chequeo de vencimiento de canStartAt() en la app.
  -- El coalesce del plan no es decorativo: con plan_id null (toda cuenta
  -- nueva) `null in (…)` es null, `false or null` es null, y un `if not null`
  -- no entra — una cuenta sin plan ni visitas reservaba y quedaba en -1.
  v_unlimited := coalesce(v_profile.credits, 0) >= 999
    or coalesce(v_profile.plan_id in ('im', 'gm'), false);
  if not v_unlimited and coalesce(v_profile.credits, 0) <= 0 then
    raise exception 'NO_CREDITS';
  end if;
  if v_profile.plan_expiry is not null and v_profile.plan_expiry < now() then
    raise exception 'PLAN_EXPIRED';
  end if;
  if v_profile.plan_expiry is not null
     and p_ds > (v_profile.plan_expiry at time zone 'America/Mazatlan')::date then
    raise exception 'PLAN_ENDS_BEFORE';
  end if;

  -- Un slot "pasó" cuando ya empezó el siguiente (isSlotPast): el de las 7:00
  -- se puede reservar hasta las 7:29.
  v_today := (now() at time zone 'UTC' - interval '7 hours')::date;
  v_now_slot := public.habit_slot_start(v_today,
    floor(extract(epoch from now() - public.habit_slot_start(v_today, 0)) / 1800)::integer);
  v_start := public.habit_slot_start(p_ds, p_start_idx);
  v_end := public.habit_slot_start(p_ds, p_start_idx + p_slots_used);
  if v_start < v_now_slot then raise exception 'BOOKING_PAST'; end if;
  if p_ds > v_today + c_advance_days then raise exception 'BOOKING_TOO_FAR'; end if;

  -- Candado por día (en orden, para no cruzarse con otra reserva que tome los
  -- mismos dos días): desde aquí nadie más reserva ese día hasta el commit, así
  -- que el cupo que se cuenta abajo es el que queda.
  perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(p_ds::text));
  if p_start_idx + p_slots_used > 48 then
    perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext((p_ds + 1)::text));
  end if;

  if exists(
    select 1 from public.bookings
    where user_id = v_uid and status = 'active' and ds = p_ds
  ) then
    raise exception 'ONE_PER_DAY';
  end if;
  -- Una de las 23:00 de ayer puede alcanzar la madrugada de hoy.
  if exists(
    select 1 from public.bookings b
    where b.user_id = v_uid and b.status = 'active'
      and b.ds between p_ds - 1 and p_ds + 1
      and public.habit_slot_start(b.ds, b.start_idx) < v_end
      and v_start < public.habit_slot_start(b.ds, b.start_idx + coalesce(b.slots_used, 3))
  ) then
    raise exception 'OVERLAP';
  end if;

  -- El plan decide si es grupal, no lo que mande el cliente.
  v_group := coalesce(v_profile.plan_type = 'grupal', false);
  for i in 0 .. p_slots_used - 1 loop
    select * into v_state
    from public.habit_slot_state(p_ds + ((p_start_idx + i) / 48), (p_start_idx + i) % 48, null);
    if v_state.closed then raise exception 'SLOT_BLOCKED'; end if;
    if c_cap - v_state.taken < 1 then raise exception 'SLOT_FULL'; end if;
    v_min_free := least(v_min_free, c_cap - v_state.taken);
  end loop;
  -- Una grupal se lleva los lugares que quedan libres en todo su rango.
  v_spots := case when v_group then v_min_free else 1 end;

  insert into public.bookings
    (user_id, ds, start_idx, slots_used, is_group, grupal_spots, time_str, dur_min, status, credit_charged)
  values
    (v_uid, p_ds, p_start_idx, p_slots_used, v_group, v_spots,
     public.habit_fmt_slot(p_start_idx) || ' - ' || public.habit_fmt_slot(p_start_idx + p_slots_used),
     p_slots_used * 30, 'active', not v_unlimited)
  returning * into v_booking;

  -- `slot_occupancy` es única por (ds, slot_idx, user_id). Una fila que quedó
  -- de una reserva ya cancelada (cancelación a medias del camino anterior)
  -- bloquearía el insert, así que se retira.
  delete from public.slot_occupancy o
  using public.bookings b
  where b.id = o.booking_id and b.status <> 'active' and o.user_id = v_uid
    and (o.ds, o.slot_idx) in (
      select p_ds + ((p_start_idx + g) / 48), (p_start_idx + g) % 48
      from generate_series(0, p_slots_used - 1) g
    );

  insert into public.slot_occupancy (ds, slot_idx, user_id, booking_id, is_group, spot)
  select p_ds + ((p_start_idx + g) / 48), (p_start_idx + g) % 48, v_uid, v_booking.id, v_group,
         case when v_group then v_spots end
  from generate_series(0, p_slots_used - 1) g;

  if v_unlimited then
    v_credits := v_profile.credits;
  else
    update public.profiles set credits = credits - 1
    where id = v_uid
    returning credits into v_credits;
  end if;

  return jsonb_build_object('booking', to_jsonb(v_booking), 'credits', v_credits);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Cancelar
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.cancel_my_booking(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_profile public.profiles%rowtype;
  v_start timestamptz;
  v_unlimited boolean;
  v_refund boolean;
  v_credits integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found or v_booking.user_id <> v_uid then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking.status <> 'active' then raise exception 'BOOKING_NOT_ACTIVE'; end if;

  -- canCancelBk(): con 12 h o más de anticipación, o dentro de las 2 h
  -- siguientes a haber reservado. Nunca una que ya empezó.
  v_start := public.habit_slot_start(v_booking.ds, v_booking.start_idx);
  if v_start <= now() then raise exception 'BOOKING_STARTED'; end if;
  if v_start - now() < interval '12 hours'
     and now() - v_booking.created_at > interval '2 hours' then
    raise exception 'CANCEL_WINDOW_CLOSED';
  end if;

  select * into v_profile from public.profiles where id = v_uid for update;
  -- Mismo coalesce que en book_my_slot: sin él, quien tiene visitas sueltas
  -- sin plan_id cancelaba y no recuperaba la visita (refunded = null).
  v_unlimited := coalesce(v_profile.credits, 0) >= 999
    or coalesce(v_profile.plan_id in ('im', 'gm'), false);
  -- Devuelve lo que cobró. Una reserva de antes de esta migración no lo sabe,
  -- y se decide como antes: si el plan de hoy no es ilimitado. Un plan
  -- ilimitado vigente no recibe visitas sueltas, que no significarían nada.
  v_refund := not v_unlimited and coalesce(v_booking.credit_charged, true);

  update public.bookings set status = 'cancelled' where id = v_booking.id;
  delete from public.slot_occupancy where booking_id = v_booking.id;

  if v_refund then
    update public.profiles set credits = credits + 1
    where id = v_uid
    returning credits into v_credits;
  else
    v_credits := v_profile.credits;
  end if;

  return jsonb_build_object('credits', v_credits, 'refunded', v_refund);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Cambiar de horario (mismo día; se permite aunque ya no se pueda cancelar)
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.reschedule_my_booking(p_booking_id uuid, p_start_idx integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_cap constant integer := 4;
  v_uid uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_slots integer;
  v_today date;
  v_now_slot timestamptz;
  v_start timestamptz;
  v_end timestamptz;
  v_state record;
  v_min_free integer := c_cap;
  v_spots integer;
  i integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_start_idx is null or p_start_idx < 0 or p_start_idx > 47 then
    raise exception 'BOOKING_INVALID';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found or v_booking.user_id <> v_uid then raise exception 'BOOKING_NOT_FOUND'; end if;
  if v_booking.status <> 'active' then raise exception 'BOOKING_NOT_ACTIVE'; end if;
  if public.habit_slot_start(v_booking.ds, v_booking.start_idx) <= now() then
    raise exception 'BOOKING_STARTED';
  end if;
  if p_start_idx = v_booking.start_idx then raise exception 'SAME_TIME'; end if;

  v_slots := coalesce(v_booking.slots_used, 3);
  v_today := (now() at time zone 'UTC' - interval '7 hours')::date;
  v_now_slot := public.habit_slot_start(v_today,
    floor(extract(epoch from now() - public.habit_slot_start(v_today, 0)) / 1800)::integer);
  v_start := public.habit_slot_start(v_booking.ds, p_start_idx);
  v_end := public.habit_slot_start(v_booking.ds, p_start_idx + v_slots);
  if v_start < v_now_slot then raise exception 'BOOKING_PAST'; end if;

  perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(v_booking.ds::text));
  if p_start_idx + v_slots > 48 then
    perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext((v_booking.ds + 1)::text));
  end if;

  if exists(
    select 1 from public.bookings b
    where b.user_id = v_uid and b.status = 'active' and b.id <> v_booking.id
      and b.ds between v_booking.ds - 1 and v_booking.ds + 1
      and public.habit_slot_start(b.ds, b.start_idx) < v_end
      and v_start < public.habit_slot_start(b.ds, b.start_idx + coalesce(b.slots_used, 3))
  ) then
    raise exception 'OVERLAP';
  end if;

  -- La reserva conserva si es grupal: cambiar de horario no cambia de plan.
  for i in 0 .. v_slots - 1 loop
    select * into v_state
    from public.habit_slot_state(v_booking.ds + ((p_start_idx + i) / 48), (p_start_idx + i) % 48, v_booking.id);
    if v_state.closed then raise exception 'SLOT_BLOCKED'; end if;
    if c_cap - v_state.taken < 1 then raise exception 'SLOT_FULL'; end if;
    v_min_free := least(v_min_free, c_cap - v_state.taken);
  end loop;
  v_spots := case when v_booking.is_group then v_min_free else 1 end;

  update public.bookings
  set start_idx = p_start_idx,
      time_str = public.habit_fmt_slot(p_start_idx) || ' - ' || public.habit_fmt_slot(p_start_idx + v_slots),
      grupal_spots = v_spots
  where id = v_booking.id
  returning * into v_booking;

  delete from public.slot_occupancy where booking_id = v_booking.id;
  delete from public.slot_occupancy o
  using public.bookings b
  where b.id = o.booking_id and b.status <> 'active' and o.user_id = v_uid
    and (o.ds, o.slot_idx) in (
      select v_booking.ds + ((p_start_idx + g) / 48), (p_start_idx + g) % 48
      from generate_series(0, v_slots - 1) g
    );
  insert into public.slot_occupancy (ds, slot_idx, user_id, booking_id, is_group, spot)
  select v_booking.ds + ((p_start_idx + g) / 48), (p_start_idx + g) % 48, v_uid, v_booking.id,
         v_booking.is_group, case when v_booking.is_group then v_spots end
  from generate_series(0, v_slots - 1) g;

  return jsonb_build_object('booking', to_jsonb(v_booking));
end;
$$;

revoke all on function public.book_my_slot(date, integer, integer) from public, anon;
revoke all on function public.cancel_my_booking(uuid) from public, anon;
revoke all on function public.reschedule_my_booking(uuid, integer) from public, anon;
grant execute on function public.book_my_slot(date, integer, integer) to authenticated;
grant execute on function public.cancel_my_booking(uuid) to authenticated;
grant execute on function public.reschedule_my_booking(uuid, integer) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. El socio ya no escribe su plan, sus reservas ni sus pagos
-- ─────────────────────────────────────────────────────────────────────────────

-- SECURITY INVOKER a propósito: así `current_user` es quien ejecuta el UPDATE.
-- Directo desde la app es 'authenticated'; dentro de un RPC security definer
-- (book_my_slot, ensure_habit_profile, handle_new_user) es el dueño de la
-- función, y con service-role es 'service_role'. Solo el primer caso se
-- restringe, y el admin queda fuera igual que en guard_profile_privileges.
create or replace function public.guard_profile_billing()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if public.is_habit_admin() then return new; end if;

  if tg_op = 'INSERT' then
    if coalesce(new.credits, 0) <> 0 or new.plan_id is not null or new.plan_type is not null
       or new.plan_expiry is not null or coalesce(new.plan_is_courtesy, false) then
      raise exception 'billing fields can only be set by the server';
    end if;
    return new;
  end if;

  if new.credits is distinct from old.credits
     or new.plan_id is distinct from old.plan_id
     or new.plan_type is distinct from old.plan_type
     or new.plan_expiry is distinct from old.plan_expiry
     or new.plan_is_courtesy is distinct from old.plan_is_courtesy then
    raise exception 'billing fields can only be changed by the server or an administrator';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_profile_billing_before_write on public.profiles;
create trigger guard_profile_billing_before_write
before insert or update on public.profiles
for each row execute function public.guard_profile_billing();

-- Reservas y ocupación: solo por los RPC de arriba (o el admin, cuyas
-- políticas "Admin all …" no se tocan). Leer sigue igual.
drop policy if exists "Users insert own bookings" on public.bookings;
drop policy if exists "Users update own bookings" on public.bookings;
drop policy if exists "Users insert own slots" on public.slot_occupancy;
drop policy if exists "Users delete own slots" on public.slot_occupancy;

-- Nadie en la app registra su propio pago: Stripe entra por service-role y los
-- pagos manuales los captura el admin. Esta política solo servía para meter
-- pagos falsos en los reportes.
drop policy if exists "Users insert own payments" on public.payments;

-- Si alguna política creada a mano en el dashboard todavía deja escribir a
-- socios en estas tablas, esta migración no la conoce por nombre: se avisa.
do $$
declare
  r record;
begin
  for r in
    select tablename, policyname, cmd
    from pg_policies
    where schemaname = 'public'
      and tablename in ('bookings', 'slot_occupancy', 'payments')
      and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
      and coalesce(qual, '') || ' ' || coalesce(with_check, '') !~* 'admin'
  loop
    raise notice 'Revisar: la política "%" (%) en % todavía deja escribir a socios.',
      r.policyname, r.cmd, r.tablename;
  end loop;
end $$;

commit;
