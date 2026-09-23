-- Rutinas básicas asignadas: todo socio nuevo de HABIT arranca con ellas
-- palomeadas, y los que hoy no tienen ni una rutina las reciben ya.
--
-- La 116 dejó de asignarlas: una rutina básica (`boards.is_starter`) la ve
-- cualquier socio sin necesidad de una fila en `board_assignments`. Al socio le
-- funcionaba, pero no a quien lo atiende: en Admin → Editar socio → «Pizarrones
-- asignados» las básicas salían sin palomear, y un cliente con esa lista vacía
-- se lee como un cliente sin rutinas. Esta migración las vuelve a asignar.
--
-- Qué es una básica: la columna `is_starter`, no el color. Aquí se marcan de una
-- vez todas las azules del gym con ejercicios, porque así las distingue el gym
-- hoy. Pero el azul es también el color por defecto del editor: si el color
-- decidiera, una rutina hecha para un solo cliente a la que nadie le cambió el
-- color les llegaría a todos los socios nuevos. De aquí en adelante manda el
-- interruptor «Rutina básica» de Admin → Rutinas.
--
-- Para el socio no cambia nada: la app agrupa en «Rutinas básicas» todo lo que
-- tenga is_starter, esté asignado o no.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Las azules del gym con ejercicios son básicas
-- ─────────────────────────────────────────────────────────────────────────────
-- La 116 ya marcó las que eran azules entonces; esto alcanza a las que se
-- hicieron azules después. `to_jsonb(b)->>'archived_at'` deja fuera las
-- archivadas sin depender de que la 117 (que crea esa columna) esté corrida.
update public.boards b
   set is_starter = true,
       updated_at = now()
 where b.owner_id is null
   and lower(coalesce(b.color, '')) = '#2563eb'
   and jsonb_array_length(coalesce(b.exercises, '[]'::jsonb)) > 0
   and (to_jsonb(b) ->> 'archived_at') is null
   and not b.is_starter;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Cuáles se asignan: las básicas
-- ─────────────────────────────────────────────────────────────────────────────
-- La versión de la 057 tomaba cualquier rutina azul, incluidas las vacías.
-- La usan también `assign_default_member_boards()` y el alta de socios desde el
-- admin (api/search-users.js), así que redefinirla aquí los alinea a todos.
create or replace function public.default_member_board_ids()
returns table(board_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select b.id
  from public.boards b
  where b.is_starter
    and b.owner_id is null
    and (to_jsonb(b) ->> 'archived_at') is null
  order by b.created_at asc;
$$;

grant execute on function public.default_member_board_ids() to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Al registrarse: trigger sobre profiles
-- ─────────────────────────────────────────────────────────────────────────────
-- Inserta directo en vez de llamar a assign_default_member_boards(), que exige
-- ser el propio socio o un admin: una comprobación de permisos que falle aquí
-- tumbaría el alta del perfil. Por lo mismo, cualquier error se degrada a un
-- WARNING — quedarse sin rutinas se arregla desde el admin; quedarse sin perfil
-- deja al socio sin poder entrar.
create or replace function public.assign_default_member_boards_on_profile_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role = 'user' and coalesce(new.source, 'habit') = 'habit' then
    begin
      insert into public.board_assignments (board_id, user_id)
      select d.board_id, new.id
      from public.default_member_board_ids() d
      on conflict do nothing;
    exception when others then
      raise warning 'No se asignaron las rutinas básicas a %: %', new.id, sqlerrm;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists assign_default_member_boards_after_profile_insert on public.profiles;
create trigger assign_default_member_boards_after_profile_insert
after insert on public.profiles
for each row
execute function public.assign_default_member_boards_on_profile_insert();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Los socios que hoy no tienen ni una rutina
-- ─────────────────────────────────────────────────────────────────────────────
-- "Ni una rutina" = ninguna asignada y ninguna hecha por él. Los que ya tienen
-- algo no se tocan: su lista es la que su coach (o ellos) armaron.
-- Solo socios de HABIT: la tripulación de Skandi comparte `profiles`.
do $$
declare
  r record;
  v_boards integer := 0;
  v_members integer := 0;
  v_rows integer := 0;
begin
  for r in
    select b.name, jsonb_array_length(coalesce(b.exercises, '[]'::jsonb)) as n
    from public.default_member_board_ids() d
    join public.boards b on b.id = d.board_id
    order by b.name
  loop
    raise notice 'BÁSICA → % (% ejercicios)', r.name, r.n;
    v_boards := v_boards + 1;
  end loop;

  if v_boards = 0 then
    raise notice 'No hay rutinas básicas: no se asignó nada. Márcalas en Admin → Rutinas → «Rutina básica».';
    return;
  end if;

  with ins as (
    insert into public.board_assignments (board_id, user_id)
    select d.board_id, p.id
    from public.profiles p
    cross join public.default_member_board_ids() d
    where p.role = 'user'
      and coalesce(p.source, 'habit') = 'habit'
      and not exists (select 1 from public.board_assignments a where a.user_id = p.id)
      and not exists (select 1 from public.boards o where o.owner_id = p.id)
    on conflict do nothing
    returning user_id
  )
  select count(*), count(distinct user_id) into v_rows, v_members from ins;

  raise notice 'Total: % básicas → % socios sin rutina (% asignaciones).', v_boards, v_members, v_rows;
end $$;

commit;
