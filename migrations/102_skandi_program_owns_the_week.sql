-- Skandi Fit: el programa se vuelve el dueño del plan.
--
-- Hasta hoy la fuente de la verdad de "qué toca el martes" era skandi_templates.weekday -- una
-- columna que vive en la RUTINA. skandi_programs (069) guardaba una FOTO de esa columna, y
-- "cargar" un programa no aplicaba nada: recorría todas las rutinas del miembro reescribiendo
-- su weekday hasta que la foto volvía a ser cierta.
--
-- De esa inversión salían todos los síntomas (ver docs/CAPAS_ENTRENAR_SKANDI.md §2): el
-- programa no podía decir cuánto dura, no podía tener una semana distinta de otra, una rutina
-- no podía estar en dos programas a la vez, y editar el plan obligaba a editar el mundo.
--
-- Esta migración invierte la propiedad. NO borra weekday: se queda como "día sugerido" de una
-- rutina suelta y como el camino completo para quien no tenga programa activo. Se retirará en
-- una migración posterior, cuando nada la lea -- nunca en la misma que cambia quién la lee.

begin;

-- ---------------------------------------------------------------------------------------
-- 1. El programa aprende a durar.
-- ---------------------------------------------------------------------------------------
-- start_date es lo que convierte un programa en un ciclo con fecha: sin él el programa sigue
-- siendo una foto y toda la app cae al camino de weekday, que es exactamente el comportamiento
-- de antes. Por eso es nullable y sin default -- es el interruptor.
alter table public.skandi_programs
  add column if not exists weeks       integer not null default 4 check (weeks between 1 and 16),
  add column if not exists deload_week boolean not null default true,
  add column if not exists start_date  date;

-- ---------------------------------------------------------------------------------------
-- 2. Los días del programa aprenden a variar por semana.
-- ---------------------------------------------------------------------------------------
-- week_index = 0 significa "se repite todas las semanas". Un programa normal siguen siendo 7
-- filas con 0; uno ondulante agrega filas con week_index = N solo donde la semana N se aparta.
--
-- La regla de resolución es de una línea, y es de reemplazo, no de mezcla: si existe CUALQUIER
-- fila (week_index = N, weekday = W), esas filas son el día completo; si no, mandan las de 0.
-- Mezclar por ranura daría un martes hecho de dos semanas distintas, que no es lo que nadie
-- quiere decir al escribir "en la semana 3 el martes es otra cosa".
--
-- sort_order existe para dos sesiones el mismo día (fuerza en la mañana, nado en la tarde).
-- Hoy la interfaz siempre escribe 0 y mete fuerza y resistencia en la misma fila; la columna
-- nace aquí para no pedir un ALTER -- y un cambio del índice único -- a las tres semanas.
alter table public.skandi_program_days
  add column if not exists week_index integer not null default 0 check (week_index between 0 and 17),
  add column if not exists sort_order integer not null default 0;

-- El unique(program_id, weekday) inline de la 069 es justo lo que topaba el programa a una sola
-- semana. Se busca por nombre real en vez de asumirlo: la 069 lo creó sin nombrarlo.
do $$
declare v_name text;
begin
  select con.conname into v_name
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public' and rel.relname = 'skandi_program_days'
    and con.contype = 'u'
    and (select array_agg(att.attname::text order by att.attname)
         from unnest(con.conkey) k
         join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k)
        = array['program_id','weekday'];
  if v_name is not null then
    execute format('alter table public.skandi_program_days drop constraint %I', v_name);
  end if;
end $$;

create unique index if not exists idx_skandi_program_days_slot
  on public.skandi_program_days(program_id, week_index, weekday, sort_order);

-- ---------------------------------------------------------------------------------------
-- 3. Backfill: el ciclo que ya estaba corriendo no se pierde.
-- ---------------------------------------------------------------------------------------
-- La 100 enlazó skandi_training_blocks.program_id: el bloque vigente ya sabe de qué programa
-- salió y cuántas semanas dura. Se copia al programa para que el miembro que ya tiene un
-- programa cargado siga en la misma semana del ciclo después de correr esto, sin tocar nada.
--
-- Solo programas ACTIVOS: uno guardado y nunca cargado no tiene ciclo, y darle uno inventado
-- lo haría empezar a estampar el calendario sin que nadie se lo pidiera.
update public.skandi_programs p
set weeks       = b.build_weeks,
    deload_week = true,
    start_date  = b.start_date
from (
  select distinct on (program_id) program_id, start_date, build_weeks
  from public.skandi_training_blocks
  where program_id is not null
  order by program_id, start_date desc
) b
where b.program_id = p.id
  and p.is_active
  and p.start_date is null;

