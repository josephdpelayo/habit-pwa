-- 156 — La pantalla del gym: la rutina del día (docs/PANTALLA_GYM.md).
--
-- Joseph, 27 nov 2026: «mientras nadie se conecte a la pantalla de los clientes, hay que
-- transmitir la rutina del día. Tomemos una de las básicas y presentémosla con ejemplos de gif,
-- todos los ejercicios visibles en una sola pantalla». Como las teles de clase de un gym de
-- circuito: cada ejercicio en su cuadro, con su número, su demostración en movimiento y lo que
-- se hace (series × repeticiones).
--
-- Cuál rutina: la que el admin fije en el control (gym_screens.daily_board_id) o, si no fijó
-- ninguna, una de las básicas (boards.is_starter) que rota un día a la vez, en orden de nombre.
-- La rotación cuenta días desde una fecha fija, así todas las teles y todos los días dan lo
-- mismo sin guardar nada.
--
-- La tele la pide con gym_screen_daily(screen, key) —misma llave que gym_screen_state, misma
-- razón—, aparte del estado de la gente: cambia una vez al día y no lleva datos de nadie.
-- Por ejercicio manda las candidatas a demostración y la tele elige (HabitScreen.pickMedia):
--   · la animación del catálogo (animation_url, los SVG de skill-anim) o un GIF/MP4 del
--     catálogo del propio ejercicio;
--   · un GIF del catálogo con el mismo nombre o alias (los 47 que vinieron de Skandi): las
--     básicas apuntan a filas del gym que solo traen YouTube, y el GIF vive en otra fila;
--   · los videos del gym (YouTube Shorts / Drive) del ejercicio y de su fila del catálogo.
-- Nada de notas del coach.

begin;

alter table public.gym_screens
  add column if not exists daily_board_id uuid references public.boards(id) on delete set null;

-- Un nombre sin acentos, minúsculas, sin signos y con espacios simples: para emparejar
-- «ELEVACIÓN DE TALÓN» con un alias «elevacion de talon».
create or replace function public.gym_screen_norm(p text)
returns text
language sql
immutable
set search_path = public
as $$
  select btrim(regexp_replace(
    translate(lower(coalesce(p, '')), 'áéíóúüñàèìòù-_', 'aeiouunaeiou  '),
    '[^a-z0-9]+', ' ', 'g'));
$$;

