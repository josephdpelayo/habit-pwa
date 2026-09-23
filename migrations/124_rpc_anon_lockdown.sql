-- Cerrar a `anon` dos funciones que confiaban en "sin sesión = SQL Editor".
--
-- merge_exercise_catalog (123) y assign_default_member_boards (057) saltaban
-- la comprobación de admin cuando auth.uid() venía vacío, pensando en el SQL
-- Editor y el service role. Pero una llamada con la llave pública de la app
-- (la anon key, que va dentro de app.html) también llega sin auth.uid(), y
-- Supabase le da EXECUTE a `anon` sobre toda función nueva de `public` por
-- sus privilegios por defecto: el `revoke ... from public` de la 123 no lo
-- quita. Comprobado contra producción: la anon key pasaba el filtro y solo
-- la frenaba que los ids no existieran. Con ella se podía fusionar (y así
-- desactivar) cualquier ejercicio del catálogo. La de la 057 tiene el mismo
-- patrón (asignar rutinas a cualquier socio), pero en producción no existe;
-- se cierra solo donde esté.
--
-- Dos capas: se le quita EXECUTE a anon, y la 123 deja de fiarse de un
-- auth.uid() vacío — ahora distingue por el rol del JWT. Sin JWT (SQL
-- Editor) o con service_role pasa; con cualquier otro hace falta ser admin.

begin;

revoke execute on function public.merge_exercise_catalog(uuid, uuid) from anon, public;

-- La de la 057 no existe en todas las bases (en producción no está): solo
-- se le quita el permiso si está. Un revoke sobre una función que no existe
-- es un error que tumba toda la migración.
do $$
begin
  if to_regprocedure('public.assign_default_member_boards(uuid)') is not null then
    execute 'revoke execute on function public.assign_default_member_boards(uuid) from anon, public';
  end if;
end $$;

-- Igual que la 123, salvo la primera comprobación.
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
  -- auth.role() es el rol del JWT: vacío en el SQL Editor, 'service_role'
  -- desde el servidor, 'anon' o 'authenticated' desde la app.
  if coalesce(auth.role(), '') not in ('', 'service_role') and not exists (
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

-- create or replace conserva los permisos, pero se repiten para que el
-- estado final se lea aquí sin tener que ir a la 123.
revoke execute on function public.merge_exercise_catalog(uuid, uuid) from anon, public;
grant execute on function public.merge_exercise_catalog(uuid, uuid) to authenticated, service_role;

commit;
