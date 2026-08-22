-- Skandi Fit: platillos guardados. La forma más barata de estimar una comida es no estimarla.
--
-- La comida real se repite: el mismo desayuno cuatro veces por semana, el mismo pollo con
-- arroz de la tarde. Volver a mandarle esa foto al modelo cada vez es pagar por una respuesta
-- que ya tenemos — y peor, es tirar las correcciones que el usuario hizo a mano la primera
-- vez, porque una estimación nueva no las recuerda.
--
-- El truco de esta migración es CUÁNDO se guarda el platillo: después de corregirlo. El
-- snapshot no es lo que la IA adivinó, es lo que el usuario dejó bien. Registrarlo otra vez
-- es una copia escalada por un factor de porción — cero tokens, respuesta instantánea, y
-- funciona sin señal.
--
-- Tres niveles, de más barato a más caro:
--   1. Platillo guardado  -> copiar y escalar             (0 tokens)
--   2. Alimento del catálogo + gramos -> un renglón       (0 tokens)
--   3. Foto o descripción -> IA                            (~1-3 centavos)
-- La app debe ofrecerlos en ese orden. La IA es el último recurso, no el primero.

-- ── 1. El platillo ──────────────────────────────────────────────────────────

create table if not exists public.skandi_dishes (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid references public.profiles(id) on delete cascade not null,
  name          text not null,
  notes         text,
  -- Lugar habitual: un platillo de casa arrastra su decisión sobre el aceite.
  venue         text check (venue is null or venue in ('casa','restaurante','fonda','otro')),
  -- De qué comida se sacó el snapshot. Solo para rastro; borrar esa comida no borra el platillo.
  source_meal_id uuid references public.skandi_meals(id) on delete set null,
  times_used    integer not null default 0,
  last_used_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Un nombre, un platillo. Guardar "Avena de la mañana" dos veces actualiza, no duplica.
create unique index if not exists idx_skandi_dishes_user_name
  on public.skandi_dishes(user_id, lower(name));
create index if not exists idx_skandi_dishes_user_used
  on public.skandi_dishes(user_id, times_used desc, last_used_at desc);

create table if not exists public.skandi_dish_items (
  id             uuid primary key default uuid_generate_v4(),
  dish_id        uuid references public.skandi_dishes(id) on delete cascade not null,
  user_id        uuid references public.profiles(id) on delete cascade not null,
  food_id        uuid references public.skandi_foods(id) on delete set null,
  label          text not null,
  grams          numeric(7,2),
  -- Macros de la porción base (factor 1), absolutos, igual que en skandi_meal_items.
  kcal           numeric(7,2) not null default 0,
  protein_g      numeric(6,2) not null default 0,
  carbs_g        numeric(6,2) not null default 0,
  fat_g          numeric(6,2) not null default 0,
  fiber_g        numeric(6,2) not null default 0,
  included       boolean not null default true,
  is_cooking_fat boolean not null default false,
  sort_order     integer not null default 0
);

create index if not exists idx_skandi_dish_items_dish
  on public.skandi_dish_items(dish_id, sort_order);

-- El platillo hereda del que ya se comió: guardamos también de dónde vino cada comida.
alter table public.skandi_meals
  add column if not exists dish_id uuid references public.skandi_dishes(id) on delete set null,
  add column if not exists dish_scale numeric(4,2) check (dish_scale is null or dish_scale between 0.1 and 10);

comment on column public.skandi_meals.dish_id is
  'si esta comida se registró desde un platillo guardado, cuál — permite medir qué tanto se repite';

alter table public.skandi_dishes enable row level security;
alter table public.skandi_dish_items enable row level security;

drop policy if exists "Skandi manage own dishes" on public.skandi_dishes;
create policy "Skandi manage own dishes"
  on public.skandi_dishes for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Skandi manage own dish items" on public.skandi_dish_items;
create policy "Skandi manage own dish items"
  on public.skandi_dish_items for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── 2. Guardar una comida ya corregida como platillo ────────────────────────
-- Copia los renglones TAL COMO QUEDARON, incluidos los desmarcados y la grasa de cocción con
-- su estado: si decidiste que tu desayuno de casa no lleva aceite, el platillo lo recuerda.

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

  -- Re-guardar con el mismo nombre reemplaza la receta: es "actualizar mi platillo".
  delete from public.skandi_dish_items where dish_id = dish;

  insert into public.skandi_dish_items
    (dish_id, user_id, food_id, label, grams, kcal, protein_g, carbs_g, fat_g, fiber_g,
     included, is_cooking_fat, sort_order)
  select dish, owner, food_id, label, grams, kcal, protein_g, carbs_g, fat_g, fiber_g,
         included, is_cooking_fat, sort_order
  from public.skandi_meal_items
  where meal_id = p_meal_id;

  return dish;
end;
$$;

revoke all on function public.skandi_save_meal_as_dish(uuid, text) from public;
grant execute on function public.skandi_save_meal_as_dish(uuid, text) to authenticated, service_role;

-- ── 3. Registrar un platillo (con porción) ──────────────────────────────────
-- p_scale es el único parámetro que cambia el día a día: 0.5 = media porción, 2 = doble.
-- Todo en una transacción: la comida y sus renglones nacen juntos o no nacen.

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

  -- least() replica los CHECK de skandi_meal_items: escalar x10 un platillo grande no debe
  -- reventar el insert, y perder la comida por un tope es peor que guardarla topada.
  insert into public.skandi_meal_items
    (meal_id, user_id, food_id, label, grams, kcal, protein_g, carbs_g, fat_g, fiber_g,
     source, included, is_cooking_fat, sort_order)
  select
    meal, owner, food_id, label,
    least(round(coalesce(grams, 0) * scale, 1), 5000),
    least(round(kcal      * scale, 1), 10000),
    least(round(protein_g * scale, 1), 1000),
    least(round(carbs_g   * scale, 1), 1000),
    least(round(fat_g     * scale, 1), 1000),
    least(round(fiber_g   * scale, 1), 1000),
    'catalog', included, is_cooking_fat, sort_order
  from public.skandi_dish_items
  where dish_id = p_dish_id;

  update public.skandi_dishes
  set times_used = times_used + 1, last_used_at = now()
  where id = p_dish_id;

  return meal;
end;
$$;

revoke all on function public.skandi_create_meal_from_dish(uuid, text, numeric, timestamptz, text) from public;
grant execute on function public.skandi_create_meal_from_dish(uuid, text, numeric, timestamptz, text) to authenticated, service_role;

-- ── 4. Un alimento suelto del catálogo, sin IA ──────────────────────────────
-- El segundo nivel de ahorro: "180 g de pechuga" no necesita un modelo, necesita una
-- multiplicación. Escala los macros por 100 g del catálogo a los gramos que se comió.

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
    (meal_id, user_id, food_id, label, grams, kcal, protein_g, carbs_g, fat_g, fiber_g,
     source, sort_order)
  values (
    p_meal_id, owner, f.id,
    case when f.brand is null or f.brand = '' then f.name else f.name || ' (' || f.brand || ')' end,
    least(p_grams, 5000),
    least(round(f.kcal_100g    * k, 1), 10000),
    least(round(f.protein_100g * k, 1), 1000),
    least(round(f.carbs_100g   * k, 1), 1000),
    least(round(f.fat_100g     * k, 1), 1000),
    least(round(f.fiber_100g   * k, 1), 1000),
    'catalog', nextp
  )
  returning id into item;

  update public.skandi_foods
  set times_used = times_used + 1, updated_at = now()
  where id = f.id;

  return item;
end;
$$;

revoke all on function public.skandi_add_food_to_meal(uuid, uuid, numeric) from public;
grant execute on function public.skandi_add_food_to_meal(uuid, uuid, numeric) to authenticated, service_role;

-- ── 5. Vista de sugerencias: qué ofrecerle antes de encender la IA ──────────
-- Una sola consulta que la app puede pedir al abrir el tab Comida: los platillos y alimentos
-- que más repites, ordenados por uso. Es la lista que hace que la IA casi nunca haga falta.

create or replace view public.skandi_quick_picks as
select
  'dish'::text  as kind,
  d.id,
  d.user_id,
  d.name,
  null::text    as brand,
  d.times_used,
  d.last_used_at,
  (select coalesce(sum(i.kcal), 0) from public.skandi_dish_items i
    where i.dish_id = d.id and i.included) as kcal
from public.skandi_dishes d
union all
select
  'food'::text,
  f.id,
  f.user_id,
  f.name,
  f.brand,
  f.times_used,
  null::timestamptz,
  f.kcal_100g
from public.skandi_foods f
where f.user_id is not null;

-- La vista hereda la RLS de las tablas base (security_invoker), así que cada quien ve
-- solo lo suyo sin necesidad de política propia.
alter view public.skandi_quick_picks set (security_invoker = true);

grant select on public.skandi_quick_picks to authenticated;
