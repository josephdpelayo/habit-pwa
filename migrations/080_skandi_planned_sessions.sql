-- Skandi Fit: el calendario fechado.
--
-- Hasta hoy toda la planeación descansaba en una sola columna: skandi_templates.weekday y
-- skandi_activity_templates.weekday. Eso es correcto para la fuerza (el press del martes se
-- repite seis semanas y esa repetición es el método) y es estructuralmente incapaz de
-- representar resistencia periodizada, donde la semana 7 no se parece a la 1. Reescribir
-- "correr el miércoles" cada semana además borra lo que decía la semana pasada: no hay
-- historia del plan, ni taper, ni adherencia.
--
-- Esta migración agrega una capa ENCIMA, no un reemplazo: plantilla -> calendario -> sesión
-- registrada. Nada de skandi_templates / skandi_sessions / skandi_sets cambia, y ninguna
-- sesión histórica se migra.
--
-- La regla que resuelve el conflicto fuerza-vs-resistencia es is_edited:
--   * la plantilla se propaga a los días futuros que nadie tocó;
--   * en cuanto editas un día concreto, ese día queda congelado y la plantilla ya no lo pisa.
-- Un solo mecanismo para las dos modalidades, en vez de dos sistemas de agenda paralelos.
--
-- Ver docs/PLAN_ENTRENAMIENTO_SKANDI.md (fase T1).

create table if not exists public.skandi_planned_sessions (
  id                    uuid primary key default uuid_generate_v4(),
  user_id               uuid references public.profiles(id) on delete cascade not null,
  day                   date not null,
  -- Sin unique(user_id, day, sort_order) a propósito: dos sesiones el mismo día son normales
  -- (fuerza en la mañana, nado en la tarde) y un unique obligaría a resolver colisiones dentro
  -- del insert set-based del estampado. El orden se resuelve con (sort_order, created_at).
  sort_order            integer not null default 0,
  discipline            text not null check (discipline in
                          ('strength','run','bike','swim','row','walk','hiit','hyrox','mobility','rest','other')),

  -- De dónde salió esta fila. Decide qué puede volver a estampar el RPC y qué no.
  source                text not null default 'manual'
                          check (source in ('template','manual','program','season')),
  template_id           uuid references public.skandi_templates(id) on delete set null,
  activity_template_id  uuid references public.skandi_activity_templates(id) on delete set null,
  is_edited             boolean not null default false,

  -- La prescripción.
  title                 text,
  -- Pasos estructurados (calentamiento, series, enfriamiento). Se llena hasta la fase T2;
  -- la columna nace aquí para no pedir un ALTER a las tres semanas.
  structure             jsonb,
  target_duration_min   integer check (target_duration_min is null or target_duration_min between 1 and 600),
  target_distance_km    numeric(6,2) check (target_distance_km is null or target_distance_km between 0 and 500),
  target_zone           integer check (target_zone is null or target_zone between 1 and 5),
  target_load           integer check (target_load is null or target_load between 0 and 5000),
  is_brick              boolean not null default false,
  notes                 text,

  -- La conciliación con lo que de verdad pasó.
  status                text not null default 'planned'
                          check (status in ('planned','done','partial','skipped','moved')),
  session_id            uuid references public.skandi_sessions(id) on delete set null,
  activity_id           uuid references public.skandi_external_activities(id) on delete set null,
  completed_at          timestamptz,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index if not exists idx_skandi_planned_user_day
  on public.skandi_planned_sessions(user_id, day);
-- El estampado busca "¿ya existe una fila de esta plantilla ese día?" en cada corrida.
create index if not exists idx_skandi_planned_template
  on public.skandi_planned_sessions(user_id, template_id) where template_id is not null;
create index if not exists idx_skandi_planned_activity_template
  on public.skandi_planned_sessions(user_id, activity_template_id) where activity_template_id is not null;

alter table public.skandi_planned_sessions enable row level security;

drop policy if exists "Crew manage own skandi planned sessions" on public.skandi_planned_sessions;
create policy "Crew manage own skandi planned sessions"
  on public.skandi_planned_sessions for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- updated_at por trigger y no por la app: el estampado, la conciliación y la edición manual
-- escriben esta tabla por tres caminos distintos, y el que se le olvide es justo el que
-- ensucia la sincronización.
create or replace function public.skandi_planned_touch()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_skandi_planned_touch on public.skandi_planned_sessions;
create trigger trg_skandi_planned_touch
  before update on public.skandi_planned_sessions
  for each row execute function public.skandi_planned_touch();


-- ---------------------------------------------------------------------------------------
-- skandi_ensure_week: estampa una semana desde las plantillas.
--
-- Idempotente: correrlo dos veces sobre la misma semana no duplica nada. Se llama cuando la
-- app abre una semana, no por adelantado — materializar un año entero significaría que
-- cambiar una rutina tiene que reescribir 52 semanas de filas.
--
-- Hace dos cosas, en este orden:
--   1. BORRA los estampados que quedaron obsoletos y que nadie tocó (la rutina se movió de
--      día, se desasignó, o se borró). Esto es lo que hace que editar la plantilla se
--      propague hacia adelante.
--   2. INSERTA los que faltan.
-- Ninguna de las dos toca una fila con is_edited, con status != 'planned' o ya conciliada:
-- lo que editaste o hiciste es tuyo, y el estampado no vuelve a pasar por encima.
-- ---------------------------------------------------------------------------------------
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
  -- la adherencia de semanas que ya se cerraron.
  if v_monday < date_trunc('week', current_date)::date then
    return 0;
  end if;

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

  -- Reconciliación de arrastre. Estampar una semana que ya empezó deja filas 'planned' en
  -- días donde SÍ se entrenó: esas sesiones ya existían y nadie las ligó, porque la
  -- conciliación normal corre al terminar el entrenamiento. Sin este paso, encender el
  -- calendario un jueves muestra la semana en 0/4 habiendo entrenado tres días — y una
  -- métrica que arranca mintiendo no se vuelve a mirar.
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