-- ---------------------------------------------------------------------------------------
-- 4. skandi_week_slots: la semana efectiva, en un solo lugar.
-- ---------------------------------------------------------------------------------------
-- Contesta "¿qué toca cada día de ESTA semana?" y es el único lugar donde vive la regla de
-- resolución. La usan el borrado de obsoletos y los dos inserts del estampado; tenerla como
-- función y no como tres CTE copiadas es lo que impide que un día se contradigan entre sí.
--
-- Con p_program null devuelve la semana de weekday, sin programa de por medio: el estampado es
-- una sola consulta en los dos modos, no dos ramas que hay que mantener en paralelo.
create or replace function public.skandi_week_slots(p_uid uuid, p_program uuid, p_week_index integer)
returns table(weekday integer, sort_order integer, template_id uuid, activity_template_id uuid)
language sql
stable
-- security INVOKER a propósito, al revés que skandi_ensure_week: llamada desde el RPC (que sí
-- es definer) corre igual con los permisos del definer, y llamada directo por un cliente cae
-- bajo RLS. Definer aquí dejaría que cualquier autenticado pasara el uid de otro y leyera qué
-- rutina tiene cada quién en cada día.
set search_path = public
as $$
  select d.weekday, d.sort_order, d.template_id, d.activity_template_id
  from public.skandi_program_days d
  where p_program is not null
    and p_week_index >= 0
    and d.program_id = p_program
    and (
      d.week_index = p_week_index
      or (d.week_index = 0 and not exists (
            select 1 from public.skandi_program_days o
            where o.program_id = p_program
              and o.week_index = p_week_index
              and o.weekday = d.weekday))
    )
  union all
  select t.weekday, 0, t.id, null
  from public.skandi_templates t
  where p_program is null and t.user_id = p_uid and t.weekday is not null
  union all
  select a.weekday, 1, null, a.id
  from public.skandi_activity_templates a
  where p_program is null and a.user_id = p_uid and a.weekday is not null;
$$;

grant execute on function public.skandi_week_slots(uuid, uuid, integer) to authenticated;

-- ---------------------------------------------------------------------------------------
-- 5. skandi_ensure_week estampa desde el programa activo.
-- ---------------------------------------------------------------------------------------
-- Igual que la 096 en todo lo demás (la guarda del pasado envuelve solo el estampado; las dos
-- reconciliaciones corren siempre). Lo único que cambia es DE DÓNDE sale la semana: del
-- programa activo con start_date, si lo hay, y de weekday si no.
--
-- Esto es lo que hace que "inyectar el programa al calendario" deje de ser una acción aparte:
-- el programa activo ES lo que el calendario estampa, semana por semana al abrirla. No se
-- materializan las N semanas de golpe -- un cambio en una rutina tendría que reescribir el
-- ciclo entero (ver docs/PLAN_ENTRENAMIENTO_SKANDI.md §10).
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
      -- Un ciclo NO se repite solo por calendario: esa decisión ya la tomó la 066 ("the app
      -- never auto-repeats a block by calendar alone") y sigue siendo la correcta -- terminar
      -- un bloque es el momento de reevaluar, no de volver a empezar en automático. Pasada la
      -- última semana el índice se vuelve -1; skandi_week_slots no devuelve filas para un
      -- índice negativo, así que el ciclo se detiene de verdad. Se pide 1..v_cycle_len y nunca
      -- 0, porque 0 es "todas las semanas" y pedirlo como semana concreta anularía su respaldo.
      if v_week_index > v_cycle_len then
        v_week_index := -1;
      end if;
    end if;
  end if;

  -- El pasado no se materializa: un plan inventado hacia atrás no es historia, y ensuciaría
  -- la adherencia de semanas que ya se cerraron. Esto NO corta la función entera: solo salta
  -- el estampado. La reconciliación de abajo corre para cualquier semana.
  if v_monday >= date_trunc('week', current_date)::date then

    -- 1) Fuera lo estampado que quedó obsoleto y que nadie tocó (la rutina se movió de día, se
    -- desasignó, se borró, o el programa cambió). Esto es lo que hace que editar el plan se
    -- propague hacia adelante. 'program' entra junto a 'template' porque desde esta migración
    -- el estampado se firma con el origen real; lo cargado a mano para una sola semana
    -- (applyProgramToWeek) queda a salvo por is_edited, como siempre.
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
        -- la plantilla que la originó se borró: el on delete set null dejó la fila huérfana
        or (p.template_id is null and p.activity_template_id is null)
      );
    get diagnostics v_n = row_count;
    v_inserted := v_inserted + v_n;

    -- Si la misma rutina quedó en el mismo día al pasar de weekday a programa (o al revés),
    -- no se borra ni se reinserta. Aun así su origen debe decir quién manda ahora.
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

    -- 2) Fuerza. El guard es por template_id y no por disciplina: dos rutinas distintas el
    -- mismo día son válidas, volver a estampar la misma no.
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

    -- 3) Resistencia. Los tipos de actividad se traducen a disciplinas del calendario; 'other'
    -- existe en el check justamente para que un tipo nuevo no reviente el estampado.
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

  -- Reconciliación de arrastre (fuerza). Estampar una semana que ya empezó deja filas
  -- 'planned' en días donde SÍ se entrenó: esas sesiones ya existían y nadie las ligó, porque
  -- la conciliación normal corre al terminar el entrenamiento. Sin este paso, encender el
  -- calendario un jueves muestra la semana en 0/4 habiendo entrenado tres días -- y una
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
      and not exists (select 1 from public.skandi_planned_sessions q where q.session_id = s.id)
    order by s.id, p.sort_order, p.created_at
  )
  update public.skandi_planned_sessions p
  set status = 'done', completed_at = c.completed_at, session_id = c.sid
  from cand c
  where p.id = c.pid;
  get diagnostics v_n = row_count;
  v_inserted := v_inserted + v_n;

  -- Reconciliación de arrastre (resistencia).
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

  -- Devuelve filas tocadas (borradas + insertadas + conciliadas): es lo que el cliente usa
  -- para decidir si tiene que volver a leer la semana.
  return v_inserted;
end;
$$;

grant execute on function public.skandi_ensure_week(date) to authenticated;

commit;
