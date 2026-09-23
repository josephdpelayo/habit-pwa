-- Fusionar ejercicios repetidos del catálogo.
--
-- El mismo ejercicio acaba en exercise_catalog con dos nombres: la importación
-- de Skandi (071) trajo "Lagartija pike" junto al "Pike push up" de HABIT, y
-- cada vez que el coach escribía un ejercicio a su manera ("Extension de tricep
-- con cuerda" frente a "Extensión tríceps cuerda") la app creaba otra fila. El
-- resultado: dos entradas en el buscador, dos en la ficha del músculo, y el
-- video de YouTube pegado en una que la otra no encuentra.
--
-- La app ya compara nombres por su identidad (sin acentos, sin "de/con", en
-- singular: exerciseSignature() en app.html), así que deja de crear duplicados
-- y agrupa los que ya existen en Admin → Rutinas → "Ejercicios repetidos". Esta
-- función es la que fusiona un par cuando el admin elige con cuál se queda.
--
-- No borra nada: la fila que se va queda con is_active = false, su nombre y su
-- slug pasan a ser alias de la que queda (el buscador los sigue encontrando), y
-- las rutinas y sesiones que la usaban pasan a apuntar a la que queda.

begin;

-- Mismo criterio que videoKindRank() en app.html: el video que grabó el gym
-- (YouTube, Drive: cualquier cosa que no sea un archivo) gana a un MP4, y un
-- MP4 a un GIF o imagen. Se mira la extensión sin query ni hash, como mediaKind().
create or replace function public.exercise_video_rank(p_url text)
returns integer
language sql
immutable
as $$
  select case
    when p_url is null or btrim(p_url) = '' then -1
    when split_part(split_part(lower(p_url), '?', 1), '#', 1) ~ '\.(gif|png|jpe?g|webp|avif)$' then 0
    when split_part(split_part(lower(p_url), '?', 1), '#', 1) ~ '\.(mp4|webm|mov|m4v)$' then 1
    else 2
  end;
$$;

create or replace function public.merge_exercise_catalog(p_keep uuid, p_drop uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  k public.exercise_catalog%rowtype;
  d public.exercise_catalog%rowtype;
  v_boards integer := 0;
  v_sessions integer := 0;
begin
  -- Sin sesión es el SQL Editor o el service role; con sesión, solo un admin.
  if auth.uid() is not null and not exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'Solo un admin puede fusionar ejercicios';
  end if;
  if p_keep is null or p_drop is null or p_keep = p_drop then
    raise exception 'Hay que elegir dos ejercicios distintos';
  end if;

  select * into k from public.exercise_catalog where id = p_keep for update;
  if not found then raise exception 'No existe el ejercicio que se queda (%)', p_keep; end if;
  select * into d from public.exercise_catalog where id = p_drop for update;
  if not found then raise exception 'No existe el ejercicio que se fusiona (%)', p_drop; end if;

  -- Lo que queda se enriquece con lo que traía el otro, sin pisar lo propio:
  -- el mejor video, y reparto / instrucciones / músculos solo si le faltaban.
  update public.exercise_catalog c set
    aliases = (
      select coalesce(array_agg(distinct a order by a), '{}')
      from unnest(coalesce(k.aliases, '{}') || coalesce(d.aliases, '{}') || array[lower(d.name), d.slug]) a
      where a is not null and btrim(a) <> '' and a <> lower(k.name) and a <> k.slug
    ),
    video_url = case
      when public.exercise_video_rank(d.video_url) > public.exercise_video_rank(k.video_url) then d.video_url
      else k.video_url end,
    muscle_split = case
      when coalesce(k.muscle_split, '{}'::jsonb) = '{}'::jsonb then coalesce(d.muscle_split, '{}'::jsonb)
      else k.muscle_split end,
    instructions = coalesce(nullif(btrim(k.instructions), ''), d.instructions),
    primary_muscle = coalesce(nullif(btrim(k.primary_muscle), ''), d.primary_muscle),
    secondary_muscles = case when cardinality(k.secondary_muscles) = 0 then d.secondary_muscles else k.secondary_muscles end,
    equipment = case when cardinality(k.equipment) = 0 then d.equipment else k.equipment end,
    is_active = true,
    updated_at = now()
  where c.id = k.id;

  update public.exercise_catalog
     set is_active = false, updated_at = now()
   where id = d.id;

  -- Rutinas (de todos: del gym y las que se arma cada socio). Se cambia a qué
  -- ficha apunta el ejercicio, no su nombre: el nombre es lo que el coach
  -- escribió para esa rutina. El historial de series no se toca — va por el
  -- id de cada ejercicio de la rutina, no por el catálogo.
  update public.boards b
     set exercises = (
       select jsonb_agg(
                case when x.e->>'catalogId' = d.id::text or x.e->>'exerciseKey' = d.slug
                     then x.e || jsonb_build_object('catalogId', k.id::text, 'exerciseKey', k.slug)
                     else x.e end
                order by x.ord)
       from jsonb_array_elements(b.exercises) with ordinality as x(e, ord))
   where jsonb_typeof(b.exercises) = 'array'
     and exists (select 1 from jsonb_array_elements(b.exercises) e
                  where e->>'catalogId' = d.id::text or e->>'exerciseKey' = d.slug);
  get diagnostics v_boards = row_count;

  -- Los ejercicios cambiados o añadidos a mitad de un entreno (070).
  update public.coaching_schedule s
     set session_exercises = (
       select jsonb_agg(
                case when x.e->>'catalogId' = d.id::text or x.e->>'exerciseKey' = d.slug
                     then x.e || jsonb_build_object('catalogId', k.id::text, 'exerciseKey', k.slug)
                     else x.e end
                order by x.ord)
       from jsonb_array_elements(s.session_exercises) with ordinality as x(e, ord))
   where jsonb_typeof(s.session_exercises) = 'array'
     and exists (select 1 from jsonb_array_elements(s.session_exercises) e
                  where e->>'catalogId' = d.id::text or e->>'exerciseKey' = d.slug);
  get diagnostics v_sessions = row_count;

  return jsonb_build_object('kept', k.name, 'merged', d.name, 'boards', v_boards, 'sessions', v_sessions);
end;
$$;

revoke all on function public.merge_exercise_catalog(uuid, uuid) from public;
grant execute on function public.merge_exercise_catalog(uuid, uuid) to authenticated, service_role;

commit;
