-- Coaching de HABIT: el programa se vuelve un ciclo con fechas.
--
-- Hasta la 114 un programa era una FOTO de una semana: se aplicaba copiándolo a
-- coaching_week_templates y ahí moría. Por eso no podía decir cuánto dura, no
-- podía tener una semana distinta de otra (una descarga), y "¿en qué semana del
-- bloque va este cliente?" no tenía respuesta en ninguna parte.
--
-- Esta migración invierte la propiedad, igual que la 102 hizo en Skandi Fit:
-- un programa activo CON start_date pasa a ser la fuente de la verdad del
-- calendario, semana por semana. coaching_week_templates NO se retira: sigue
-- siendo el camino completo para quien no tiene programa fechado (que es todo el
-- mundo hasta que alguien ponga una fecha) y el respaldo que el socio ve en su
-- vista Semana. start_date es el interruptor: sin él, nada cambia.
--
-- Las tres lecciones que dejó la regresión de Skandi (ver migración 109) y que
-- aquí se respetan desde el principio:
--   · la regla de resolución vive en UNA función (coaching_week_slots), no
--     copiada en cada consulta que la necesita;
--   · la guarda del pasado envuelve solo el estampado, nunca la función entera;
--   · el ciclo no se repite solo por calendario — terminar un bloque es el
--     momento de reevaluar, no de volver a empezar en automático.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. El programa aprende a durar
-- ─────────────────────────────────────────────────────────────────────────────
-- weeks es la longitud TOTAL del ciclo, descarga incluida. No hay un booleano
-- `deload_week` aparte como en Skandi: qué es cada semana lo dice su fase en
-- coaching_program_weeks, que es más expresivo y ahorra la aritmética de sumar
-- una semana fantasma al final.
alter table public.coaching_programs
  add column if not exists weeks      integer not null default 4 check (weeks between 1 and 16),
  add column if not exists start_date date;

-- Una plantilla del gym (user_id null, migración 114) describe un plan, no un
-- ciclo de nadie: no puede tener fecha de arranque.
do $$
begin
  alter table public.coaching_programs drop constraint if exists coaching_programs_template_no_start;
  alter table public.coaching_programs
    add constraint coaching_programs_template_no_start
    check (user_id is not null or start_date is null);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Los días aprenden a variar por semana del ciclo
-- ─────────────────────────────────────────────────────────────────────────────
-- week_index = 0 significa "se repite todas las semanas". Un programa normal
-- sigue siendo las mismas filas con 0; uno con descarga agrega filas con
-- week_index = N solo donde la semana N se aparta.
--
-- La resolución es de REEMPLAZO, no de mezcla: si existe cualquier fila
-- (week_index = N, dow = D), esa fila es el día completo; si no, manda la de 0.
-- Mezclar por ranura daría un martes hecho de dos semanas distintas, que no es
-- lo que nadie quiere decir al escribir "en la semana 5 el martes es otra cosa".
--
-- De ahí sale una consecuencia que hay que sostener en todas partes: una fila
-- con board_id null es un MARCADOR DE DÍA LIBRE, no una fila a medias. Es la
-- única forma de decir "en la semana 5 el viernes se descansa" — borrar la fila
-- haría que ese día volviera a heredarse de las de 0. El estampado las ignora.
alter table public.coaching_program_days
  add column if not exists week_index integer not null default 0 check (week_index between 0 and 16);

-- El unique(program_id, dow) inline de la 070 es justo lo que topaba un programa
-- a una sola semana. Se busca por columnas porque la 070 lo creó sin nombrarlo.
do $$
declare v_name text;
begin
  select con.conname into v_name
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public' and rel.relname = 'coaching_program_days'
    and con.contype = 'u'
    and (select array_agg(att.attname::text order by att.attname)
         from unnest(con.conkey) k
         join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k)
        = array['dow','program_id'];
  if v_name is not null then
    execute format('alter table public.coaching_program_days drop constraint %I', v_name);
  end if;
end $$;

