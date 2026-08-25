-- Skandi Fit: resistencia estructurada (fase T2, docs/PLAN_ENTRENAMIENTO_SKANDI.md).
--
-- `skandi_planned_sessions.structure` (jsonb) ya existe desde la 080 — nació ahí a propósito
-- para no pedir un ALTER a las tres semanas, y hasta hoy nadie la llenaba. `skandi-plan.js` es
-- el módulo nuevo que la lee y la escribe; esta migración es lo que le faltaba a la base para
-- que ese módulo tenga con qué trabajar:
--
--   1. HIIT y Hyrox como tipo de actividad de verdad, no como 'other'. El calendario
--      (skandi_planned_sessions.discipline) ya sabía dibujarlos — DISC_GLYPH en skandi.html
--      tiene su símbolo desde la 080 — pero lo que de verdad se REGISTRA
--      (skandi_external_activities.activity_type) no los distinguía, así que terminar un día de
--      Hyrox planeado caía en 'other' y le mentía a la figura muscular
--      (Core 40/Shoulders 20/Quads 20/Chest 20 en vez del reparto real de piernas y espalda).
--   2. Captura propia de HIIT (rondas, trabajo/descanso) y de nado (largo de alberca, estilo):
--      hoy esos datos no tienen dónde vivir.
--   3. Umbrales de ritmo/potencia (ritmo umbral de correr, CSS de nado, FTP de bici) para que
--      "Z4" se pueda convertir a un número real. El pulso ya vive en skandi_settings desde la
--      087; esto le agrega los otros tres, en la misma tabla y no en una nueva —
--      skandi_athlete_zones nunca se creó como tabla aparte porque 087 ya había resuelto el
--      mismo problema para pulso ahí mismo, y separar el resto sería la misma info en dos sitios.
--
-- Lo que NO hace esta migración: no toca skandi_sessions/skandi_sets, no crea
-- skandi_workout_steps (el jsonb ya cubre eso, §4 del documento), y no importa Hyrox/HIIT desde
-- Strava — skandi-strava.js sigue mapeando por sport_type y eso es un cambio de módulo, no de
-- esquema.

-- ---------------------------------------------------------------------------------------------
-- 1. HIIT y Hyrox como activity_type real.
-- ---------------------------------------------------------------------------------------------

alter table public.skandi_external_activities
  drop constraint if exists skandi_external_activities_activity_type_check;
alter table public.skandi_external_activities
  add constraint skandi_external_activities_activity_type_check
  check (activity_type in ('running','cycling','swimming','rowing','walking','hiit','hyrox','other'));

alter table public.skandi_activity_templates
  drop constraint if exists skandi_activity_templates_activity_type_check;
alter table public.skandi_activity_templates
  add constraint skandi_activity_templates_activity_type_check
  check (activity_type in ('running','cycling','swimming','rowing','walking','hiit','hyrox','other'));

-- ---------------------------------------------------------------------------------------------
-- 2. Captura rica: HIIT/Hyrox (rondas, trabajo/descanso) y nado (alberca, estilo). Desnivel
--    sirve para correr/bici/caminar por igual, así que va sin condicionar el tipo.
-- ---------------------------------------------------------------------------------------------

alter table public.skandi_external_activities
  add column if not exists rounds integer check (rounds is null or rounds between 1 and 50),
  add column if not exists work_sec integer check (work_sec is null or work_sec between 1 and 3600),
  add column if not exists rest_sec integer check (rest_sec is null or rest_sec between 0 and 1800),
  add column if not exists elevation_m integer check (elevation_m is null or elevation_m between 0 and 20000),
  add column if not exists pool_length_m integer check (pool_length_m is null or pool_length_m in (25, 50)),
  add column if not exists stroke text check (stroke is null or stroke in ('free','back','breast','fly','mixed'));

comment on column public.skandi_external_activities.rounds is
  'HIIT/Hyrox: número de rondas del circuito.';
comment on column public.skandi_external_activities.work_sec is
  'HIIT: segundos de trabajo por intervalo. Hyrox no lo usa (las estaciones no son a tiempo fijo).';
comment on column public.skandi_external_activities.rest_sec is
  'HIIT: segundos de descanso por intervalo.';
comment on column public.skandi_external_activities.pool_length_m is
  'Nado en alberca: 25 o 50 m. Null = aguas abiertas o desconocido.';
comment on column public.skandi_external_activities.stroke is
  'Nado: estilo dominante de la sesión, cuando aplica.';

-- ---------------------------------------------------------------------------------------------
-- 3. Umbrales de ritmo/potencia, junto al pulso que ya guarda la 087.
-- ---------------------------------------------------------------------------------------------

alter table public.skandi_settings
  add column if not exists run_threshold_sec_km integer
    check (run_threshold_sec_km is null or run_threshold_sec_km between 120 and 900),
  add column if not exists swim_css_sec_100m integer
    check (swim_css_sec_100m is null or swim_css_sec_100m between 40 and 300),
  add column if not exists bike_ftp_w integer
    check (bike_ftp_w is null or bike_ftp_w between 40 and 500);

comment on column public.skandi_settings.run_threshold_sec_km is
  'Ritmo umbral de correr, seg/km (de una prueba de umbral o carrera reciente de referencia). Con esto skandi-plan.js convierte "Z4" a un ritmo real.';
comment on column public.skandi_settings.swim_css_sec_100m is
  'Critical Swim Speed, seg/100m.';
comment on column public.skandi_settings.bike_ftp_w is
  'Functional Threshold Power, watts. Solo si hay potenciómetro — sin él, se deja vacío y las zonas de bici se quedan en "Z4" a secas.';

-- ---------------------------------------------------------------------------------------------
-- 4. El estampado (skandi_ensure_week, 080) traducía activity_type -> discipline con un CASE
--    que no conocía hiit/hyrox y los caía a 'other'. Con el tipo ya real, se corrige la
--    traducción — mismo cuerpo de función, solo las dos ramas nuevas del CASE.
-- ---------------------------------------------------------------------------------------------

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

  v_monday := p_week_start - (extract(isodow from p_week_start)::int - 1);

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
      (p.template_id is not null and not exists (
         select 1 from public.skandi_templates t
         where t.id = p.template_id and t.user_id = v_uid
           and t.weekday = (p.day - v_monday)))
      or (p.activity_template_id is not null and not exists (
         select 1 from public.skandi_activity_templates a
         where a.id = p.activity_template_id and a.user_id = v_uid
           and a.weekday = (p.day - v_monday)))
      or (p.template_id is null and p.activity_template_id is null)
    );

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
           when 'hiit'     then 'hiit'
           when 'hyrox'    then 'hyrox'
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
