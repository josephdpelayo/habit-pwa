begin;

-- Joseph pidió (20 nov 2026) volver a abrir Entrena con David de martes a viernes de
-- la semana siguiente, 24–27 de noviembre, con los mismos horarios (7, 8 y 9 h) y el
-- mismo bloqueo de 7:00 a 10:00 en la agenda. La 148 tenía el rango 16–20 nov quemado
-- en cuatro sitios; ahora los días viven en uno solo, david_pilot_is_day(), y abrir
-- otra semana es cambiar esa función y bloquear la agenda.

create or replace function public.david_pilot_is_day(p_ds date)
returns boolean language sql immutable set search_path = public
as $$
  select p_ds between date '2026-11-16' and date '2026-11-20'
      or p_ds between date '2026-11-24' and date '2026-11-27'
$$;
revoke all on function public.david_pilot_is_day(date) from public;

alter table public.david_pilot_holds drop constraint if exists david_pilot_holds_ds_check;
alter table public.david_pilot_holds
  add constraint david_pilot_holds_ds_check check (public.david_pilot_is_day(ds));

create or replace function public.david_pilot_slots()
returns table(ds date, start_idx integer, remaining integer, reserved boolean, amount integer, payment_open boolean, credits_used integer)
language sql stable security definer set search_path = public
as $$
  select d.day, s.idx, public.david_pilot_remaining(d.day, s.idx),
         exists (select 1 from public.bookings b
                 where b.ds = d.day and b.start_idx = s.idx
                   and b.user_id = p.id and b.coach_david and b.status = 'active'),
         (2 - public.david_pilot_credits(p, t.starts_at)) * 11000,
         t.starts_at > now() + interval '32 minutes',
         case when p.plan_id in ('im', 'gm') and p.plan_expiry >= t.starts_at then 0
              else public.david_pilot_credits(p, t.starts_at) end
  from generate_series(0, 11) as offsets(day_offset)
  cross join lateral (select date '2026-11-16' + offsets.day_offset as day) d
  cross join (values (14), (16), (18)) as s(idx)
  join public.profiles p on p.id = auth.uid()
  cross join lateral (select public.habit_slot_start(d.day, s.idx) as starts_at) t
  where public.david_pilot_is_day(d.day) and t.starts_at > now()
  order by d.day, s.idx
$$;
revoke all on function public.david_pilot_slots() from public;
grant execute on function public.david_pilot_slots() to authenticated;

create or replace function public.reserve_david_pilot(p_ds date, p_start_idx integer)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  member_id uuid := auth.uid();
  member_profile public.profiles%rowtype;
  booking_id uuid;
  tickets_used integer;
begin
  if member_id is null or p_ds is null or not public.david_pilot_is_day(p_ds)
    or p_start_idx is null or p_start_idx not in (14, 16, 18) then
    raise exception 'Horario inválido.';
  end if;

  select * into member_profile from public.profiles where id = member_id for update;
  perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(p_ds::text));
  if public.habit_slot_start(p_ds, p_start_idx) <= clock_timestamp() then
    raise exception 'La sesión ya empezó.';
  end if;

  select id into booking_id from public.bookings
  where user_id = member_id and ds = p_ds and status = 'active'
    and coach_david and start_idx = p_start_idx;
  if found then return booking_id; end if;

  if member_profile.id is null or public.david_pilot_credits(member_profile, public.habit_slot_start(p_ds, p_start_idx)) < 2 then
    raise exception 'Necesitas dos boletos de clase o una mensualidad activa.';
  end if;
  tickets_used := case
    when member_profile.plan_id in ('im', 'gm') and member_profile.plan_expiry >= public.habit_slot_start(p_ds, p_start_idx) then 0
    else 2
  end;

  if exists (select 1 from public.bookings
             where user_id = member_id and ds = p_ds and status = 'active')
    or exists (select 1 from public.david_pilot_holds h where h.user_id = member_id
      and h.stripe_id is null and h.expires_at > now()) then
    raise exception 'Ya tienes una reserva activa para este día.';
  end if;

  if public.david_pilot_remaining(p_ds, p_start_idx) = 0 then
    raise exception 'Cupo lleno.';
  end if;

  insert into public.bookings
    (user_id, ds, start_idx, slots_used, time_str, dur_min, credit_charged, coach_david, david_credits_used)
  values
    (member_id, p_ds, p_start_idx, 2,
     public.habit_fmt_slot(p_start_idx) || ' - ' || public.habit_fmt_slot(p_start_idx + 2),
     60, tickets_used > 0, true, tickets_used)
  returning id into booking_id;

  if tickets_used > 0 then
    update public.profiles set credits = credits - tickets_used where id = member_id;
  end if;

  return booking_id;
