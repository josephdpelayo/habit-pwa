-- Programas del lado del coach.
--
-- La migración 070 creó coaching_programs / coaching_program_days pensándolos
-- solo para el socio: el admin quedó con políticas `for select`. El resultado es
-- que el coach no puede armarle un programa a su cliente ni reutilizar el mismo
-- plan con dos personas — tiene que rehacer la semana día por día en cada uno.
--
-- Esta migración añade dos cosas y nada más:
--   (a) el coach escribe programas de sus clientes;
--   (b) un programa con user_id null es una PLANTILLA DEL GYM: no es de nadie,
--       no se "sigue", se copia sobre un cliente. Es el mismo truco que
--       boards.owner_id null (070) y que skandi_foods.user_id null (073).

-- ─────────────────────────────────────────────────────────────────────────────
-- (a) De quién es el programa y quién lo hizo
-- ─────────────────────────────────────────────────────────────────────────────
-- created_by distingue lo que armó el coach de lo que se armó el socio, igual
-- que en coaching_week_templates. Sin esto el coach no puede saber si el
-- programa activo se lo puso él o se lo cambió el cliente.
alter table public.coaching_programs
  add column if not exists created_by uuid references public.profiles(id) on delete set null;

-- Una plantilla del gym no pertenece a ningún socio.
alter table public.coaching_programs
  alter column user_id drop not null;

-- ...y por lo mismo nunca puede estar "activa": activo significa "es la semana
-- que este socio está siguiendo", y una plantilla no la sigue nadie.
do $$
begin
  alter table public.coaching_programs drop constraint if exists coaching_programs_template_not_active;
  alter table public.coaching_programs
    add constraint coaching_programs_template_not_active
    check (user_id is not null or is_active = false);
end $$;

-- El índice único de "un solo programa activo por socio" ya ignora los NULL
-- (idx_coaching_programs_one_active, migración 070), así que las plantillas del
-- gym conviven sin pelearse por él.

create index if not exists idx_coaching_programs_gym
  on public.coaching_programs(name) where user_id is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- (b) Políticas
-- ─────────────────────────────────────────────────────────────────────────────
-- Admin escribe todo (antes solo leía). La política del socio sobre lo suyo
-- (070) se queda igual: user_id = auth.uid() nunca casa con una plantilla del
-- gym, así que un socio no puede tocarlas.
drop policy if exists "Admin view all programs" on public.coaching_programs;
drop policy if exists "Admin manage programs" on public.coaching_programs;
create policy "Admin manage programs"
  on public.coaching_programs for all
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

-- Las plantillas del gym las lee cualquier autenticado, como los pizarrones del
-- gym: son el catálogo compartido del que sale un plan.
drop policy if exists "Auth users read gym program templates" on public.coaching_programs;
create policy "Auth users read gym program templates"
  on public.coaching_programs for select
  using (auth.uid() is not null and user_id is null);

drop policy if exists "Admin view all program days" on public.coaching_program_days;
drop policy if exists "Admin manage program days" on public.coaching_program_days;
create policy "Admin manage program days"
  on public.coaching_program_days for all
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

drop policy if exists "Auth users read gym program template days" on public.coaching_program_days;
create policy "Auth users read gym program template days"
  on public.coaching_program_days for select
  using (auth.uid() is not null and exists(
    select 1 from public.coaching_programs p
    where p.id = program_id and p.user_id is null
  ));

-- ─────────────────────────────────────────────────────────────────────────────
-- (c) Aplicar un programa a un socio, de una sola pieza
-- ─────────────────────────────────────────────────────────────────────────────
-- Aplicar un programa son cuatro escrituras que tienen que pasar juntas: borrar
-- la semana base, escribir la del programa, desactivar el programa anterior y
-- activar este. Hacerlas sueltas desde el cliente (que es lo que hace hoy
-- applyProgramSb del socio) deja al socio sin semana si falla la de en medio.
--
-- p_program_id puede ser una plantilla del gym: en ese caso se copia a un
-- programa nuevo del socio, porque una plantilla no se "activa", se usa.
create or replace function public.apply_coaching_program(p_user_id uuid, p_program_id uuid, p_week_start date, p_today date default null)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_is_admin boolean;
  v_program  public.coaching_programs%rowtype;
  v_target   uuid;
begin
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
    into v_is_admin;
  if auth.uid() <> p_user_id and not v_is_admin then
    raise exception 'not authorized';
  end if;

  select * into v_program from public.coaching_programs where id = p_program_id;
  if not found then
    raise exception 'programa no encontrado';
  end if;
  if v_program.user_id is not null and v_program.user_id <> p_user_id then
    raise exception 'ese programa es de otro socio';
  end if;

  if v_program.user_id is null then
    -- Plantilla del gym: se copia. El socio se queda con su propia versión, que
    -- puede editar sin tocar la plantilla compartida.
    insert into public.coaching_programs (user_id, name, notes, is_active, created_by)
    values (p_user_id, v_program.name, v_program.notes, false, auth.uid())
    returning id into v_target;

    insert into public.coaching_program_days (program_id, dow, board_id, board_name, board_color)
    select v_target, dow, board_id, board_name, board_color
    from public.coaching_program_days where program_id = v_program.id;
  else
    v_target := v_program.id;
  end if;

  -- La semana se reescribe entera, no solo los días que el programa nombra: un
  -- día que el programa deja libre tiene que quedar libre de verdad, si no la
  -- semana queda mezclada con lo que había del programa anterior.
  delete from public.coaching_week_templates where user_id = p_user_id;

  insert into public.coaching_week_templates (user_id, dow, board_id, board_name, board_color, created_by)
  select p_user_id, dow, board_id, board_name, board_color, auth.uid()
  from public.coaching_program_days where program_id = v_target;

  update public.coaching_programs set is_active = false
    where user_id = p_user_id and is_active and id <> v_target;
  update public.coaching_programs set is_active = true, updated_at = now()
    where id = v_target;

  -- Lo ya materializado desde la base anterior sobra: solo lo que nadie ha
  -- tocado (scheduled y nacido de la base) y de hoy en adelante. El "hoy" lo
  -- manda el cliente porque current_date aquí es UTC, y en Mazatlán eso ya es
  -- mañana a partir de las cinco de la tarde.
  delete from public.coaching_schedule
   where user_id = p_user_id
     and ds >= greatest(p_week_start, coalesce(p_today, current_date))
     and status = 'scheduled'
     and generated_from_base;

  perform public.ensure_coaching_week_from_template(p_user_id, p_week_start);

  return v_target;
end;
$$;

grant execute on function public.apply_coaching_program(uuid, uuid, date, date) to authenticated;
