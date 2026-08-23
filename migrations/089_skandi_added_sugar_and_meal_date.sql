-- Skandi Fit: azúcar añadida y la fecha real de la comida.
--
-- Dos huecos que se descubrieron usando la pestaña de comida en el barco:
--
-- 1. FECHA. `skandi_meals.eaten_at` tenía default now() y NINGUNA de las cuatro rutas de
--    alta lo escribía. Registrar anoche la cena de ayer la contaba en el día de hoy, y no
--    había forma de corregirlo. Aquí solo se agrega `photo_taken_at` (la fecha EXIF de la
--    foto, que es el mejor testigo de cuándo se comió); poder elegir la fecha es cosa del
--    cliente, que ya tenía la columna disponible y no la usaba.
--
-- 2. AZÚCAR AÑADIDA. La 077 metió `sugar_g` como techo, pero mide azúcares TOTALES: el
--    plátano y el refresco cuentan igual. Eso hace el techo inservible — la fruta entera
--    trae fibra y agua, no es lo que la OMS pide limitar. Así que el azúcar se parte en dos
--    y el techo pasa a colgar de la parte AÑADIDA. `sugar_g` se conserva y se sigue
--    llenando: el azúcar total es información buena, simplemente no es contra lo que uno
--    se mide. `added_sugar_g <= sugar_g` no se fuerza con un check — el modelo estima las
--    dos por separado y un check que se dispara a media noche por un redondeo convierte un
--    error de estimación en una comida que no se puede guardar.
--
-- Ninguna kcal cambia: la añadida ya está dentro de sugar_g, que ya está dentro de carbs_g.

-- ── 1. Columnas ─────────────────────────────────────────────────────────────

alter table public.skandi_foods
  add column if not exists added_sugar_100g numeric(6,2) not null default 0
    check (added_sugar_100g between 0 and 100);

alter table public.skandi_meal_items
  add column if not exists added_sugar_g numeric(6,2) not null default 0
    check (added_sugar_g between 0 and 1000);

alter table public.skandi_meals
  add column if not exists added_sugar_g numeric(7,2) not null default 0,
  add column if not exists photo_taken_at timestamptz;

comment on column public.skandi_meals.photo_taken_at is
  'DateTimeOriginal del EXIF de la foto, cuando venía. Es la referencia que propone eaten_at; '
  'se guarda aparte porque eaten_at es editable y esta no: es lo que dijo la cámara.';

alter table public.skandi_dish_items
  add column if not exists added_sugar_g numeric(6,2) not null default 0;

alter table public.skandi_nutrition_targets
  add column if not exists added_sugar_g_target integer
    check (added_sugar_g_target is null or added_sugar_g_target between 0 and 500);

comment on column public.skandi_nutrition_targets.added_sugar_g_target is
  'Techo de azúcar AÑADIDA (no total). Null = no se rastrea. La OMS pide <10% de las kcal '
  'y sugiere <5%: a 2,400 kcal son 60 g y 30 g. Es un techo, no una meta.';

-- ── 2. El trigger de totales ────────────────────────────────────────────────

create or replace function public.skandi_meal_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid := coalesce(new.meal_id, old.meal_id);
begin
  update public.skandi_meals m
  set kcal          = coalesce(t.kcal, 0),
      protein_g     = coalesce(t.protein_g, 0),
      carbs_g       = coalesce(t.carbs_g, 0),
      fat_g         = coalesce(t.fat_g, 0),
      fiber_g       = coalesce(t.fiber_g, 0),
      sugar_g       = coalesce(t.sugar_g, 0),
      added_sugar_g = coalesce(t.added_sugar_g, 0)
  from (
    select sum(kcal) kcal, sum(protein_g) protein_g, sum(carbs_g) carbs_g,
           sum(fat_g) fat_g, sum(fiber_g) fiber_g, sum(sugar_g) sugar_g,
           sum(added_sugar_g) added_sugar_g
    from public.skandi_meal_items
    where meal_id = target and included
  ) t
  where m.id = target;
  return null;
end;
$$;

-- ── 3. Los cuatro RPC que escriben renglones ───────────────────────────────

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
    -- Un renglón viejo sin el campo no inventa azúcar añadida: 0 es "no sabemos", y para un
    -- techo la lectura honesta de "no sabemos" es no acusar.
    least(
      coalesce(nullif(item->>'added_sugar_g','')::numeric, 0),
      coalesce(nullif(item->>'sugar_g','')::numeric, 0)
    ),
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