-- La rutina que toca hoy en esa pantalla (null si no hay básicas).
create or replace function public.gym_screen_daily_board(p_screen text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  with fixed as (
    select s.daily_board_id as id
    from public.gym_screens s
    join public.boards b on b.id = s.daily_board_id
    where s.id = p_screen and b.archived_at is null
  ), starters as (
    select b.id, row_number() over (order by b.name, b.id) - 1 as n, count(*) over () as total
    from public.boards b
    where b.is_starter and b.owner_id is null and b.archived_at is null
      and jsonb_typeof(b.exercises) = 'array' and jsonb_array_length(b.exercises) > 0
  )
  select coalesce(
    (select id from fixed),
    (select id from starters
     where n = (((now() at time zone 'America/Mazatlan')::date - date '2026-01-05') % greatest(total, 1)))
  );
$$;

create or replace function public.gym_screen_daily(p_screen text, p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_screen public.gym_screens%rowtype;
  v_board  public.boards%rowtype;
  v_id     uuid;
  v_ex     jsonb;
begin
  select * into v_screen from public.gym_screens where id = p_screen;
  if not found or p_key is null or v_screen.access_key <> p_key then
    return jsonb_build_object('ok', false, 'error', 'KEY');
  end if;
  v_id := public.gym_screen_daily_board(p_screen);
  if v_id is null then return jsonb_build_object('ok', true, 'board', null); end if;
  select * into v_board from public.boards where id = v_id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'name', e->>'name',
      'sets', e->'sets', 'reps', e->'reps', 'repsType', e->'repsType', 'rest', e->'rest',
      'media', (
        select coalesce(jsonb_agg(u order by rk), '[]'::jsonb) from (
          -- 1) la animación o el GIF del propio ejercicio en el catálogo
          select c.animation_url as u, 1 as rk from public.exercise_catalog c
            where c.id::text = (e->>'catalogId') and c.animation_url is not null
          union all
          select c.video_url, 2 from public.exercise_catalog c
            where c.id::text = (e->>'catalogId') and c.video_url ~* '\.(gif|mp4|webm|webp)(\?|$)'
          union all
          -- 2) un GIF de otra fila del catálogo con el mismo nombre o alias
          select g.video_url, 3 from (
            select c2.video_url from public.exercise_catalog c2
            where c2.is_active and c2.video_url ~* '\.(gif|mp4|webm|webp)(\?|$)'
              and (public.gym_screen_norm(c2.name) = public.gym_screen_norm(e->>'name')
                or exists (select 1 from unnest(coalesce(c2.aliases, '{}')) a
                           where public.gym_screen_norm(a) = public.gym_screen_norm(e->>'name')))
            order by c2.name limit 1) g
          union all
          -- 3) los videos del gym: los del ejercicio en la rutina y el de su fila del catálogo
          select v->>'url', 4 from jsonb_array_elements(
              case when jsonb_typeof(e->'videos') = 'array' then e->'videos' else '[]'::jsonb end) v
            where coalesce(v->>'url', '') <> ''
          union all
          select x, 5 from unnest(array[e->>'videoUrl', e->>'video_url', e->>'video', e->>'driveUrl']) x
            where coalesce(x, '') <> ''
          union all
          select c.video_url, 6 from public.exercise_catalog c
            where c.id::text = (e->>'catalogId') and coalesce(c.video_url, '') <> ''
        ) m
      )
    ) order by t.o), '[]'::jsonb)
  into v_ex
  from jsonb_array_elements(case when jsonb_typeof(v_board.exercises) = 'array' then v_board.exercises else '[]'::jsonb end)
       with ordinality as t(e, o)
  where jsonb_typeof(t.e) = 'object' and coalesce(t.e->>'name', '') <> '';

  return jsonb_build_object('ok', true, 'fixed', v_screen.daily_board_id is not null,
    'board', jsonb_build_object('id', v_board.id, 'title', v_board.name, 'color', v_board.color,
      'exercises', v_ex));
end;
$$;

-- El control: fijar una rutina (o volver a la rotación con null) y ver las básicas para elegir.
create or replace function public.gym_screen_set_daily(p_screen text, p_board uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_habit_admin() then
    raise exception 'NOT_ADMIN';
  end if;
  if p_board is not null and not exists (
      select 1 from public.boards b where b.id = p_board and b.owner_id is null and b.archived_at is null) then
    raise exception 'NO_BOARD';
  end if;
  update public.gym_screens set daily_board_id = p_board, updated_at = now() where id = p_screen;
  if not found then raise exception 'NO_SCREEN'; end if;
  -- La tele pide la rutina cada 10 min; así la cambia al momento (se recarga).
  update public.gym_screen_pings set reload_nonce = reload_nonce + 1, bumped_at = now()
  where screen_id = p_screen;
  return public.gym_screen_daily_options(p_screen);
end;
$$;

create or replace function public.gym_screen_daily_options(p_screen text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_habit_admin() then
    raise exception 'NOT_ADMIN';
  end if;
  return jsonb_build_object(
    'fixed', (select daily_board_id from public.gym_screens where id = p_screen),
    'today', public.gym_screen_daily_board(p_screen),
    'starters', (select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name,
        'n', jsonb_array_length(b.exercises)) order by b.name, b.id), '[]'::jsonb)
      from public.boards b
      where b.is_starter and b.owner_id is null and b.archived_at is null
        and jsonb_typeof(b.exercises) = 'array' and jsonb_array_length(b.exercises) > 0));
end;
$$;

revoke all on function public.gym_screen_norm(text) from public, anon, authenticated;
revoke all on function public.gym_screen_daily_board(text) from public, anon, authenticated;
revoke all on function public.gym_screen_daily(text, text) from public, anon, authenticated;
revoke all on function public.gym_screen_set_daily(text, uuid) from public, anon, authenticated;
revoke all on function public.gym_screen_daily_options(text) from public, anon, authenticated;

grant execute on function public.gym_screen_daily(text, text) to anon, authenticated;
grant execute on function public.gym_screen_set_daily(text, uuid) to authenticated;
grant execute on function public.gym_screen_daily_options(text) to authenticated;

commit;
