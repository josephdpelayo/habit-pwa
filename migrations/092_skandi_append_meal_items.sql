-- Skandi Fit: agregar renglones con una foto MÁS a una comida ya registrada.
--
-- skandi_save_meal_items() siempre borra y vuelve a insertar: es correcto para el primer
-- análisis (una comida = una foto), pero rompe el caso real en un barco — nadie fotografía
-- el plato completo de un jalón, se va agregando conforme se va comiendo o se acuerda. Repetir
-- "Foto" desde el detalle de una comida ya registrada debe SUMAR renglones, no reemplazar los
-- que ya se corrigieron a mano.
--
-- Es la misma idea que ya tenía skandi_add_food_to_meal (código de barras / catálogo agregan
-- sin borrar); esto le da el mismo camino a un renglón que viene de una foto analizada por IA.

create or replace function public.skandi_append_meal_items(
  p_meal_id uuid,
  p_items   jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid;
  base  integer;
begin
  select user_id into owner from public.skandi_meals where id = p_meal_id;
  if owner is null then
    raise exception 'meal % not found', p_meal_id;
  end if;
  if owner <> auth.uid() and auth.uid() is not null then
    raise exception 'not your meal';
  end if;

  select coalesce(max(sort_order), 0) into base
  from public.skandi_meal_items where meal_id = p_meal_id;

  insert into public.skandi_meal_items
    (meal_id, user_id, food_id, label, grams, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g,
     added_sugar_g, source, ai_confidence, sort_order, included, is_cooking_fat)
  select
    p_meal_id,
    owner,
    nullif(item->>'food_id','')::uuid,
    item->>'label',
    nullif(item->>'grams','')::numeric,
    coalesce(nullif(item->>'kcal','')::numeric, 0),
    coalesce(nullif(item->>'protein_g','')::numeric, 0),
    coalesce(nullif(item->>'carbs_g','')::numeric, 0),
    coalesce(nullif(item->>'fat_g','')::numeric, 0),
    coalesce(nullif(item->>'fiber_g','')::numeric, 0),
    coalesce(nullif(item->>'sugar_g','')::numeric, 0),
    least(
      coalesce(nullif(item->>'added_sugar_g','')::numeric, 0),
      coalesce(nullif(item->>'sugar_g','')::numeric, 0)
    ),
    coalesce(nullif(item->>'source',''), 'ai'),
    nullif(item->>'ai_confidence','')::numeric,
    base + ordinality::integer,
    coalesce((item->>'included')::boolean, true),
    coalesce((item->>'is_cooking_fat')::boolean, false)
  from jsonb_array_elements(p_items) with ordinality as t(item, ordinality);

  -- Agregar una foto más nunca deja a la comida en "failed" o "pending": si esto corrió, ya
  -- hay renglones válidos. No se toca ai_confidence — mezclar la confianza de dos fotos
  -- distintas no significa nada.
  update public.skandi_meals
  set analysis_status = 'ready',
      analysis_error  = null
  where id = p_meal_id;
end;
$$;
