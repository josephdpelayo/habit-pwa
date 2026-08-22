-- Skandi Fit: la comida no siempre entra por una foto, y el aceite no siempre existe.
--
-- Tres cambios sobre la 073, todos nacidos de cómo se registra la comida en la vida real:
--
-- 1. LA GRASA DE COCCIÓN ES UN RENGLÓN APARTE, PALOMEABLE. Estimarla siempre y sumarla
--    dentro del guisado hacía imposible desmarcarla: en casa Joseph cocina sin aceite y en
--    restaurante no lo controla. Ahora el modelo la devuelve como su propio renglón
--    (is_cooking_fat) y el usuario la palomea o la quita. Quitarla NO la borra: `included`
--    la deja fuera de la suma pero la conserva, así se puede volver a palomear.
-- 2. `included` en vez de borrar. Un diario donde "quitar" destruye el dato no deja
--    corregirse, y el aceite es exactamente el renglón que se prende y apaga.
-- 3. Cuatro maneras de registrar: foto, texto ("dos huevos con frijoles"), código de barras
--    y captura manual. `input_kind` las distingue para poder medir después cuál usas y cuál
--    acierta más.

-- ── 1. Renglones: incluido / grasa de cocción ───────────────────────────────

alter table public.skandi_meal_items
  add column if not exists included        boolean not null default true,
  add column if not exists is_cooking_fat  boolean not null default false;

comment on column public.skandi_meal_items.included is
  'false = el usuario lo desmarcó; se conserva pero no suma en los totales de la comida';
comment on column public.skandi_meal_items.is_cooking_fat is
  'aceite/mantequilla de cocción estimado por la IA: se pinta como palomita, no como alimento';

-- ── 2. Los totales suman solo lo palomeado ──────────────────────────────────

create or replace function public.skandi_recalc_meal_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid := coalesce(new.meal_id, old.meal_id);
begin
  update public.skandi_meals m
  set kcal      = coalesce(t.kcal, 0),
      protein_g = coalesce(t.protein_g, 0),
      carbs_g   = coalesce(t.carbs_g, 0),
      fat_g     = coalesce(t.fat_g, 0),
      fiber_g   = coalesce(t.fiber_g, 0)
  from (
    select sum(kcal) kcal, sum(protein_g) protein_g, sum(carbs_g) carbs_g,
           sum(fat_g) fat_g, sum(fiber_g) fiber_g
    from public.skandi_meal_items
    where meal_id = target and included   -- <- el único cambio contra la 073
  ) t
  where m.id = target;
  return null;
end;
$$;

-- ── 3. Comidas: de dónde vino y dónde se comió ──────────────────────────────
-- `venue` no es decoración: es lo que decide si la grasa de cocción llega palomeada o no.
-- En casa, desmarcada; fuera, marcada. `note` sigue siendo el texto del usuario y ahora
-- también es la ENTRADA cuando no hay foto ("dos huevos con frijoles y una tortilla").

alter table public.skandi_meals
  add column if not exists venue      text check (venue is null or venue in ('casa','restaurante','fonda','otro')),
  add column if not exists input_kind text not null default 'photo'
                            check (input_kind in ('photo','text','barcode','manual'));

comment on column public.skandi_meals.note is
  'contexto que escribió el usuario; cuando no hay foto, es la descripción que se analiza';

-- ── 4. Código de barras: un producto, una fila ──────────────────────────────
-- Sin esto, escanear el mismo producto dos veces creaba dos alimentos. El índice permite
-- que convivan el global (user_id null, sembrado de Open Food Facts) y el personal.

create unique index if not exists idx_skandi_foods_user_barcode
  on public.skandi_foods(coalesce(user_id, '00000000-0000-0000-0000-000000000000'::uuid), barcode)
  where barcode is not null;

-- ── 5. El RPC de guardado aprende los dos campos nuevos ─────────────────────
-- Misma transacción que en la 073 (reemplazo atómico de los renglones); lo único que cambia
-- es que ahora lee `included` e `is_cooking_fat` del JSON. Con default true / false, un
-- payload viejo se sigue comportando igual.

create or replace function public.skandi_save_meal_items(
  p_meal_id uuid,
  p_items   jsonb,
  p_status  text default 'ready',
  p_confidence numeric default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid;
begin
  select user_id into owner from public.skandi_meals where id = p_meal_id;
  if owner is null then
    raise exception 'meal % not found', p_meal_id;
  end if;
  if owner <> auth.uid() and auth.uid() is not null then
    raise exception 'not your meal';
  end if;

  delete from public.skandi_meal_items where meal_id = p_meal_id;

  insert into public.skandi_meal_items
    (meal_id, user_id, food_id, label, grams, kcal, protein_g, carbs_g, fat_g, fiber_g,
     source, ai_confidence, sort_order, included, is_cooking_fat)
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
    coalesce(nullif(item->>'source',''), 'ai'),
    nullif(item->>'ai_confidence','')::numeric,
    coalesce(nullif(item->>'sort_order','')::integer, ordinality::integer),
    coalesce((item->>'included')::boolean, true),
    coalesce((item->>'is_cooking_fat')::boolean, false)
  from jsonb_array_elements(p_items) with ordinality as t(item, ordinality);

  update public.skandi_meals
  set analysis_status = p_status,
      ai_confidence   = coalesce(p_confidence, ai_confidence),
      analysis_error  = null
  where id = p_meal_id;
end;
$$;

revoke all on function public.skandi_save_meal_items(uuid, jsonb, text, numeric) from public;
grant execute on function public.skandi_save_meal_items(uuid, jsonb, text, numeric) to authenticated, service_role;

-- ── 6. Contador de uso del catálogo ─────────────────────────────────────────
-- times_used ordena qué alimentos se le mandan al modelo como referencia. Incrementarlo
-- desde el cliente con un update directo es una carrera; aquí es una sola sentencia.

create or replace function public.skandi_bump_food_usage(p_food_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.skandi_foods
  set times_used = times_used + 1, updated_at = now()
  where id = any(p_food_ids)
    and (user_id = auth.uid() or user_id is null);
end;
$$;

revoke all on function public.skandi_bump_food_usage(uuid[]) from public;
grant execute on function public.skandi_bump_food_usage(uuid[]) to authenticated, service_role;
