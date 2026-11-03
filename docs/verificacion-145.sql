-- Verificación de la 145, para correr DESPUÉS en el SQL Editor. No escribe nada.
-- Si la 145 terminó bien, su propio bloque final ya levantó el aviso
-- «Programa «Parada de manos en 8 semanas»: 12 rutinas, 48 días, 8 semanas.»
-- Esto es para verlo con los ojos y revisar lo que ese bloque no cuenta.

-- 1. Lo que la app necesita para pintar la tarjeta: la plantilla con su llave.
select id, name, name_en, user_id, weeks, template_key, is_active
from public.coaching_programs
where template_key = 'handstand-8';

-- 2. Las 12 rutinas del gym. Las tres de cada fase, con cuántos ejercicios trae cada una.
--    is_starter tiene que ser false en las 12: no deben salir en la lista de nadie.
select b.name, b.name_en, b.is_starter, b.duration_min,
       jsonb_array_length(b.exercises) as ejercicios
from public.boards b
where 'programa-handstand' = any(b.tags) and b.owner_id is null
order by b.name;

-- 3. Los 48 días: 6 por semana (lunes a sábado), ninguno sin rutina.
select week_index, count(*) as dias, count(board_id) as con_rutina,
       string_agg(dow::text, ',' order by dow) as dows
from public.coaching_program_days
where program_id = md5('habit-handstand:program')::uuid
group by week_index
order by week_index;

-- 4. Las 8 semanas y su fase. Las pares son las de prueba.
select week_index, phase, note, note_en
from public.coaching_program_weeks
where program_id = md5('habit-handstand:program')::uuid
order by week_index;

-- 5. Los 10 ejercicios nuevos, con su figura y su inglés.
select name, slug, animation_url is not null as figura,
       instructions_en is not null as en
from public.exercise_catalog
where slug in ('preparacion-de-munecas','apertura-de-hombros-en-pared','encogimientos-en-pica',
               'patadas-de-conejo','salida-en-rueda','caminata-en-pared',
               'encogimientos-de-frente-a-la-pared','patada-a-la-pared',
               'toques-de-hombro-en-pared','patada-al-equilibrio')
order by name;

-- 6. Anon ya no puede reescribirle la semana a nadie: las tres tienen que salir en false.
select p.oid::regprocedure as funcion,
       has_function_privilege('anon', p.oid, 'execute') as anon_puede
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('apply_coaching_program','ensure_coaching_week_from_template','coaching_week_slots')
order by 1;
