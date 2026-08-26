-- Skandi Fit: dos programas activos a la vez -- fuerza y resistencia como pistas
-- independientes, cada una con su propio ciclo (fecha de inicio, semanas, descarga), que se ven
-- juntas en el calendario. Antes solo un programa podía mandar sobre la semana entera
-- (idx_skandi_programs_one_active, migración 069): un objeto mezclaba fuerza y resistencia el
-- mismo día, y activar uno reemplazaba al otro sin importar de qué se trataba.
--
-- Punto de partida: el cuerpo de skandi_ensure_week que dejó la 109 (la que reparó la
-- regresión de la 104). Esta migración lo EXTIENDE, no lo vuelve a escribir -- exactamente la
-- lección que costó la 104: partir de una copia vieja en vez del cuerpo vigente borró en
-- silencio toda la resolución por programa durante semanas sin que nadie lo notara.

begin;

-- ---------------------------------------------------------------------------------------
-- 1. El programa aprende de qué disciplina es dueño.
-- ---------------------------------------------------------------------------------------
-- 'mixed' por default: todo programa que ya existe (incluidos los que ya están activos) sigue
-- mandando sobre fuerza y resistencia igual que hoy, sin tocarle nada a nadie.
alter table public.skandi_programs
  add column if not exists track text not null default 'mixed'
    check (track in ('strength','endurance','mixed'));

-- Antes: como máximo un programa activo por usuario, sin importar de qué se trataba. Ahora:
-- como máximo uno activo por pista exacta -- pero eso solo evita fuerza-contra-fuerza y
-- resistencia-contra-resistencia. Un mixto activo junto a cualquiera de los dos duplicaría el
-- estampado del mismo día (el mixto ya lo cubre completo), y esa regla cruzada no cabe en un
-- índice parcial -- la cierra el trigger de abajo, mismo patrón que
-- skandi_planned_link_program (103).
drop index if exists idx_skandi_programs_one_active;
create unique index if not exists idx_skandi_programs_one_active_per_track
  on public.skandi_programs(user_id, track) where is_active;

create or replace function public.skandi_programs_track_exclusive()
returns trigger
language plpgsql
as $$
begin
  if new.is_active then
    if new.track = 'mixed' then
      if exists (
        select 1 from public.skandi_programs
        where user_id = new.user_id and is_active and id <> new.id
      ) then
        raise exception 'A mixed program cannot be active alongside another active program.';
      end if;
    else
      if exists (
        select 1 from public.skandi_programs
        where user_id = new.user_id and is_active and id <> new.id and track = 'mixed'
      ) then
        raise exception 'Cannot activate a % program while a mixed program is active.', new.track;
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_skandi_programs_track_exclusive on public.skandi_programs;
create trigger trg_skandi_programs_track_exclusive
  before insert or update of is_active, track on public.skandi_programs
  for each row execute function public.skandi_programs_track_exclusive();

-- ---------------------------------------------------------------------------------------
-- 2. skandi_ensure_week resuelve hasta dos programas: el que gobierna fuerza y el que
--    gobierna resistencia, cada uno con su propio ciclo (pueden empezar en fechas distintas,
--    durar distinto, tener su propia semana de descarga -- no están sincronizados a propósito).
--
--    skandi_week_slots (102) NO cambia: cada rama la llama filtrando a su propia columna, así
--    que un programa mixto (que satisface las dos búsquedas con el mismo id) no se estampa dos
--    veces -- la rama de fuerza se queda solo con sus filas de template_id, la de resistencia
--    solo con las de activity_template_id.
-- ---------------------------------------------------------------------------------------