end;
$$;
revoke all on function public.reserve_david_pilot(date, integer) from public;
grant execute on function public.reserve_david_pilot(date, integer) to authenticated;

create or replace function public.hold_david_pilot(p_user uuid, p_ds date, p_idx integer, p_amount integer)
returns public.david_pilot_holds
language plpgsql security definer set search_path = public
as $$
declare
  profile public.profiles%rowtype;
  hold public.david_pilot_holds;
  expiry timestamptz := date_trunc('second', clock_timestamp()) + interval '32 minutes';
  class_start timestamptz;
  amount_due integer;
  tickets_used integer;
begin
  if p_ds is null or not public.david_pilot_is_day(p_ds)
    or p_idx is null or p_idx not in (14, 16, 18) then
    raise exception 'Horario inválido.';
  end if;
  class_start := public.habit_slot_start(p_ds, p_idx);
  if expiry >= class_start then
    raise exception 'El pago en línea cierra 32 minutos antes de la sesión.';
  end if;
  select * into profile from public.profiles where id = p_user for update;
  if not found then raise exception 'Completa tu perfil para reservar.'; end if;

  perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(p_ds::text));
  if exists (select 1 from public.bookings
    where user_id = p_user and ds = p_ds and status = 'active') then
    raise exception 'Ya tienes una reserva activa para este día.';
  end if;
  tickets_used := public.david_pilot_credits(profile, class_start);
  if tickets_used = 2 then
    raise exception 'Puedes reservar con tu mensualidad o con dos boletos.';
  end if;
  amount_due := (2 - tickets_used) * 11000;
  if amount_due is distinct from p_amount then
    raise exception 'El precio cambió. Actualiza la agenda para verlo.';
  end if;
  select * into hold from public.david_pilot_holds h
    where h.user_id = p_user and h.stripe_id is null and h.expires_at > now();
  if found then
    if hold.ds = p_ds and hold.start_idx = p_idx and hold.amount = amount_due and hold.expires_at > clock_timestamp() + interval '31 minutes' then
      return hold;
    end if;
    raise exception 'Ya tienes un pago pendiente. Termínalo desde Stripe o espera a que venza.';
  end if;
  if public.david_pilot_remaining(p_ds, p_idx) = 0 then
    raise exception 'Cupo lleno.';
  end if;

  insert into public.david_pilot_holds(user_id, ds, start_idx, credits_used, amount, expires_at)
  values (p_user, p_ds, p_idx, tickets_used, amount_due, expiry)
  returning * into hold;
  return hold;
end;
$$;
revoke all on function public.hold_david_pilot(uuid, date, integer, integer) from public;
grant execute on function public.hold_david_pilot(uuid, date, integer, integer) to service_role;

-- Bloquea martes 24 a viernes 27 de 7:00 a 10:00, como la 148 hizo con 17–20.
do $$
declare
  d date;
  first_slot constant integer := 14;
  end_slot constant integer := 20;
begin
  for d in select generate_series(date '2026-11-24', date '2026-11-27', interval '1 day')::date loop
    perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(d::text));

    if exists (
      select 1
      from public.bookings b
      where b.status = 'active' and not b.coach_david
        and b.ds between d - 1 and d
        and public.habit_slot_start(b.ds, b.start_idx)
          < public.habit_slot_start(d, end_slot)
        and public.habit_slot_start(d, first_slot)
          < public.habit_slot_start(b.ds, b.start_idx + coalesce(b.slots_used, 3))
    ) then
      raise exception 'Hay reservas activas el % que coinciden con Entrena con David. Revísalas en Agenda antes de bloquear.', d;
    end if;

    insert into public.slot_blocks as blocks (ds, slot_idx, spots, reason)
    select d, slot_idx, 4, 'Entrena con David'
    from generate_series(first_slot, end_slot - 1) as slots(slot_idx)
    on conflict (ds, slot_idx) do update
    set spots = excluded.spots,
        reason = excluded.reason || ' · ' || blocks.reason
    where blocks.spots < excluded.spots;
  end loop;
end;
$$;

commit;
