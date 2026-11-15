begin;

alter table public.bookings
  add column if not exists coach_david boolean not null default false,
  add column if not exists david_credits_used integer check (david_credits_used between 0 and 2);

create table if not exists public.david_pilot_holds (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  start_idx integer not null check (start_idx in (14, 16, 18)),
  credits_used integer not null check (credits_used in (0, 1)),
  amount integer not null check (amount = (2 - credits_used) * 11000),
  expires_at timestamptz not null,
  stripe_id text unique,
  booking_id uuid references public.bookings(id) on delete set null,
  rejected boolean not null default false
);

alter table public.david_pilot_holds enable row level security;
revoke all on public.david_pilot_holds from anon, authenticated;

create or replace function public.david_pilot_held(p_idx integer)
returns integer language sql stable set search_path = public
as $$
  select count(*)::integer from public.david_pilot_holds h
  where h.start_idx = p_idx and h.expires_at > now() and h.stripe_id is null
$$;
revoke all on function public.david_pilot_held(integer) from public;

create or replace function public.david_pilot_remaining(p_idx integer)
returns integer language sql stable set search_path = public
as $$
  with active as (
    select start_idx, slots_used,
           case when is_group then least(4, coalesce(nullif(grupal_spots, 0), 4)) else 1 end as spots
    from public.bookings
    where ds = date '2026-11-16' and status = 'active' and coach_david
  )
  select greatest(0, least(
    3 - (select count(*) from active where start_idx = p_idx),
    4 - (select max(used) from (
      select coalesce(sum(active.spots), 0) as used
      from generate_series(p_idx, p_idx + 1) as slot(idx)
      left join active on active.start_idx <= slot.idx and active.start_idx + active.slots_used > slot.idx
      group by slot.idx
    ) as occupancy)
  ) - public.david_pilot_held(p_idx))::integer
$$;
revoke all on function public.david_pilot_remaining(integer) from public;

-- La visita individual (i1 en lib/_plans.js) cuesta 110 MXN.
create or replace function public.david_pilot_credits(p_profile public.profiles, p_starts_at timestamptz)
returns integer language sql immutable set search_path = public
as $$
  select case
    when p_profile.plan_id in ('im', 'gm') and p_profile.plan_expiry >= p_starts_at then 2
    when p_profile.credits between 1 and 998
      and (p_profile.plan_expiry is null or p_profile.plan_expiry >= p_starts_at)
      then least(2, p_profile.credits)
    else 0
  end
$$;
revoke all on function public.david_pilot_credits(public.profiles, timestamptz) from public;

create or replace function public.david_pilot_slots()
returns table(start_idx integer, remaining integer, reserved boolean, amount integer, payment_open boolean, credits_used integer)
language sql stable security definer set search_path = public
as $$
  select s.idx, public.david_pilot_remaining(s.idx),
         exists (select 1 from public.bookings b
                 where b.ds = date '2026-11-16' and b.start_idx = s.idx
                   and b.user_id = p.id and b.coach_david and b.status = 'active'),
         (2 - public.david_pilot_credits(p, t.starts_at)) * 11000,
         t.starts_at > now() + interval '32 minutes',
         case when p.plan_id in ('im', 'gm') and p.plan_expiry >= t.starts_at then 0
              else public.david_pilot_credits(p, t.starts_at) end
  from (values (14), (16), (18)) as s(idx)
  join public.profiles p on p.id = auth.uid()
  cross join lateral (select public.habit_slot_start(date '2026-11-16', s.idx) as starts_at) t
  where t.starts_at > now()
  order by s.idx
$$;

create or replace function public.reserve_david_pilot(p_start_idx integer)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  pilot_date constant date := date '2026-11-16';
  member_id uuid := auth.uid();
  member_profile public.profiles%rowtype;
  booking_id uuid;
  tickets_used integer;
