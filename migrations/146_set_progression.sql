-- 146 · La progresión es la carga (docs/PROGRAMA_HANDSTAND.md §10)
--
-- En una skill de calistenia no se sube de peso: se sube de progresión. Un aguante de front
-- lever no se mide en kilos, se mide en qué variante lo aguantaste — tuck, tuck avanzado, una
-- pierna, straddle, half lay, completo. Y no es una por entreno: Joseph entrena el aguante en
-- straddle, las negativas subiendo en advanced y bajando en half straddle, y los touch y las
-- dominadas en L y en tuck, el mismo día. Así que la variante va **por serie**, exactamente
-- donde `weight` ya vive.
--
--   1. coaching_session_sets.rung_id: en qué escalón se hizo ESA serie. Es el gemelo de
--      `weight` para lo que no se carga con peso. Nulo en todo lo que no es skill, que es casi
--      todo.
--   2. boards.exercises[] puede traer `skillGroup` (el slug de coach_skills) en lugar de
--      `catalogId`: el ejercicio de la rutina es «Aguante de front lever», la línea entera, y
--      la progresión se elige al entrenar. Eso es jsonb y no pide columna; aquí solo queda
--      escrito, porque es la mitad del modelo.
--
-- El `on delete set null` es a propósito: una serie es historia y no se borra porque alguien
-- limpie el catálogo. `merge_exercise_catalog` (123/124) no borra la fila que fusiona, la
-- desactiva, así que un merge no deja rung_id colgando y no hay que repuntarlo ahí.
--
-- Lo que esto mejora de paso: hasta hoy la marca de la escalera se deducía del `ex_key` del
-- ejercicio (loadSkillMarksSb cruzaba las rutinas de la persona para saber qué escalón era
-- cada llave), o sea una sola progresión por ejercicio y adivinada. Con rung_id la marca sale
-- de la serie misma, exacta, y sirve igual para un ejercicio agregado en vivo.
--
-- Requiere: 029 (coaching_session_sets), 037 (exercise_catalog), 141 (las escaleras).

begin;

alter table public.coaching_session_sets
  add column if not exists rung_id uuid references public.exercise_catalog(id) on delete set null;

comment on column public.coaching_session_sets.rung_id is
  'En qué escalón de la escalera se hizo esta serie. En una skill la progresión es la carga: '
  'el gemelo de weight. Nulo en lo que no es skill.';

-- «La vez pasada» de una variante y la marca de la escalera leen por persona y escalón, de lo
-- más nuevo a lo más viejo.
create index if not exists idx_coaching_session_sets_rung
  on public.coaching_session_sets(user_id, rung_id, updated_at desc)
  where rung_id is not null;

do $$
declare n_col int; n_idx int;
begin
  select count(*) into n_col from information_schema.columns
   where table_schema = 'public' and table_name = 'coaching_session_sets' and column_name = 'rung_id';
  select count(*) into n_idx from pg_indexes
   where schemaname = 'public' and indexname = 'idx_coaching_session_sets_rung';
  if n_col <> 1 or n_idx <> 1 then
    raise exception 'La 146 no quedó: % columna, % índice', n_col, n_idx;
  end if;
  raise notice 'La progresión por serie está lista (coaching_session_sets.rung_id).';
end $$;

commit;
