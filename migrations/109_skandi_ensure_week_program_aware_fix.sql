-- Skandi Fit: repara la regresión de skandi_ensure_week (el RPC que estampa el calendario).
--
-- La migración 102 hizo que skandi_ensure_week leyera el programa activo con start_date
-- (v_program/v_week_index, vía skandi_week_slots) y solo cayera a skandi_templates.weekday sin
-- programa. La 103 conservó ese cuerpo tal cual y solo agregó la tabla de fases y el trigger de
-- program_id/program_week_index en skandi_planned_sessions.
--
-- La 104 (resistencia estructurada, hiit/hyrox) volvió a redefinir skandi_ensure_week (mismo
-- create-or-replace de siempre) para agregarle dos ramas nuevas al CASE de activity_type -> discipline,
-- pero su propio comentario dice que partió de "el mismo cuerpo de función" de la migración 080
-- -- una copia de ANTES de la 102/103, no la vigente. El resultado borró sin querer toda la
-- resolución por programa (v_program, v_start, v_weeks, v_week_index, las llamadas a
-- skandi_week_slots, el estampado con source='program', el update que voltea el source cuando
-- una rutina se queda en el mismo día al cambiar de weekday a programa) y además reintrodujo el
-- bug que la 096 ya había corregido una vez: la guarda del pasado volvió a envolver la función
-- entera en vez de solo el estampado, así que la reconciliación de arrastre tampoco corría para
-- semanas ya cerradas.
--
-- Desde entonces (hasta la 108) skandi_ensure_week nunca lee skandi_programs/
-- skandi_program_days/skandi_program_weeks: cualquier programa con start_date se ve bien en la
-- hoja de "Programa" (esa parte es puramente cliente, lee state.programDays) pero no estampa
-- nada en el calendario real -- cae en silencio al camino de weekday plano.
--
-- Esta migración recupera el cuerpo de la 102 (programa-aware, con el fix de la 096 ya
-- incorporado) y le re-aplica encima las dos ramas de la 104 (hiit/hyrox) en los dos lugares
-- donde aparece el CASE de traducción. No toca skandi_week_slots (102) ni el trigger de
-- periodización (103): siguen intactos, solo estaban huérfanos porque nada los llamaba.

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
  v_program    uuid;
  v_start      date;
  v_weeks      integer;
  v_deload     boolean;
  v_cycle_len  integer;
  v_week_index integer := 0;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Ancla al lunes real de esa semana (isodow: lunes = 1), pase lo que pase el cliente.
  v_monday := p_week_start - (extract(isodow from p_week_start)::int - 1);

  -- ¿Manda un programa esta semana? Solo si está activo, tiene fecha de arranque, y esa fecha
  -- ya pasó: un programa que arranca el mes que viene no gobierna la semana de hoy.
  select p.id, p.start_date, p.weeks, p.deload_week
    into v_program, v_start, v_weeks, v_deload
  from public.skandi_programs p
  where p.user_id = v_uid and p.is_active and p.start_date is not null
  limit 1;

  if v_program is not null then
    v_start := v_start - (extract(isodow from v_start)::int - 1);
    if v_monday < v_start then
      v_program := null;
    else
      v_cycle_len := greatest(1, coalesce(v_weeks, 4) + case when coalesce(v_deload, true) then 1 else 0 end);
      v_week_index := ((v_monday - v_start) / 7) + 1;
      if v_week_index > v_cycle_len then
        v_week_index := -1;
      end if;
    end if;
  end if;

  -- El pasado no se materializa. Esto NO corta la función entera (fix de la 096): solo salta
  -- el estampado. La reconciliación de arrastre, más abajo, corre para cualquier semana.
  if v_monday >= date_trunc('week', current_date)::date then

    delete from public.skandi_planned_sessions p
    where p.user_id = v_uid
      and p.day between v_monday and v_monday + 6
      and p.source in ('template','program')
      and p.is_edited = false
      and p.status = 'planned'
      and p.completed_at is null
      and p.session_id is null
      and p.activity_id is null
      and (
        (p.template_id is not null and not exists (
           select 1 from public.skandi_week_slots(v_uid, v_program, v_week_index) s
           where s.template_id = p.template_id and s.weekday = (p.day - v_monday)))
        or (p.activity_template_id is not null and not exists (
           select 1 from public.skandi_week_slots(v_uid, v_program, v_week_index) s
           where s.activity_template_id = p.activity_template_id and s.weekday = (p.day - v_monday)))
        or (p.template_id is null and p.activity_template_id is null)
      );
    get diagnostics v_n = row_count;
    v_inserted := v_inserted + v_n;

    update public.skandi_planned_sessions p
    set source = case when v_program is null then 'template' else 'program' end
    where p.user_id = v_uid
      and p.day between v_monday and v_monday + 6
      and p.source in ('template','program')
      and p.source is distinct from case when v_program is null then 'template' else 'program' end
      and p.is_edited = false and p.status = 'planned'
      and p.completed_at is null and p.session_id is null and p.activity_id is null
      and (
        (p.template_id is not null and exists (
          select 1 from public.skandi_week_slots(v_uid, v_program, v_week_index) s
          where s.template_id = p.template_id and s.weekday = (p.day - v_monday)))
        or (p.activity_template_id is not null and exists (
          select 1 from public.skandi_week_slots(v_uid, v_program, v_week_index) s
          where s.activity_template_id = p.activity_template_id and s.weekday = (p.day - v_monday)))
      );
    get diagnostics v_n = row_count;
    v_inserted := v_inserted + v_n;

    insert into public.skandi_planned_sessions
      (user_id, day, sort_order, discipline, source, template_id, title)
    select v_uid, v_monday + s.weekday, s.sort_order * 2, 'strength',
           case when v_program is null then 'template' else 'program' end,
           t.id, t.name
    from public.skandi_week_slots(v_uid, v_program, v_week_index) s
    join public.skandi_templates t on t.id = s.template_id
    where s.template_id is not null
      and not exists (
        select 1 from public.skandi_planned_sessions p
        where p.user_id = v_uid and p.day = v_monday + s.weekday and p.template_id = t.id);
    get diagnostics v_n = row_count;
    v_inserted := v_inserted + v_n;

    -- Resistencia. Los tipos de actividad se traducen a disciplinas del calendario; hiit/hyrox
    -- (104) suman a las cinco de siempre, 'other' sigue de respaldo para un tipo futuro.
    insert into public.skandi_planned_sessions
      (user_id, day, sort_order, discipline, source, activity_template_id, title,
       target_duration_min, target_distance_km, target_zone, notes)
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
           case when v_program is null then 'template' else 'program' end,
           a.id, null,
           a.target_duration_min, a.target_distance_km, a.target_zone, a.notes
    from public.skandi_week_slots(v_uid, v_program, v_week_index) s
    join public.skandi_activity_templates a on a.id = s.activity_template_id
    where s.activity_template_id is not null
      and not exists (
        select 1 from public.skandi_planned_sessions p
        where p.user_id = v_uid and p.day = v_monday + s.weekday and p.activity_template_id = a.id);
    get diagnostics v_n = row_count;
    v_inserted := v_inserted + v_n;

  end if;

  -- Reconciliación de arrastre (fuerza). Corre siempre, incluso si la semana ya cerró.
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

  -- Reconciliación de arrastre (resistencia). Mismas dos ramas nuevas que en el estampado.
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