create or replace function public.skandi_ensure_week(p_week_start date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_monday     date;
  v_inserted   integer := 0;
  v_n          integer := 0;

  -- Programa dueño de la fuerza (track 'strength' o 'mixed').
  v_prog_s     uuid;
  v_start_s    date;
  v_weeks_s    integer;
  v_deload_s   boolean;
  v_cycle_s    integer;
  v_widx_s     integer := 0;

  -- Programa dueño de la resistencia (track 'endurance' o 'mixed'). Si ambas búsquedas
  -- resuelven al mismo id (mixto), v_widx_s y v_widx_e salen idénticos: misma fila, mismos
  -- datos, el trigger de la sección 1 garantiza que nunca son dos programas distintos a la vez.
  v_prog_e     uuid;
  v_start_e    date;
  v_weeks_e    integer;
  v_deload_e   boolean;
  v_cycle_e    integer;
  v_widx_e     integer := 0;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Ancla al lunes real de esa semana (isodow: lunes = 1), pase lo que pase el cliente.
  v_monday := p_week_start - (extract(isodow from p_week_start)::int - 1);

  select p.id, p.start_date, p.weeks, p.deload_week
    into v_prog_s, v_start_s, v_weeks_s, v_deload_s
  from public.skandi_programs p
  where p.user_id = v_uid and p.is_active and p.start_date is not null
    and p.track in ('strength', 'mixed')
  limit 1;

  select p.id, p.start_date, p.weeks, p.deload_week
    into v_prog_e, v_start_e, v_weeks_e, v_deload_e
  from public.skandi_programs p
  where p.user_id = v_uid and p.is_active and p.start_date is not null
    and p.track in ('endurance', 'mixed')
  limit 1;

  -- Un programa que arranca el mes que viene no gobierna la semana de hoy: se trata como si no
  -- existiera (cae a weekday) hasta que su fecha llegue.
  if v_prog_s is not null then
    v_start_s := v_start_s - (extract(isodow from v_start_s)::int - 1);
    if v_monday < v_start_s then
      v_prog_s := null;
    else
      v_cycle_s := greatest(1, coalesce(v_weeks_s, 4) + case when coalesce(v_deload_s, true) then 1 else 0 end);
      v_widx_s := ((v_monday - v_start_s) / 7) + 1;
      -- Un ciclo NO se repite solo por calendario (066, 102): pasada la última semana el
      -- índice se vuelve -1, y skandi_week_slots no devuelve filas para un índice negativo con
      -- programa no nulo -- el ciclo se detiene de verdad, no se materializa nada.
      if v_widx_s > v_cycle_s then
        v_widx_s := -1;
      end if;
    end if;
  end if;

  if v_prog_e is not null then
    v_start_e := v_start_e - (extract(isodow from v_start_e)::int - 1);
    if v_monday < v_start_e then
      v_prog_e := null;
    else
      v_cycle_e := greatest(1, coalesce(v_weeks_e, 4) + case when coalesce(v_deload_e, true) then 1 else 0 end);
      v_widx_e := ((v_monday - v_start_e) / 7) + 1;
      if v_widx_e > v_cycle_e then
        v_widx_e := -1;
      end if;
    end if;
  end if;

  -- El pasado no se materializa (096): esto NO corta la función entera, solo salta el
  -- estampado. La reconciliación de arrastre, más abajo, corre para cualquier semana.
  if v_monday >= date_trunc('week', current_date)::date then

    -- 1) Fuera lo estampado que quedó obsoleto y que nadie tocó -- la rutina se movió de día,
    -- se desasignó, se borró, o el programa que la gobierna cambió. Cada columna se revisa
    -- contra SU pista: una fila de fuerza contra v_prog_s/v_widx_s, una de resistencia contra
    -- v_prog_e/v_widx_e.
    delete from public.skandi_planned_sessions p
    where p.user_id = v_uid
      and p.day between v_monday and v_monday + 6
      and p.source in ('template', 'program')
      and p.is_edited = false
      and p.status = 'planned'
      and p.completed_at is null
      and p.session_id is null
      and p.activity_id is null
      and (
        (p.template_id is not null and not exists (
           select 1 from public.skandi_week_slots(v_uid, v_prog_s, v_widx_s) s
           where s.template_id = p.template_id and s.weekday = (p.day - v_monday)))
        or (p.activity_template_id is not null and not exists (
           select 1 from public.skandi_week_slots(v_uid, v_prog_e, v_widx_e) s
           where s.activity_template_id = p.activity_template_id and s.weekday = (p.day - v_monday)))
        or (p.template_id is null and p.activity_template_id is null)
      );
    get diagnostics v_n = row_count;
    v_inserted := v_inserted + v_n;

    -- Si la misma rutina/plan quedó en el mismo día al cambiar de weekday a programa (o al
    -- revés, o de un programa a otro dentro de su misma pista), no se borra ni se reinserta.
    -- Aun así su origen debe decir quién manda ahora -- por columna, cada una contra su pista.
    update public.skandi_planned_sessions p
    set source = case
          when p.template_id is not null then (case when v_prog_s is null then 'template' else 'program' end)
          else (case when v_prog_e is null then 'template' else 'program' end)
        end
    where p.user_id = v_uid
      and p.day between v_monday and v_monday + 6
      and p.source in ('template', 'program')
      and p.is_edited = false and p.status = 'planned'
      and p.completed_at is null and p.session_id is null and p.activity_id is null
      and (
        (p.template_id is not null
          and p.source is distinct from (case when v_prog_s is null then 'template' else 'program' end)
          and exists (
            select 1 from public.skandi_week_slots(v_uid, v_prog_s, v_widx_s) s
            where s.template_id = p.template_id and s.weekday = (p.day - v_monday)))
        or (p.activity_template_id is not null
          and p.source is distinct from (case when v_prog_e is null then 'template' else 'program' end)
          and exists (
            select 1 from public.skandi_week_slots(v_uid, v_prog_e, v_widx_e) s
            where s.activity_template_id = p.activity_template_id and s.weekday = (p.day - v_monday)))
      );
    get diagnostics v_n = row_count;
    v_inserted := v_inserted + v_n;

    -- 2) Fuerza -- dueña la pista v_prog_s (o weekday si ninguna la gobierna). El guard es por
    -- template_id y no por disciplina: dos rutinas distintas el mismo día son válidas, volver a
    -- estampar la misma no.
    insert into public.skandi_planned_sessions
      (user_id, day, sort_order, discipline, source, template_id, title, program_id, program_week_index)
    select v_uid, v_monday + s.weekday, s.sort_order * 2, 'strength',
           case when v_prog_s is null then 'template' else 'program' end,
           t.id, t.name,
           v_prog_s, case when v_prog_s is null then null else v_widx_s end
    from public.skandi_week_slots(v_uid, v_prog_s, v_widx_s) s
    join public.skandi_templates t on t.id = s.template_id
    where s.template_id is not null
      and not exists (
        select 1 from public.skandi_planned_sessions p
        where p.user_id = v_uid and p.day = v_monday + s.weekday and p.template_id = t.id);
    get diagnostics v_n = row_count;
    v_inserted := v_inserted + v_n;

    -- 3) Resistencia -- dueña la pista v_prog_e. hiit/hyrox (104) siguen sumando a las cinco de
    -- siempre, 'other' de respaldo para un tipo futuro.
    insert into public.skandi_planned_sessions
      (user_id, day, sort_order, discipline, source, activity_template_id, title,
       target_duration_min, target_distance_km, target_zone, notes, program_id, program_week_index)
    select v_uid, v_monday + s.weekday,
           s.sort_order * 2 + case when s.template_id is null then 0 else 1 end,
           case a.activity_type
             when 'running'  then 'run'
             when 'cycling'  then 'bike'
             when 'swimming' then 'swim'
             when 'rowing'   then 'row'
             when 'walking'  then 'walk'
             when 'hiit'     then 'hiit'
             when 'hyrox'    then 'hyrox'
             else 'other'
           end,
           case when v_prog_e is null then 'template' else 'program' end,
           a.id, null,
           a.target_duration_min, a.target_distance_km, a.target_zone, a.notes,
           v_prog_e, case when v_prog_e is null then null else v_widx_e end
    from public.skandi_week_slots(v_uid, v_prog_e, v_widx_e) s
    join public.skandi_activity_templates a on a.id = s.activity_template_id
    where s.activity_template_id is not null
      and not exists (
        select 1 from public.skandi_planned_sessions p
        where p.user_id = v_uid and p.day = v_monday + s.weekday and p.activity_template_id = a.id);
    get diagnostics v_n = row_count;
    v_inserted := v_inserted + v_n;

  end if;

  -- Reconciliación de arrastre (fuerza). No depende de qué programa manda cada pista -- sin
  -- cambios frente a la 109.
  with cand as (
    select distinct on (s.id) p.id as pid, s.id as sid, s.completed_at
    from public.skandi_planned_sessions p
    join public.skandi_sessions s
      on s.user_id = v_uid
     and s.completed_at is not null
     and (s.completed_at at time zone 'America/Mazatlan')::date = p.day
    where p.user_id = v_uid
      and p.day between v_monday and v_monday + 6
      and p.discipline = 'strength'
      and p.status = 'planned'
      and p.session_id is null and p.activity_id is null
      and not exists (select 1 from public.skandi_planned_sessions q where q.session_id = s.id)
    order by s.id, p.sort_order, p.created_at
  )
  update public.skandi_planned_sessions p
  set status = 'done', completed_at = c.completed_at, session_id = c.sid
  from cand c
  where p.id = c.pid;
  get diagnostics v_n = row_count;
  v_inserted := v_inserted + v_n;

  -- Reconciliación de arrastre (resistencia). Mismas dos ramas de hiit/hyrox que en el
  -- estampado.
  with cand as (
    select distinct on (a.id) p.id as pid, a.id as aid, a.performed_at
    from public.skandi_planned_sessions p
    join public.skandi_external_activities a
      on a.user_id = v_uid
     and (a.performed_at at time zone 'America/Mazatlan')::date = p.day
     and p.discipline = case a.activity_type
           when 'running'  then 'run'
           when 'cycling'  then 'bike'
           when 'swimming' then 'swim'
           when 'rowing'   then 'row'
           when 'walking'  then 'walk'
           when 'hiit'     then 'hiit'
           when 'hyrox'    then 'hyrox'
           else 'other'
         end
    where p.user_id = v_uid
      and p.day between v_monday and v_monday + 6
      and p.status = 'planned'
      and p.session_id is null and p.activity_id is null
      and not exists (select 1 from public.skandi_planned_sessions q where q.activity_id = a.id)
    order by a.id, p.sort_order, p.created_at
  )
  update public.skandi_planned_sessions p
  set status = 'done', completed_at = c.performed_at, activity_id = c.aid
  from cand c
  where p.id = c.pid;
  get diagnostics v_n = row_count;
  v_inserted := v_inserted + v_n;

  return v_inserted;
end;
$$;

grant execute on function public.skandi_ensure_week(date) to authenticated;

commit;
