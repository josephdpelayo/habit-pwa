-- Rutinas básicas: las que todo socio tiene desde el primer día.
--
-- Hoy un socio recién registrado abre Entrenar → Mis rutinas y lee "Tu
-- entrenador aún no te asigna pizarrones". Esa es su primera impresión de la
-- app, y es una pantalla vacía que no puede resolver por su cuenta.
--
-- Esto YA se intentaba con asignaciones: la migración 057 creó
-- `assign_default_member_boards()`, que copia las rutinas azules a
-- `board_assignments` de cada socio, con un trigger al crear el perfil y una
-- llamada en cada login. Esta migración lo sustituye, por tres razones:
--
--   · es una fila por socio y por rutina — miles que mantener, y que hay que
--     volver a crear cada vez que se añade una rutina básica nueva (el trigger
--     solo corre al registrarse, así que a los socios de ayer no les llega);
--   · el coach no puede distinguir lo que le asignó él a un cliente de lo que
--     le puso el automatismo: en su panel todo se ve igual;
--   · si alguien desasigna una básica creyendo que limpia, el socio la pierde.
--
-- Una rutina básica no es de nadie en particular — es del gym, como las
-- plantillas de programa de la 114 — así que se marca UNA vez en la rutina y la
-- ven todos, sin filas intermedias.
--
-- La RLS no cambia: `boards` ya deja leer a cualquier autenticado todo lo que
-- tiene owner_id null (migración 070). Lo único que faltaba era que la app
-- supiera cuáles enseñar sin que nadie las asignara.

begin;

alter table public.boards
  add column if not exists is_starter boolean not null default false;

create index if not exists idx_boards_starter
  on public.boards(is_starter) where is_starter;

-- Una rutina personal de un socio no puede ser básica del gym.
do $$
begin
  alter table public.boards drop constraint if exists boards_starter_is_gym;
  alter table public.boards
    add constraint boards_starter_is_gym
    check (not is_starter or owner_id is null);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Siembra: las azules del gym que ya tienen ejercicios
-- ─────────────────────────────────────────────────────────────────────────────
-- El azul (#2563eb) es el color por defecto del editor, así que "azul" y
-- "básica" coinciden hoy pero no son lo mismo: en cuanto alguien cambie un
-- color esto dejaría de valer. Por eso el color solo se usa AQUÍ, para sembrar
-- una vez; a partir de ahora manda la columna, y el interruptor "Básica" de la
-- biblioteca del admin es lo que la mueve.
--
-- Se exigen ejercicios: una rutina vacía marcada como básica es una promesa
-- rota para el socio que la abre.
--
-- Antes de marcar nada, la lista se imprime en los mensajes del SQL Editor.
-- Revísala: si sobra o falta alguna, se corrige desde el admin sin tocar SQL.
do $$
declare
  r record;
  v_n integer := 0;
begin
  for r in
    select name, jsonb_array_length(coalesce(exercises, '[]'::jsonb)) as n
    from public.boards
    where owner_id is null
      and color = '#2563eb'
      and jsonb_array_length(coalesce(exercises, '[]'::jsonb)) > 0
    order by name
  loop
    raise notice 'BÁSICA → % (% ejercicios)', r.name, r.n;
    v_n := v_n + 1;
  end loop;

  if v_n = 0 then
    raise notice 'Ninguna rutina azul del gym con ejercicios: no se marcó ninguna. Márcalas desde Admin → Rutinas.';
  else
    raise notice 'Total: % rutinas marcadas como básicas.', v_n;
  end if;
end $$;

update public.boards
   set is_starter = true,
       updated_at = now()
 where owner_id is null
   and color = '#2563eb'
   and jsonb_array_length(coalesce(exercises, '[]'::jsonb)) > 0
   and not is_starter;

-- ─────────────────────────────────────────────────────────────────────────────
-- Retirar el mecanismo de la 057
-- ─────────────────────────────────────────────────────────────────────────────
-- Deja de crear asignaciones automáticas. Las que ya existen apuntando a una
-- rutina básica sobran —la rutina ya la ve todo el mundo— y quitarlas es lo que
-- devuelve a `board_assignments` su único significado: "esto se lo puso su
-- coach a esta persona". Las asignaciones a rutinas NO básicas no se tocan.
drop trigger if exists assign_default_member_boards_after_profile_insert on public.profiles;
drop function if exists public.assign_default_member_boards_on_profile_insert();

delete from public.board_assignments a
 using public.boards b
 where b.id = a.board_id
   and b.is_starter;

-- assign_default_member_boards() y default_member_board_ids() se quedan por si
-- algún cliente con HTML cacheado todavía las llama: devolver 0 filas es
-- inofensivo ahora que las básicas no dependen de asignaciones.

commit;