begin
  if member_id is null or p_start_idx is null or p_start_idx not in (14, 16, 18) then
    raise exception 'Horario inválido.';
  end if;

  select * into member_profile from public.profiles where id = member_id for update;
  perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(pilot_date::text));
  if public.habit_slot_start(pilot_date, p_start_idx) <= clock_timestamp() then
    raise exception 'La sesión ya empezó.';
  end if;

  select id into booking_id from public.bookings
  where user_id = member_id and ds = pilot_date and status = 'active'
    and coach_david and start_idx = p_start_idx;
  if found then return booking_id; end if;

  if member_profile.id is null or public.david_pilot_credits(member_profile, public.habit_slot_start(pilot_date, p_start_idx)) < 2 then
    raise exception 'Necesitas dos boletos de clase o una mensualidad activa.';
  end if;
  tickets_used := case
    when member_profile.plan_id in ('im', 'gm') and member_profile.plan_expiry >= public.habit_slot_start(pilot_date, p_start_idx) then 0
    else 2
  end;

  if exists (select 1 from public.bookings
             where user_id = member_id and ds = pilot_date and status = 'active')
    or exists (select 1 from public.david_pilot_holds h where h.user_id = member_id
      and h.stripe_id is null and h.expires_at > now()) then
    raise exception 'Ya tienes una reserva activa para este día.';
  end if;

  if public.david_pilot_remaining(p_start_idx) = 0 then
    raise exception 'Cupo lleno.';
  end if;

  insert into public.bookings
    (user_id, ds, start_idx, slots_used, time_str, dur_min, credit_charged, coach_david, david_credits_used)
  values
    (member_id, pilot_date, p_start_idx, 2,
     public.habit_fmt_slot(p_start_idx) || ' - ' || public.habit_fmt_slot(p_start_idx + 2),
     60, tickets_used > 0, true, tickets_used)
  returning id into booking_id;

  if tickets_used > 0 then
    update public.profiles set credits = credits - tickets_used where id = member_id;
  end if;

  return booking_id;
end;
$$;

create or replace function public.hold_david_pilot(p_user uuid, p_idx integer, p_amount integer)
returns public.david_pilot_holds
language plpgsql security definer set search_path = public
as $$
declare
  pilot_date constant date := date '2026-11-16';
  profile public.profiles%rowtype;
  hold public.david_pilot_holds;
  expiry timestamptz := date_trunc('second', clock_timestamp()) + interval '32 minutes';
  class_start timestamptz := public.habit_slot_start(pilot_date, p_idx);
  amount_due integer;
  tickets_used integer;
begin
  if p_idx is null or p_idx not in (14, 16, 18) or expiry >= class_start then
    raise exception 'El pago en línea cierra 32 minutos antes de la sesión.';
  end if;
  select * into profile from public.profiles where id = p_user for update;
  if not found then raise exception 'Completa tu perfil para reservar.'; end if;

  perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(pilot_date::text));
  if exists (select 1 from public.bookings
    where user_id = p_user and ds = pilot_date and status = 'active') then
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
    if hold.start_idx = p_idx and hold.amount = amount_due and hold.expires_at > clock_timestamp() + interval '31 minutes' then
      return hold;
    end if;
    raise exception 'Ya tienes un pago pendiente. Termínalo desde Stripe o espera a que venza.';
  end if;
  if public.david_pilot_remaining(p_idx) = 0 then
    raise exception 'Cupo lleno.';
  end if;

  insert into public.david_pilot_holds(user_id, start_idx, credits_used, amount, expires_at)
  values (p_user, p_idx, tickets_used, amount_due, expiry)
  returning * into hold;
  return hold;
end;
$$;

create or replace function public.finish_david_pilot(
  p_hold uuid, p_user uuid, p_stripe text, p_amount integer
)
returns boolean language plpgsql security definer set search_path = public
as $$
declare
  pilot_date constant date := date '2026-11-16';
  hold public.david_pilot_holds;
  profile public.profiles%rowtype;
  reservation uuid;