create unique index if not exists idx_coaching_program_days_slot
  on public.coaching_program_days(program_id, week_index, dow);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Qué es cada semana del ciclo
-- ─────────────────────────────────────────────────────────────────────────────
-- No es otra jerarquía encima de week_index: solo describe la semana que ese
-- índice ya define. Sin fila, la semana es 'acumulacion' — que es lo que una
-- semana normal es.
create table if not exists public.coaching_program_weeks (
  id         uuid primary key default uuid_generate_v4(),
  program_id uuid references public.coaching_programs(id) on delete cascade not null,
  week_index integer not null check (week_index between 1 and 16),
  phase      text not null default 'acumulacion'
               check (phase in ('acumulacion','intensificacion','descarga','test')),
  note       text,
  created_at timestamptz not null default now(),
  unique(program_id, week_index)
);

create index if not exists idx_coaching_program_weeks_program
  on public.coaching_program_weeks(program_id, week_index);

alter table public.coaching_program_weeks enable row level security;

drop policy if exists "Users manage own program weeks" on public.coaching_program_weeks;
create policy "Users manage own program weeks"
  on public.coaching_program_weeks for all
  using (exists(select 1 from public.coaching_programs p
                 where p.id = program_id and p.user_id = auth.uid()))
  with check (exists(select 1 from public.coaching_programs p
                      where p.id = program_id and p.user_id = auth.uid()));

