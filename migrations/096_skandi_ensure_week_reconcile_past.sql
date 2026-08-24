-- Skandi Fit: la reconciliación de arrastre (migración 080) también corre en una semana que
-- ya cerró, no solo en la actual/futura.
--
-- El bug: skandi_ensure_week() salía con `return 0` de golpe para cualquier semana anterior a
-- la de hoy ("el pasado no se materializa"), y esa salida temprana se llevaba de encuentro DOS
-- pasos muy distintos que compartían la misma guarda por accidente:
--   1. Estampar filas nuevas desde las plantillas — esto SÍ debe frenar en el pasado, es el
--      caso que el comentario original describe (no inventar un plan hacia atrás).
--   2. Conciliar filas 'planned' que YA EXISTÍAN con lo que de verdad se entrenó (sesiones de
--      skandi_sessions, actividades de skandi_external_activities) — esto NO debería frenar
--      nunca: es solo marcar como hecho algo que ya estaba planeado, con datos que llegaron
--      tarde (Strava/Intervals sincronizados uno o dos días después, típicamente al cerrar la
--      semana). Bloquearlo es lo que dejaba "Bici Relax" en 'planned' para siempre en cuanto
--      la semana pasaba al pasado, mientras el ciclismo real de Intervals entraba aparte como
--      actividad "sin planear": dos filas para un mismo entreno en vez de una conciliada.
--
-- El arreglo: la guarda del pasado ahora envuelve solo el estampado (borrar lo obsoleto +
-- insertar fuerza + insertar resistencia). Los dos pasos de conciliación corren siempre. Es
-- seguro para semanas viejas porque cada uno ya filtra por `p.day between v_monday y
-- v_monday+6` y por `p.status='planned' and p.session_id/activity_id is null`: solo toca lo
-- que ya estaba planeado y sigue sin ligar, nunca inventa una fila nueva.

create or replace function public.skandi_ensure_week(p_week_start date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_monday   date;
  v_inserted integer := 0;
  v_n        integer := 0;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Ancla al lunes real de esa semana (isodow: lunes = 1), pase lo que pase el cliente.
  v_monday := p_week_start - (extract(isodow from p_week_start)::int - 1);

  -- El pasado no se materializa: un plan inventado hacia atrás no es historia, y ensuciaría
  -- la adherencia de semanas que ya se cerraron. Esto ya NO corta la función entera: solo
  -- salta el estampado. La reconciliación de abajo corre para cualquier semana.
  if v_monday >= date_trunc('week', current_date)::date then

    delete from public.skandi_planned_sessions p
    where p.user_id = v_uid
      and p.day between v_monday and v_monday + 6
      and p.source = 'template'
      and p.is_edited = false
      and p.status = 'planned'
      and p.completed_at is null
      and p.session_id is null
      and p.activity_id is null
      and (
        -- la rutina de fuerza ya no vive en ese día de la semana (o ya no existe)
        (p.template_id is not null and not exists (
           select 1 from public.skandi_templates t
           where t.id = p.template_id and t.user_id = v_uid
             and t.weekday = (p.day - v_monday)))
        -- el plan de cardio ya no vive en ese día de la semana (o ya no existe)
        or (p.activity_template_id is not null and not exists (
           select 1 from public.skandi_activity_templates a
           where a.id = p.activity_template_id and a.user_id = v_uid
             and a.weekday = (p.day - v_monday)))
        -- la plantilla que la originó se borró: el on delete set null dejó la fila huérfana
        or (p.template_id is null and p.activity_template_id is null)
      );

    -- Fuerza. El guard es por template_id y no por disciplina: dos rutinas distintas el mismo
    -- día son válidas, volver a estampar la misma no.
    insert into public.skandi_planned_sessions
      (user_id, day, sort_order, discipline, source, template_id, title)
    select v_uid, v_monday + t.weekday, 0, 'strength', 'template', t.id, t.name
    from public.skandi_templates t
    where t.user_id = v_uid
      and t.weekday is not null
      and not exists (
        select 1 from public.skandi_planned_sessions p
        where p.user_id = v_uid and p.day = v_monday + t.weekday and p.template_id = t.id);
    get diagnostics v_n = row_count;
    v_inserted := v_inserted + v_n;

    -- Resistencia. Los tipos de actividad se traducen a disciplinas del calendario; 'other'
    -- existe en el check justamente para que un tipo nuevo no reviente el estampado.
    insert into public.skandi_planned_sessions
      (user_id, day, sort_order, discipline, source, activity_template_id, title,
       target_duration_min, target_distance_km, target_zone, notes)
    select v_uid, v_monday + a.weekday, 1,
           case a.activity_type
             when 'running'  then 'run'
             when 'cycling'  then 'bike'
             when 'swimming' then 'swim'
             when 'rowing'   then 'row'
             when 'walking'  then 'walk'
             else 'other'
           end,
           'template', a.id, null,
           a.target_duration_min, a.target_distance_km, a.target_zone, a.notes
    from public.skandi_activity_templates a
    where a.user_id = v_uid
      and a.weekday is not null
      and not exists (
        select 1 from public.skandi_planned_sessions p
        where p.user_id = v_uid and p.day = v_monday + a.weekday and p.activity_template_id = a.id);
    get diagnostics v_n = row_count;
    v_inserted := v_inserted + v_n;

  end if;

  -- Reconciliación de arrastre. Estampar una semana que ya empezó deja filas 'planned' en
  -- días donde SÍ se entrenó: esas sesiones ya existían y nadie las ligó, porque la
  -- conciliación normal corre al terminar el entrenamiento. Sin este paso, encender el
  -- calendario un jueves muestra la semana en 0/4 habiendo entrenado tres días — y una
  -- métrica que arranca mintiendo no se vuelve a mirar. Corre SIEMPRE, incluso si la semana
  -- ya cerró: un reloj sincronizado el lunes con la actividad del domingo pasado es el caso
  -- normal, no la excepción.
  --
  -- El día se resuelve en America/Mazatlan y no en UTC: completed_at es timestamptz, y en
  -- UTC-7 todo lo entrenado después de las 5 pm caería al día siguiente.
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
      -- una sesión que ya está ligada a otro día/fila no se vuelve a usar
      and not exists (select 1 from public.skandi_planned_sessions q where q.session_id = s.id)
    order by s.id, p.sort_order, p.created_at
  )
  update public.skandi_planned_sessions p
  set status = 'done', completed_at = c.completed_at, session_id = c.sid
  from cand c
  where p.id = c.pid;
  get diagnostics v_n = row_count;
  v_inserted := v_inserted + v_n;

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

  -- Devuelve filas tocadas (insertadas + conciliadas): es lo que el cliente usa para decidir
  -- si tiene que volver a leer la semana.
  return v_inserted;
end;
$$;

grant execute on function public.skandi_ensure_week(date) to authenticated;
