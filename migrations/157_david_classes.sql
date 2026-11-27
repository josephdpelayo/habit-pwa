begin;

-- Entrena con David deja de tener sus días escritos en el código (27 nov 2026).
--
-- Joseph pidió tres cosas:
--   1. El sábado 28 David solo da clase de 7 a 8 y de 8 a 9 (la de 9 se cierra y su
--      hora vuelve a la agenda normal).
--   2. Cada clase con David cuesta 1 boleto (antes 2): con boleto se descuenta uno,
--      sin boleto se paga una visita (110 MXN) en Stripe, con mensualidad no cuesta.
--   3. David abre y cierra sus clases desde su cuenta de admin (Admin → Agenda).
--
-- Hasta la 155 los días vivían en david_pilot_is_day() y las horas en (14, 16, 18)
-- repetidos en cinco funciones y en la API; abrir un día pedía una migración. Ahora
-- cada clase es una fila de david_classes, y las funciones la consultan.
--
-- Cerrar una clase = no acepta reservas nuevas. Si nadie la reservó (ni está pagando
-- en Stripe), la fila se borra y la hora se libera en la agenda; si ya hay reservas,
-- se quedan y la hora sigue bloqueada (cancelarlas es en Agenda, como siempre).

create table if not exists public.david_classes (
  ds date not null,
  start_idx integer not null check (start_idx between 0 and 46),
  spots integer not null default 3 check (spots between 1 and 4),
  is_open boolean not null default true,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (ds, start_idx)
);
alter table public.david_classes enable row level security;
revoke all on public.david_classes from anon, authenticated;
-- Sin políticas: la leen y escriben solo las funciones de abajo.

-- Historia: los días que ya hubo (16–20 y 24–27 nov, 7, 8 y 9 h) y el sábado 28 con
-- solo las de 7 y 8.
insert into public.david_classes (ds, start_idx)
select d::date, s.idx
from generate_series(date '2026-11-16', date '2026-11-27', interval '1 day') d
cross join (values (14), (16), (18)) s(idx)
where d::date between date '2026-11-16' and date '2026-11-20'
   or d::date between date '2026-11-24' and date '2026-11-27'
on conflict do nothing;
insert into public.david_classes (ds, start_idx) values
  (date '2026-11-28', 14), (date '2026-11-28', 16)
on conflict do nothing;

-- El apartado ya no se limita a días ni horas fijos: lo valida hold_david_pilot.
alter table public.david_pilot_holds drop constraint if exists david_pilot_holds_ds_check;
alter table public.david_pilot_holds drop constraint if exists david_pilot_holds_start_idx_check;
alter table public.david_pilot_holds drop constraint if exists david_pilot_holds_check;
alter table public.david_pilot_holds
  add constraint david_pilot_holds_start_idx_check check (start_idx between 0 and 46);
-- not valid: los apartados viejos se pagaron a dos boletos (22 000 centavos).
alter table public.david_pilot_holds
  add constraint david_pilot_holds_amount_check check (amount = (1 - credits_used) * 11000) not valid;

-- La 149 la creó para el check; queda por compatibilidad y ahora lee la tabla.
create or replace function public.david_pilot_is_day(p_ds date)
returns boolean language sql stable set search_path = public
as $$
  select exists (select 1 from public.david_classes c where c.ds = p_ds)
$$;
revoke all on function public.david_pilot_is_day(date) from public, anon, authenticated;

create or replace function public.david_class_is_open(p_ds date, p_idx integer)
returns boolean language sql stable set search_path = public
as $$
  select exists (select 1 from public.david_classes c
                 where c.ds = p_ds and c.start_idx = p_idx and c.is_open)
$$;
revoke all on function public.david_class_is_open(date, integer) from public, anon, authenticated;

-- Cupo: el de la clase (3 por defecto) y nunca más de 4 en el gym en esa hora.
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
    coalesce((select c.spots from public.david_classes c where c.ds = p_ds and c.start_idx = p_idx), 0)
      - (select count(*) from active where start_idx = p_idx),
    4 - (select max(used) from (
      select coalesce(sum(active.spots), 0) as used
      from generate_series(p_idx, p_idx + 1) as slot(idx)
      left join active on active.start_idx <= slot.idx and active.start_idx + active.slots_used > slot.idx
      group by slot.idx
    ) as occupancy)
  ) - public.david_pilot_held(p_ds, p_idx))::integer
$$;
revoke all on function public.david_pilot_remaining(date, integer) from public, anon, authenticated;

-- Cuántos boletos puede poner la persona en una clase: 1 si tiene mensualidad o al
-- menos un boleto vigente, 0 si no. (Antes hasta 2.)
create or replace function public.david_pilot_credits(p_profile public.profiles, p_starts_at timestamptz)
returns integer language sql immutable set search_path = public
as $$
  select case
    when p_profile.plan_id in ('im', 'gm') and p_profile.plan_expiry >= p_starts_at then 1
    when p_profile.credits between 1 and 998
      and (p_profile.plan_expiry is null or p_profile.plan_expiry >= p_starts_at)
      then 1
    else 0
  end
