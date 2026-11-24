-- 154 — Sacar a `anon` de verdad: el permiso que se quedaba era el de PUBLIC.
--
-- Revisión de solo lectura de producción, 24 nov 2026. Tres cosas abiertas:
--
-- 1. `profile_cards` (117) se podía ESCRIBIR. La vista es security definer (corre como su
--    dueño, postgres, que se salta la RLS), es actualizable (un select simple sobre profiles)
--    y los privilegios por defecto de Supabase les dieron a `anon` y `authenticated` TODO
--    (`arwdDxtm`), no solo el `select` que la 117 concedió. Probado con rollback: con la llave
--    pública y sin sesión, `update profile_cards set name = …` tocó una fila de `profiles`.
--    Lo mismo servía para cambiar el nombre o el avatar de cualquiera, o borrar perfiles con
--    un `delete`, y cualquier socio con sesión podía igual. Además `anon` leía las 208 filas.
--
-- 2. La 145 sí corrió, pero no cerró el hueco que decía cerrar. Quitó a `anon` el EXECUTE
--    sobre apply_coaching_program / ensure_coaching_week_from_template / coaching_week_slots, y
--    `anon` lo seguía teniendo por PUBLIC (`=X/postgres` en el acl): toda función nace con
--    EXECUTE para PUBLIC, y `anon` es parte de PUBLIC. Esos candados son
--    `auth.uid() <> p_user_id`, que con uid null da null y no dispara el `raise`. Igual
--    start_training_session / finish_training_session / set_training_session_paused /
--    reorganize_coaching_day (`v_row.user_id <> auth.uid()`): sin sesión se empezaba, pausaba o
--    cerraba el entreno de otro con su id.
--
-- 3. El mismo error en sentido contrario en otras migraciones: `revoke all … from public` +
--    `grant … to service_role` (074, 147, 148) o `to authenticated` (073, 075, 076). El revoke
--    de PUBLIC no quita la concesión EXPLÍCITA a `anon` y `authenticated` que Supabase pone a
--    toda función nueva (pg_default_acl de public), así que la intención nunca se cumplió:
--      - skandi_save_meal_items y sus hermanas aceptan uid null a propósito (para api/skandi.js,
--        que usa service-role): `if owner <> auth.uid() and auth.uid() is not null`. Con la
--        llave anon se escribían las comidas de cualquiera.
--      - skandi_bump_ai_usage / skandi_refund_ai_usage no revisan quién llama: un socio podía
--        devolverse su cuota de IA sin límite, o gastar la de otro.
--      - hold_david_pilot / finish_david_pilot (solo servidor) no revisan quién llama:
--        finish_david_pilot confirma una reserva pagada con el id del apartado.
--
-- Qué hace: a cada función le quita PUBLIC, `anon` y (en las de solo servidor)
-- `authenticated`, y le vuelve a dar EXECUTE explícito a quien sí la usa. `profile_cards` queda
-- en solo `select` para `authenticated`.
--
-- Qué NO toca, a propósito:
--   - `security_invoker` en profile_cards: no. Desde la 117 profiles solo deja leer la fila
--     propia (y staff todo); con invoker la comunidad, los favoritos y los reportes se quedan
--     sin nombres ni avatares. La vista existe para enseñar esas cuatro columnas de todos sin
--     abrir profiles; lo que estaba mal eran los privilegios, no el modo.
--   - is_habit_admin() / is_habit_staff(): políticas `to public` de profiles, training_profiles,
--     community_reports… las llaman. Sin EXECUTE, un select de `anon` sobre esas tablas pasaría
--     de vacío a error. Solo devuelven si quien llama es admin/staff: nada que filtrar.
--   - Funciones de trigger y rls_auto_enable (event trigger): no se pueden llamar por RPC, y
--     un trigger no revisa EXECUTE al dispararse. Quitarlo sería cosmético.
--   - El esquema `virtus` (otra app en la misma base): fuera de HABIT.
--   - competencia.html: solo lee lift_competitions y lift_competition_standings sin sesión, que
--     no son funciones. Su `select` para `anon` se queda; solo se le quitan escrituras a la
--     vista, que de todos modos no es actualizable.
--
-- Cada función, solo donde exista (to_regprocedure, como la 124 y la 145): un revoke sobre una
-- firma que no existe tumba la migración entera.

begin;