drop policy if exists "Admin manage program weeks" on public.coaching_program_weeks;
create policy "Admin manage program weeks"
  on public.coaching_program_weeks for all
  using (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'))
  with check (exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'));

drop policy if exists "Auth users read gym program weeks" on public.coaching_program_weeks;
create policy "Auth users read gym program weeks"
  on public.coaching_program_weeks for select
  using (auth.uid() is not null and exists(
    select 1 from public.coaching_programs p
    where p.id = program_id and p.user_id is null
  ));

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. El calendario recuerda de qué ciclo salió cada día
-- ─────────────────────────────────────────────────────────────────────────────
-- Sin esto, medir "cómo le fue en la semana 3 del bloque" es imposible en cuanto
-- el cliente pasa al siguiente programa: la fecha sola no dice a qué ciclo
-- pertenecía. on delete set null porque borrar un programa no debe borrar la
-- historia de lo que se entrenó siguiéndolo.
alter table public.coaching_schedule
  add column if not exists program_id uuid references public.coaching_programs(id) on delete set null,
  add column if not exists program_week_index integer
    check (program_week_index is null or program_week_index between 0 and 16);

create index if not exists idx_coaching_schedule_program_cycle
  on public.coaching_schedule(program_id, program_week_index, ds)
  where program_id is not null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. La semana efectiva, en un solo lugar
-- ─────────────────────────────────────────────────────────────────────────────
-- Contesta "¿qué toca cada día de ESTA semana?" y es el único sitio donde vive
-- la regla de resolución. La usan el borrado de lo obsoleto y el estampado;
-- tenerla como función y no como dos consultas copiadas es lo que impide que un
-- día se contradigan entre sí.
--
-- Con p_program null devuelve la semana base, sin programa de por medio: el
-- estampado es una sola consulta en los dos modos, no dos ramas paralelas.
--
-- security INVOKER a propósito, al revés que el RPC que la llama: desde el RPC
-- (que sí es definer) corre con los permisos del definer, y llamada directo por
-- un cliente cae bajo RLS. Definer aquí dejaría que cualquier autenticado
-- pasara el uid de otro y leyera qué rutina tiene cada quién cada día.
create or replace function public.coaching_week_slots(p_uid uuid, p_program uuid, p_week_index integer)
returns table(dow integer, board_id uuid, board_name text, board_color text)
language sql
stable
set search_path = public
as $$
  select d.dow, d.board_id, d.board_name, d.board_color
  from public.coaching_program_days d
  where p_program is not null
    and p_week_index >= 0
    and d.program_id = p_program
    and (
      d.week_index = p_week_index
      or (d.week_index = 0 and not exists (
            select 1 from public.coaching_program_days o
            where o.program_id = p_program
              and o.week_index = p_week_index
              and o.dow = d.dow))
    )
  union all
  select t.dow, t.board_id, t.board_name, t.board_color
  from public.coaching_week_templates t
  where p_program is null and t.user_id = p_uid;
$$;

grant execute on function public.coaching_week_slots(uuid, uuid, integer) to authenticated;

-- En qué semana del ciclo cae una fecha. Devuelve 0 si no hay ciclo vigente y
-- -1 si el ciclo ya terminó — los dos casos en los que coaching_week_slots no
-- devuelve nada del programa.
create or replace function public.coaching_program_week_index(p_program uuid, p_week_start date)
returns integer
language plpgsql
stable
set search_path = public
as $$
declare
  v_start date;
  v_weeks integer;
  v_mon   date;
  v_idx   integer;
begin
  if p_program is null then return 0; end if;
  select p.start_date, p.weeks into v_start, v_weeks
  from public.coaching_programs p where p.id = p_program;
  if v_start is null then return 0; end if;

  v_mon   := p_week_start - (extract(isodow from p_week_start)::int - 1);
  v_start := v_start - (extract(isodow from v_start)::int - 1);
  if v_mon < v_start then return 0; end if;

  v_idx := ((v_mon - v_start) / 7) + 1;
  -- Pasada la última semana el índice se vuelve -1 y el estampado se detiene de
  -- verdad. Nunca se pide 0 como semana concreta: 0 es "todas las semanas" y
  -- pedirlo así anularía su papel de respaldo.
  if v_idx > greatest(1, coalesce(v_weeks, 4)) then return -1; end if;
  return v_idx;
end;
$$;

grant execute on function public.coaching_program_week_index(uuid, date) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. El estampado sale del programa activo
-- ─────────────────────────────────────────────────────────────────────────────
-- Reemplaza el cuerpo de la 039. Cambia de dónde sale la semana (del programa
-- fechado si lo hay, de la plantilla si no) y añade el borrado de lo que quedó
-- obsoleto, que es lo que hace que editar el plan se propague hacia adelante
-- sin que nadie tenga que ir a limpiar semanas a mano.
--
-- Lo que NUNCA se toca: un día ya entrenado o en curso, un descanso puesto a
-- mano (status 'skipped') y un cambio de solo-esta-semana del coach
-- (generated_from_base = false). El borrado se limita a lo que nació de la base
-- y sigue intacto.
create or replace function public.ensure_coaching_week_from_template(p_user_id uuid, p_week_start date)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_is_admin boolean;
  v_monday   date;
  v_program  uuid;
  v_index    integer := 0;
begin
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
    into v_is_admin;

  if auth.uid() <> p_user_id and not v_is_admin then
    raise exception 'not authorized';
  end if;

  -- Ancla al lunes real de esa semana pase lo que pase el cliente.
  v_monday := p_week_start - (extract(isodow from p_week_start)::int - 1);

  -- El pasado no se materializa: un plan inventado hacia atrás no es historia y
  -- ensucia la adherencia de semanas ya cerradas. "Hoy" se resuelve en
  -- America/Mazatlan y no con current_date, que es UTC: un domingo después de
  -- las cinco de la tarde el servidor ya cree que es lunes y daría por cerrada
  -- la semana que el socio todavía está viviendo.
  if v_monday < date_trunc('week', (now() at time zone 'America/Mazatlan')::date)::date then
    return;
  end if;

  -- ¿Manda un programa esta semana? Solo si está activo, tiene fecha, y esa
  -- fecha ya llegó: un programa que arranca el mes que viene no gobierna hoy.
  select p.id into v_program
  from public.coaching_programs p
  where p.user_id = p_user_id and p.is_active and p.start_date is not null
  limit 1;

  if v_program is not null then
    v_index := public.coaching_program_week_index(v_program, v_monday);
    -- Antes de que arranque el ciclo manda la plantilla, como siempre.
    if v_index = 0 then v_program := null; end if;
  end if;

  -- 1) Fuera lo estampado que ya no corresponde y que nadie tocó: la rutina se
  -- movió de día, el programa cambió, o esta semana del ciclo dice otra cosa.
  delete from public.coaching_schedule s
  where s.user_id = p_user_id
    and s.ds between v_monday and v_monday + 6
    and s.status = 'scheduled'
    and s.generated_from_base
    and not exists (
      select 1 from public.coaching_week_slots(p_user_id, v_program, v_index) w
      where w.dow = (s.ds - v_monday) and w.board_id is not distinct from s.board_id
    );

  -- 2) Y se estampa lo que falta. El guard por base_template_dow es el mismo de
  -- la 039: es lo que respeta un descanso 'skipped' de una sola semana, que
  -- ocupa ese hueco a propósito.
  insert into public.coaching_schedule (
    user_id, board_id, board_name, board_color, ds,
    status, created_by, generated_from_base, base_template_dow,
    program_id, program_week_index
  )
  select
    p_user_id, w.board_id, w.board_name, w.board_color, v_monday + w.dow,
    'scheduled', auth.uid(), true, w.dow,
    v_program, case when v_program is null then null else v_index end
  from public.coaching_week_slots(p_user_id, v_program, v_index) w
  where w.board_id is not null
    and not exists (
      select 1 from public.coaching_schedule s
      where s.user_id = p_user_id
        and s.ds = v_monday + w.dow
        and s.base_template_dow = w.dow
    )
    and not exists (
      select 1 from public.coaching_schedule s
      where s.user_id = p_user_id
        and s.ds = v_monday + w.dow
        and s.board_id = w.board_id
        and s.status in ('scheduled','in_progress','done')
    );
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Aplicar un programa, ahora con fecha de arranque
-- ─────────────────────────────────────────────────────────────────────────────
-- Misma función de la 114 más p_start_date: pasarla es lo que convierte el
-- programa en un ciclo. Pasar null lo deja como estaba (una semana que se
-- repite), que sigue siendo un uso legítimo.
-- La 114 dejó esta función con cuatro argumentos. Añadir el quinto con un
-- create-or-replace no la reemplaza: crea una SOBRECARGA, y una llamada de
-- cuatro argumentos encajaría en las dos, que es como PostgREST devuelve
-- "Could not choose the best candidate function". Se retira la vieja primero.
drop function if exists public.apply_coaching_program(uuid, uuid, date, date);

