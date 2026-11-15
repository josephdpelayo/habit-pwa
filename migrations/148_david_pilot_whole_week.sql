begin;

-- 147 solo abrió el lunes 16 de noviembre. Joseph pidió que la clase piloto con
-- David sea independiente por día — toda la semana, lunes a viernes (16–20 nov) — y
-- no una sola fecha fija. Las funciones de 147 tenían la fecha quemada adentro;
-- aquí se vuelven a crear con una fecha por parámetro, y david_pilot_slots() recorre
-- los cinco días en vez de uno.

alter table public.david_pilot_holds add column if not exists ds date;
update public.david_pilot_holds set ds = date '2026-11-16' where ds is null;
alter table public.david_pilot_holds alter column ds set not null;

do $$ begin
  alter table public.david_pilot_holds
    add constraint david_pilot_holds_ds_check check (ds between date '2026-11-16' and date '2026-11-20');
exception
  when duplicate_object then null;
end $$;

drop function if exists public.david_pilot_held(integer);
create or replace function public.david_pilot_held(p_ds date, p_idx integer)
returns integer language sql stable set search_path = public
as $$
  select count(*)::integer from public.david_pilot_holds h
  where h.ds = p_ds and h.start_idx = p_idx and h.expires_at > now() and h.stripe_id is null
$$;
revoke all on function public.david_pilot_held(date, integer) from public;

drop function if exists public.david_pilot_remaining(integer);
create or replace function public.david_pilot_remaining(p_ds date, p_idx integer)
returns integer language sql stable set search_path = public
as $$
  with active as (
    select start_idx, slots_used,
           case when is_group then least(4, coalesce(nullif(grupal_spots, 0), 4)) else 1 end as spots
    from public.bookings
    where ds = p_ds and status = 'active' and coach_david
  )
  select greatest(0, least(
    3 - (select count(*) from active where start_idx = p_idx),
    4 - (select max(used) from (
      select coalesce(sum(active.spots), 0) as used
      from generate_series(p_idx, p_idx + 1) as slot(idx)
      left join active on active.start_idx <= slot.idx and active.start_idx + active.slots_used > slot.idx
      group by slot.idx
    ) as occupancy)
  ) - public.david_pilot_held(p_ds, p_idx))::integer
$$;
revoke all on function public.david_pilot_remaining(date, integer) from public;

-- david_pilot_credits no cambia: ya tomaba p_starts_at, no una fecha quemada.

drop function if exists public.david_pilot_slots();
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
  from generate_series(date '2026-11-16', date '2026-11-20', interval '1 day') as d(day)
  cross join (values (14), (16), (18)) as s(idx)
  join public.profiles p on p.id = auth.uid()
  cross join lateral (select public.habit_slot_start(d.day, s.idx) as starts_at) t
  where t.starts_at > now()
  order by d.day, s.idx
$$;
revoke all on function public.david_pilot_slots() from public;
grant execute on function public.david_pilot_slots() to authenticated;

drop function if exists public.reserve_david_pilot(integer);
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
  if member_id is null or p_ds is null or p_ds not between date '2026-11-16' and date '2026-11-20'
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

drop function if exists public.hold_david_pilot(uuid, integer, integer);
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
  if p_ds is null or p_ds not between date '2026-11-16' and date '2026-11-20'
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

-- finish_david_pilot conserva su firma (ya la llama confirm-checkout-session.js y el
-- webhook): el día sale del propio hold, no de un parámetro nuevo.
create or replace function public.finish_david_pilot(
  p_hold uuid, p_user uuid, p_stripe text, p_amount integer
)
returns boolean language plpgsql security definer set search_path = public
as $$
declare
  hold public.david_pilot_holds;
  profile public.profiles%rowtype;
  reservation uuid;
begin
  select * into profile from public.profiles where id = p_user for update;
  select * into hold from public.david_pilot_holds where id = p_hold and user_id = p_user for update;
  if not found or hold.amount <> p_amount then return false; end if;
  perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(hold.ds::text));
  if hold.stripe_id is not null then
    return hold.stripe_id = p_stripe and not hold.rejected;
  end if;
  if clock_timestamp() >= hold.expires_at
    or (profile.plan_id in ('im', 'gm') and profile.plan_expiry >= public.habit_slot_start(hold.ds, hold.start_idx))
    or exists (select 1 from public.bookings where user_id = p_user and ds = hold.ds and status = 'active')
    or (hold.credits_used = 1 and (coalesce(profile.credits, 0) not between 1 and 998
      or profile.plan_expiry < public.habit_slot_start(hold.ds, hold.start_idx))) then
    update public.david_pilot_holds set stripe_id = p_stripe, rejected = true where id = p_hold;
    return false;
  end if;

  insert into public.bookings
    (user_id, ds, start_idx, slots_used, time_str, dur_min, credit_charged, coach_david, david_credits_used)
  values
    (p_user, hold.ds, hold.start_idx, 2,
     public.habit_fmt_slot(hold.start_idx) || ' - ' || public.habit_fmt_slot(hold.start_idx + 2),
     60, hold.credits_used > 0, true, hold.credits_used)
  returning id into reservation;

  if hold.credits_used > 0 then
    update public.profiles set credits = credits - hold.credits_used where id = p_user;
  end if;
  insert into public.payments(user_id, plan_id, plan_name, plan_type, amount, stripe_id)
  values(p_user, 'david_pilot', 'Entrena con David', 'individual', hold.amount / 100.0, p_stripe);
  update public.david_pilot_holds set booking_id = reservation, stripe_id = p_stripe where id = p_hold;
  return true;
end;
$$;
revoke all on function public.finish_david_pilot(uuid, uuid, text, integer) from public;
grant execute on function public.finish_david_pilot(uuid, uuid, text, integer) to service_role;

-- keep_david_pilot_time ya era agnóstica a la fecha (compara ds/start_idx/slots_used
-- de la fila), no necesita cambios.

-- Bloquea martes a viernes (16 nov ya quedó bloqueado y con la reserva de Biodelys
-- enlazada por la 147; no se vuelve a tocar aquí).
do $$
declare
  d date;
  first_slot constant integer := 14;
  end_slot constant integer := 20;
begin
  for d in select generate_series(date '2026-11-17', date '2026-11-20', interval '1 day')::date loop
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