$$;
revoke all on function public.david_pilot_credits(public.profiles, timestamptz) from public, anon, authenticated;

-- Misma forma que antes (la app ya la lee). Salen las clases abiertas, y una cerrada
-- solo si la persona tiene lugar en ella.
create or replace function public.david_pilot_slots()
returns table(ds date, start_idx integer, remaining integer, reserved boolean, amount integer, payment_open boolean, credits_used integer)
language sql stable security definer set search_path = public
as $$
  select c.ds, c.start_idx,
         case when c.is_open then public.david_pilot_remaining(c.ds, c.start_idx) else 0 end,
         r.reserved,
         (1 - public.david_pilot_credits(p, t.starts_at)) * 11000,
         c.is_open and t.starts_at > now() + interval '32 minutes',
         case when p.plan_id in ('im', 'gm') and p.plan_expiry >= t.starts_at then 0
              else public.david_pilot_credits(p, t.starts_at) end
  from public.david_classes c
  join public.profiles p on p.id = auth.uid()
  cross join lateral (select public.habit_slot_start(c.ds, c.start_idx) as starts_at) t
  cross join lateral (select exists (
    select 1 from public.bookings b
    where b.ds = c.ds and b.start_idx = c.start_idx
      and b.user_id = p.id and b.coach_david and b.status = 'active') as reserved) r
  where t.starts_at > now() and (c.is_open or r.reserved)
  order by c.ds, c.start_idx
$$;
revoke all on function public.david_pilot_slots() from public, anon;
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
  class_start timestamptz;
begin
  if member_id is null or p_ds is null or p_start_idx is null then
    raise exception 'Horario inválido.';
  end if;

  select * into member_profile from public.profiles where id = member_id for update;
  perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(p_ds::text));
  class_start := public.habit_slot_start(p_ds, p_start_idx);

  select id into booking_id from public.bookings
  where user_id = member_id and ds = p_ds and status = 'active'
    and coach_david and start_idx = p_start_idx;
  if found then return booking_id; end if;

  if not public.david_class_is_open(p_ds, p_start_idx) then
    raise exception 'Esta clase ya no está abierta.';
  end if;
  if class_start <= clock_timestamp() then
    raise exception 'La sesión ya empezó.';
  end if;

  if member_profile.id is null or public.david_pilot_credits(member_profile, class_start) < 1 then
    raise exception 'Necesitas un boleto de clase o una mensualidad activa.';
  end if;
  tickets_used := case
    when member_profile.plan_id in ('im', 'gm') and member_profile.plan_expiry >= class_start then 0
    else 1
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
revoke all on function public.reserve_david_pilot(date, integer) from public, anon;
grant execute on function public.reserve_david_pilot(date, integer) to authenticated;

-- Sin boleto ni mensualidad: se aparta el lugar y se paga una visita en Stripe.
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
  if p_ds is null or p_idx is null then
    raise exception 'Horario inválido.';
  end if;
  class_start := public.habit_slot_start(p_ds, p_idx);
  if expiry >= class_start then
    raise exception 'El pago en línea cierra 32 minutos antes de la sesión.';
  end if;
  select * into profile from public.profiles where id = p_user for update;
  if not found then raise exception 'Completa tu perfil para reservar.'; end if;

  perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(p_ds::text));
  if not public.david_class_is_open(p_ds, p_idx) then
    raise exception 'Esta clase ya no está abierta.';
  end if;
  if exists (select 1 from public.bookings
    where user_id = p_user and ds = p_ds and status = 'active') then
    raise exception 'Ya tienes una reserva activa para este día.';
  end if;
  tickets_used := public.david_pilot_credits(profile, class_start);
  if tickets_used = 1 then
    raise exception 'Puedes reservar con tu mensualidad o con un boleto.';
  end if;
  amount_due := 11000;
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
  values (p_user, p_ds, p_idx, 0, amount_due, expiry)
  returning * into hold;
  return hold;
end;
$$;
revoke all on function public.hold_david_pilot(uuid, date, integer, integer) from public, anon, authenticated;
grant execute on function public.hold_david_pilot(uuid, date, integer, integer) to service_role;

-- finish_david_pilot no cambia: confirma lo que ya se apartó (si David cierra la clase
-- mientras alguien paga, ese lugar se respeta).

-- ── Lo que usa David desde Admin → Agenda ──────────────────────────────────────