begin
  select * into profile from public.profiles where id = p_user for update;
  perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(pilot_date::text));
  select * into hold from public.david_pilot_holds where id = p_hold and user_id = p_user for update;
  if not found or hold.amount <> p_amount then return false; end if;
  if hold.stripe_id is not null then
    return hold.stripe_id = p_stripe and not hold.rejected;
  end if;
  if clock_timestamp() >= hold.expires_at
    or (profile.plan_id in ('im', 'gm') and profile.plan_expiry >= public.habit_slot_start(pilot_date, hold.start_idx))
    or exists (select 1 from public.bookings where user_id = p_user and ds = pilot_date and status = 'active')
    or (hold.credits_used = 1 and (coalesce(profile.credits, 0) not between 1 and 998
      or profile.plan_expiry < public.habit_slot_start(pilot_date, hold.start_idx))) then
    update public.david_pilot_holds set stripe_id = p_stripe, rejected = true where id = p_hold;
    return false;
  end if;

  insert into public.bookings
    (user_id, ds, start_idx, slots_used, time_str, dur_min, credit_charged, coach_david, david_credits_used)
  values
    (p_user, pilot_date, hold.start_idx, 2,
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

revoke all on function public.hold_david_pilot(uuid, integer, integer) from public;
revoke all on function public.finish_david_pilot(uuid, uuid, text, integer) from public;
grant execute on function public.hold_david_pilot(uuid, integer, integer) to service_role;
grant execute on function public.finish_david_pilot(uuid, uuid, text, integer) to service_role;

create or replace function public.keep_david_pilot_time()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if old.coach_david and (new.ds, new.start_idx, new.slots_used)
    is distinct from (old.ds, old.start_idx, old.slots_used) then
    raise exception 'Solicita el cambio de horario de tu sesión con David en recepción.';
  end if;
  if old.coach_david and old.status = 'active' and new.status = 'cancelled'
    and auth.uid() is not null and not exists (
      select 1 from public.profiles where id = auth.uid() and role in ('admin', 'reception')
    ) then
    raise exception 'Solicita la cancelación de tu sesión con David en recepción.';
  end if;
  if old.coach_david and old.status = 'active' and new.status = 'cancelled'
    and old.david_credits_used > 0 then
    update public.profiles set credits = credits + old.david_credits_used
    where id = old.user_id and credits < 999;
  end if;
  if old.coach_david and (new.coach_david, new.david_credits_used)
    is distinct from (old.coach_david, old.david_credits_used) then
    raise exception 'No se puede cambiar el cobro de esta reserva.';
  end if;
  return new;
end;
$$;

drop trigger if exists keep_david_pilot_time on public.bookings;
create trigger keep_david_pilot_time before update on public.bookings
for each row execute function public.keep_david_pilot_time();

revoke all on function public.david_pilot_slots() from public;
revoke all on function public.reserve_david_pilot(integer) from public;
grant execute on function public.david_pilot_slots() to authenticated;
grant execute on function public.reserve_david_pilot(integer) to authenticated;

-- Piloto Entrena con David: lunes 16 de noviembre, 07:00–10:00 Mazatlán.
-- Revisar con recepción las reservas existentes si este bloque reporta conflicto.
do $$
declare
  pilot_date constant date := date '2026-11-16';
  first_slot constant integer := 14;
  end_slot constant integer := 20;
  existing_id uuid;
begin
  perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(pilot_date::text));

  -- Vincula únicamente la reserva ya existente de Biodelys. Se mantienen su duración,
  -- ocupación original y cobro anterior. Cualquier discrepancia cancela la transacción.
  select b.id into strict existing_id
  from public.bookings b
  join public.profiles p on p.id = b.user_id
  where b.ds = pilot_date and b.start_idx = first_slot and b.slots_used = 3
    and b.status = 'active'
    and concat_ws(' ', p.name, p.reception_title) ilike '%biodelys%'
  for update of b;
  update public.bookings set coach_david = true where id = existing_id and not coach_david;

  if exists (
    select 1
    from public.bookings b
    where b.status = 'active' and not b.coach_david
      and b.ds between pilot_date - 1 and pilot_date
      and public.habit_slot_start(b.ds, b.start_idx)
        < public.habit_slot_start(pilot_date, end_slot)
      and public.habit_slot_start(pilot_date, first_slot)
        < public.habit_slot_start(b.ds, b.start_idx + coalesce(b.slots_used, 3))
  ) then
    raise exception 'Hay reservas activas que coinciden con Entrena con David. Revísalas en Agenda antes de bloquear.';
  end if;

  insert into public.slot_blocks as blocks (ds, slot_idx, spots, reason)
  select pilot_date, slot_idx, 4, 'Entrena con David'
  from generate_series(first_slot, end_slot - 1) as slots(slot_idx)
  on conflict (ds, slot_idx) do update
  set spots = excluded.spots,
      reason = excluded.reason || ' · ' || blocks.reason
  where blocks.spots < excluded.spots;
exception
  when no_data_found or too_many_rows then
    raise exception 'Confirma la reserva activa de Biodelys de 07:00 a 08:30 antes de habilitar el piloto.';
end;
$$;

commit;
