begin;

-- Joseph pidió (24 nov 2026) abrir Entrena con David también el sábado 28 de
-- noviembre, con los mismos horarios (7, 8 y 9 h, 3 lugares) y el mismo bloqueo de
-- 7:00 a 10:00 en la agenda. Como dejó la 149: cambiar david_pilot_is_day() y
-- bloquear la agenda. david_pilot_slots() recorría 12 días desde el 16 (hasta el
-- 27); ahora recorre 13 para llegar al 28.

create or replace function public.david_pilot_is_day(p_ds date)
returns boolean language sql immutable set search_path = public
as $$
  select p_ds between date '2026-11-16' and date '2026-11-20'
      or p_ds between date '2026-11-24' and date '2026-11-28'
$$;
revoke all on function public.david_pilot_is_day(date) from public;

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
  from generate_series(0, 12) as offsets(day_offset)
  cross join lateral (select date '2026-11-16' + offsets.day_offset as day) d
  cross join (values (14), (16), (18)) as s(idx)
  join public.profiles p on p.id = auth.uid()
  cross join lateral (select public.habit_slot_start(d.day, s.idx) as starts_at) t
  where public.david_pilot_is_day(d.day) and t.starts_at > now()
  order by d.day, s.idx
$$;
revoke all on function public.david_pilot_slots() from public, anon;
grant execute on function public.david_pilot_slots() to authenticated;

-- Bloquea el sábado 28 de 7:00 a 10:00, como la 149 hizo con 24–27.
do $$
declare
  d constant date := date '2026-11-28';
  first_slot constant integer := 14;
  end_slot constant integer := 20;
begin
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
end;
$$;

commit;