-- Las clases de un día, con quién va.
create or replace function public.david_class_admin_day(p_ds date)
returns table(start_idx integer, spots integer, is_open boolean, booked integer, paying integer, names text[])
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_habit_admin() then
    raise exception 'Solo un admin puede ver las clases.';
  end if;
  return query
  select c.start_idx, c.spots, c.is_open,
         (select count(*)::integer from public.bookings b
          where b.ds = c.ds and b.start_idx = c.start_idx and b.coach_david and b.status = 'active'),
         public.david_pilot_held(c.ds, c.start_idx),
         coalesce((select array_agg(coalesce(nullif(p.name, ''), 'Socio') order by b.created_at)
                   from public.bookings b join public.profiles p on p.id = b.user_id
                   where b.ds = c.ds and b.start_idx = c.start_idx and b.coach_david and b.status = 'active'),
                  '{}'::text[])
  from public.david_classes c
  where c.ds = p_ds
  order by c.start_idx;
end;
$$;
revoke all on function public.david_class_admin_day(date) from public, anon;
grant execute on function public.david_class_admin_day(date) to authenticated;

-- Abrir (o reabrir) o cerrar una clase de 60 min. Abrirla bloquea su hora en la
-- agenda; cerrarla sin reservas la borra y libera esa hora.
create or replace function public.david_class_set(p_ds date, p_start_idx integer, p_open boolean)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  admin_id uuid := auth.uid();
  class_start timestamptz;
  booked integer;
  paying integer;
begin
  if not public.is_habit_admin() then
    raise exception 'Solo un admin puede abrir o cerrar clases.';
  end if;
  if p_ds is null or p_start_idx is null or p_start_idx not between 0 and 46 or p_open is null then
    raise exception 'Horario inválido.';
  end if;
  class_start := public.habit_slot_start(p_ds, p_start_idx);
  if class_start <= clock_timestamp() then
    raise exception 'Esa clase ya empezó.';
  end if;

  perform pg_advisory_xact_lock(hashtext('habit_booking_day'), hashtext(p_ds::text));

  if p_open then
    if exists (select 1 from public.david_classes c
               where c.ds = p_ds and c.start_idx <> p_start_idx
                 and c.start_idx < p_start_idx + 2 and p_start_idx < c.start_idx + 2) then
      raise exception 'Se encima con otra clase de ese día.';
    end if;
    if not exists (select 1 from public.david_classes c where c.ds = p_ds and c.start_idx = p_start_idx)
      and exists (
      select 1 from public.bookings b
      where b.status = 'active' and not b.coach_david
        and b.ds between p_ds - 1 and p_ds
        and public.habit_slot_start(b.ds, b.start_idx) < public.habit_slot_start(p_ds, p_start_idx + 2)
        and class_start < public.habit_slot_start(b.ds, b.start_idx + coalesce(b.slots_used, 3))
    ) then
      raise exception 'Ya hay socios reservados a esa hora. Revisa la agenda antes de abrir la clase.';
    end if;

    insert into public.david_classes as c (ds, start_idx, is_open, updated_by)
    values (p_ds, p_start_idx, true, admin_id)
    on conflict (ds, start_idx) do update
      set is_open = true, updated_by = admin_id, updated_at = now();

    insert into public.slot_blocks as blocks (ds, slot_idx, spots, reason)
    select p_ds, slot_idx, 4, 'Entrena con David'
    from generate_series(p_start_idx, p_start_idx + 1) as slots(slot_idx)
    on conflict (ds, slot_idx) do update
    set spots = excluded.spots,
        reason = excluded.reason || ' · ' || blocks.reason
    where blocks.spots < excluded.spots;
    return 'opened';
  end if;

  if not exists (select 1 from public.david_classes c where c.ds = p_ds and c.start_idx = p_start_idx) then
    return 'removed';
  end if;

  select count(*)::integer into booked from public.bookings b
  where b.ds = p_ds and b.start_idx = p_start_idx and b.coach_david and b.status = 'active';
  paying := public.david_pilot_held(p_ds, p_start_idx);

  if booked > 0 or paying > 0 then
    update public.david_classes
      set is_open = false, updated_by = admin_id, updated_at = now()
      where ds = p_ds and start_idx = p_start_idx;
    return 'closed';
  end if;

  delete from public.david_classes where ds = p_ds and start_idx = p_start_idx;
  delete from public.slot_blocks
  where ds = p_ds and slot_idx in (p_start_idx, p_start_idx + 1) and reason = 'Entrena con David';
  return 'removed';
end;
$$;
revoke all on function public.david_class_set(date, integer, boolean) from public, anon;
grant execute on function public.david_class_set(date, integer, boolean) to authenticated;

-- Sábado 28: la clase de 9 no existe; su hora (9:00–10:00) vuelve a la agenda.
delete from public.slot_blocks
where ds = date '2026-11-28' and slot_idx in (18, 19) and reason = 'Entrena con David'
  and not exists (select 1 from public.bookings b
                  where b.ds = date '2026-11-28' and b.start_idx = 18 and b.coach_david and b.status = 'active');

commit;