create or replace function public.skandi_save_meal_as_dish(
  p_meal_id uuid,
  p_name    text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  owner    uuid;
  m_venue  text;
  dish     uuid;
begin
  select user_id, venue into owner, m_venue from public.skandi_meals where id = p_meal_id;
  if owner is null then
    raise exception 'meal % not found', p_meal_id;
  end if;
  if owner <> auth.uid() and auth.uid() is not null then
    raise exception 'not your meal';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'el platillo necesita nombre';
  end if;

  insert into public.skandi_dishes (user_id, name, venue, source_meal_id)
  values (owner, trim(p_name), m_venue, p_meal_id)
  on conflict (user_id, lower(name)) do update
    set venue = excluded.venue,
        source_meal_id = excluded.source_meal_id,
        updated_at = now()
  returning id into dish;

  delete from public.skandi_dish_items where dish_id = dish;

  insert into public.skandi_dish_items
    (dish_id, user_id, food_id, label, grams, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g,
     added_sugar_g, included, is_cooking_fat, sort_order)
  select dish, owner, food_id, label, grams, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g,
         added_sugar_g, included, is_cooking_fat, sort_order
  from public.skandi_meal_items
  where meal_id = p_meal_id;

  return dish;
end;
$$;

create or replace function public.skandi_create_meal_from_dish(
  p_dish_id   uuid,
  p_meal_type text default 'snack',
  p_scale     numeric default 1,
  p_eaten_at  timestamptz default now(),
  p_note      text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  owner  uuid;
  d_name text;
  d_venue text;
  scale  numeric := greatest(0.1, least(coalesce(p_scale, 1), 10));
  meal   uuid;
begin
  select user_id, name, venue into owner, d_name, d_venue
  from public.skandi_dishes where id = p_dish_id;
  if owner is null then
    raise exception 'dish % not found', p_dish_id;
  end if;
  if owner <> auth.uid() and auth.uid() is not null then
    raise exception 'not your dish';
  end if;

  insert into public.skandi_meals
    (user_id, eaten_at, meal_type, note, venue, input_kind, analysis_status, dish_id, dish_scale)
  values
    (owner, coalesce(p_eaten_at, now()), p_meal_type, coalesce(p_note, d_name), d_venue,
     'manual', 'manual', p_dish_id, scale)
  returning id into meal;

  insert into public.skandi_meal_items
    (meal_id, user_id, food_id, label, grams, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g,
     added_sugar_g, source, included, is_cooking_fat, sort_order)
  select
    meal, owner, food_id, label,
    least(round(coalesce(grams, 0) * scale, 1), 5000),
    least(round(kcal          * scale, 1), 10000),
    least(round(protein_g     * scale, 1), 1000),
    least(round(carbs_g       * scale, 1), 1000),
    least(round(fat_g         * scale, 1), 1000),
    least(round(fiber_g       * scale, 1), 1000),
    least(round(sugar_g       * scale, 1), 1000),
    least(round(added_sugar_g * scale, 1), 1000),
    'catalog', included, is_cooking_fat, sort_order
  from public.skandi_dish_items
  where dish_id = p_dish_id;

  update public.skandi_dishes
  set times_used = times_used + 1, last_used_at = now()
  where id = p_dish_id;

  return meal;
end;
$$;

create or replace function public.skandi_add_food_to_meal(
  p_meal_id uuid,
  p_food_id uuid,
  p_grams   numeric
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid;
  f     public.skandi_foods%rowtype;
  k     numeric;
  item  uuid;
  nextp integer;
begin
  select user_id into owner from public.skandi_meals where id = p_meal_id;
  if owner is null then
    raise exception 'meal % not found', p_meal_id;
  end if;
  if owner <> auth.uid() and auth.uid() is not null then
    raise exception 'not your meal';
  end if;

  select * into f from public.skandi_foods
  where id = p_food_id and (user_id = owner or user_id is null);
  if f.id is null then
    raise exception 'food % not found', p_food_id;
  end if;
  if p_grams is null or p_grams <= 0 then
    raise exception 'los gramos deben ser mayores a cero';
  end if;

  k := least(p_grams, 5000) / 100.0;

  select coalesce(max(sort_order), 0) + 1 into nextp
  from public.skandi_meal_items where meal_id = p_meal_id;

  insert into public.skandi_meal_items
    (meal_id, user_id, food_id, label, grams, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g,
     added_sugar_g, source, sort_order)
  values (
    p_meal_id, owner, f.id,
    case when f.brand is null or f.brand = '' then f.name else f.name || ' (' || f.brand || ')' end,
    least(p_grams, 5000),
    least(round(f.kcal_100g         * k, 1), 10000),
    least(round(f.protein_100g      * k, 1), 1000),
    least(round(f.carbs_100g        * k, 1), 1000),
    least(round(f.fat_100g          * k, 1), 1000),
    least(round(f.fiber_100g        * k, 1), 1000),
    least(round(f.sugar_100g        * k, 1), 1000),
    least(round(f.added_sugar_100g  * k, 1), 1000),
    'catalog', nextp
  )
  returning id into item;

  update public.skandi_foods
  set times_used = times_used + 1, updated_at = now()
  where id = f.id;

  return item;
end;
$$;

-- ── 4. Un techo por default para quien ya tenía uno de azúcar total ────────
-- Quien traía sugar_g_target puesto quería limitar azúcar; lo que quería limitar era la
-- añadida. Se copia el mismo número en vez de dejarlo null y que la barra desaparezca.

update public.skandi_nutrition_targets
set added_sugar_g_target = sugar_g_target
where added_sugar_g_target is null and sugar_g_target is not null;

-- ── 5. Re-sumar ─────────────────────────────────────────────────────────────

update public.skandi_meals m
set added_sugar_g = coalesce((
  select sum(i.added_sugar_g) from public.skandi_meal_items i
  where i.meal_id = m.id and i.included
), 0);