do $$
declare
  f text;
  -- Las llama la app con sesión. `authenticated` y `service_role` se quedan.
  member_rpc text[] := array[
    'public.apply_coaching_program(uuid, uuid, date, date, date)',
    'public.apply_coaching_program(uuid, uuid, date, date)',
    'public.ensure_coaching_week_from_template(uuid, date)',
    'public.coaching_week_slots(uuid, uuid, integer)',
    'public.save_coaching_week(uuid, date, text, jsonb, integer)',
    'public.start_training_session(uuid, jsonb)',
    'public.finish_training_session(uuid)',
    'public.set_training_session_paused(uuid, boolean)',
    'public.reorganize_coaching_day(uuid, date)',
    'public.training_score_history(uuid, integer)',
    'public.default_member_board_ids()',
    'public.david_pilot_slots()',
    'public.reserve_david_pilot(date, integer)',
    'public.save_template_items(uuid, jsonb)',
    'public.ensure_own_profile(text)',
    'public.skandi_ensure_week(date)',
    'public.skandi_strava_status()',
    'public.skandi_update_exercise_media(uuid, text, text)',
    'public.skandi_save_meal_items(uuid, jsonb, text, numeric)',
    'public.skandi_append_meal_items(uuid, jsonb)',
    'public.skandi_save_meal_as_dish(uuid, text)',
    'public.skandi_create_meal_from_dish(uuid, text, numeric, timestamptz, text)',
    'public.skandi_add_food_to_meal(uuid, uuid, numeric)',
    'public.skandi_bump_food_usage(uuid[])'
  ];
  -- Solo las llama el servidor con service-role (api/skandi.js, create- y
  -- confirm-checkout-session.js). Era la intención de la 074 y la 148.
  server_rpc text[] := array[
    'public.skandi_bump_ai_usage(uuid, integer)',
    'public.skandi_refund_ai_usage(uuid)',
    'public.hold_david_pilot(uuid, date, integer, integer)',
    'public.finish_david_pilot(uuid, uuid, text, integer)'
  ];
begin
  foreach f in array member_rpc loop
    if to_regprocedure(f) is not null then
      execute 'revoke execute on function ' || f || ' from public, anon';
      execute 'grant execute on function ' || f || ' to authenticated, service_role';
    else
      raise notice 'No existe %, no hay permiso que quitar', f;
    end if;
  end loop;

  foreach f in array server_rpc loop
    if to_regprocedure(f) is not null then
      execute 'revoke execute on function ' || f || ' from public, anon, authenticated';
      execute 'grant execute on function ' || f || ' to service_role';
    else
      raise notice 'No existe %, no hay permiso que quitar', f;
    end if;
  end loop;
end $$;

-- profile_cards: solo lectura, solo con sesión. Sigue con los permisos de su dueño (ver arriba).
revoke all on public.profile_cards from public, anon, authenticated;
grant select on public.profile_cards to authenticated;

-- Las otras dos vistas con escrituras concedidas. No son actualizables y son security_invoker,
-- así que hoy no pasa nada; se quitan para que una vista que lo llegue a ser no herede el hueco.
-- lift_competition_standings conserva su select para anon: es lo que lee la TV de /competencia.
revoke insert, update, delete, truncate, references, trigger
  on public.lift_competition_standings, public.skandi_quick_picks from public, anon, authenticated;

-- Comprobación: si algo quedó abierto, se revierte todo en lugar de dejarlo a medias.
do $$
declare
  f text;
  leaks text := '';
begin
  foreach f in array array[
    'public.apply_coaching_program(uuid, uuid, date, date, date)',
    'public.ensure_coaching_week_from_template(uuid, date)',
    'public.coaching_week_slots(uuid, uuid, integer)',
    'public.save_coaching_week(uuid, date, text, jsonb, integer)',
    'public.start_training_session(uuid, jsonb)',
    'public.finish_training_session(uuid)',
    'public.set_training_session_paused(uuid, boolean)',
    'public.reorganize_coaching_day(uuid, date)',
    'public.skandi_save_meal_items(uuid, jsonb, text, numeric)',
    'public.skandi_bump_ai_usage(uuid, integer)',
    'public.skandi_refund_ai_usage(uuid)',
    'public.hold_david_pilot(uuid, date, integer, integer)',
    'public.finish_david_pilot(uuid, uuid, text, integer)'
  ] loop
    if to_regprocedure(f) is not null and has_function_privilege('anon', f, 'EXECUTE') then
      leaks := leaks || ' anon→' || f;
    end if;
  end loop;

  foreach f in array array[
    'public.skandi_bump_ai_usage(uuid, integer)',
    'public.skandi_refund_ai_usage(uuid)',
    'public.hold_david_pilot(uuid, date, integer, integer)',
    'public.finish_david_pilot(uuid, uuid, text, integer)'
  ] loop
    if to_regprocedure(f) is not null and has_function_privilege('authenticated', f, 'EXECUTE') then
      leaks := leaks || ' authenticated→' || f;
    end if;
  end loop;

  if to_regprocedure('public.start_training_session(uuid, jsonb)') is not null
     and not has_function_privilege('authenticated', 'public.start_training_session(uuid, jsonb)', 'EXECUTE') then
    leaks := leaks || ' authenticated perdió start_training_session';
  end if;

  if has_table_privilege('anon', 'public.profile_cards', 'SELECT')
     or has_table_privilege('anon', 'public.profile_cards', 'UPDATE')
     or has_table_privilege('authenticated', 'public.profile_cards', 'UPDATE')
     or has_table_privilege('authenticated', 'public.profile_cards', 'DELETE')
     or has_table_privilege('authenticated', 'public.profile_cards', 'INSERT') then
    leaks := leaks || ' profile_cards sigue con escritura o lectura anónima';
  end if;
  if not has_table_privilege('authenticated', 'public.profile_cards', 'SELECT') then
    leaks := leaks || ' authenticated perdió el select de profile_cards';
  end if;
  if not has_table_privilege('anon', 'public.lift_competition_standings', 'SELECT') then
    leaks := leaks || ' la TV de /competencia perdió su lectura';
  end if;

  if leaks <> '' then
    raise exception '154 no quedó cerrada:%', leaks;
  end if;
end $$;

commit;