create or replace function public.apply_coaching_program(
  p_user_id uuid, p_program_id uuid, p_week_start date,
  p_today date default null, p_start_date date default null)
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
    insert into public.coaching_programs (user_id, name, notes, is_active, created_by, weeks)
    values (p_user_id, v_program.name, v_program.notes, false, auth.uid(), v_program.weeks)
    returning id into v_target;

    insert into public.coaching_program_days (program_id, week_index, dow, board_id, board_name, board_color)
    select v_target, week_index, dow, board_id, board_name, board_color
    from public.coaching_program_days where program_id = v_program.id;

    insert into public.coaching_program_weeks (program_id, week_index, phase, note)
    select v_target, week_index, phase, note
    from public.coaching_program_weeks where program_id = v_program.id;
  else
    v_target := v_program.id;
  end if;

  if p_start_date is not null then
    update public.coaching_programs set start_date = p_start_date where id = v_target;
  end if;

  -- La semana base se reescribe entera desde la semana 1 del ciclo (o desde las
  -- filas de "todas las semanas" si no hay una semana 1 propia). Sigue siendo lo
  -- que ve el socio en su vista Semana y el respaldo si el ciclo termina.
  delete from public.coaching_week_templates where user_id = p_user_id;

  insert into public.coaching_week_templates (user_id, dow, board_id, board_name, board_color, created_by)
  select p_user_id, w.dow, w.board_id, w.board_name, w.board_color, auth.uid()
  from public.coaching_week_slots(p_user_id, v_target, 1) w
  where w.board_id is not null;

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

grant execute on function public.apply_coaching_program(uuid, uuid, date, date, date) to authenticated;

commit;
