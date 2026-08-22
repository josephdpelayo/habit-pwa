-- Skandi Fit: nutrición. La mitad faltante de la ecuación — sin ingesta calórica, un
-- estancamiento por técnica y uno por comer 1,600 kcal se ven idénticos en los datos.
--
-- Cuatro decisiones de diseño que valen más que el DDL:
--
-- 1. Los macros de cada renglón se guardan ABSOLUTOS (ya multiplicados por los gramos),
--    no por 100 g. Corregir hoy un alimento del catálogo no debe reescribir la comida del
--    mes pasado: un diario es un histórico, no una vista calculada.
-- 2. Los totales de skandi_meals los mantiene un trigger, nunca la app. Es el bug clásico
--    de todo diario de comida: dos rutas escribiendo la misma suma y una que se olvida.
-- 3. La comida es PRIVADA. Sin visibility 'crew' como skandi_sessions: no hay política que
--    la exponga al feed, y el bucket de fotos es privado (a diferencia del de ejercicios,
--    migración 058, que es público a propósito).
-- 4. El tope de llamadas a la IA vive en la base, no en el cliente. Un bug en la UI no
--    puede gastar de más si la cuota se verifica del lado del servidor.

-- ── 1. Catálogo de alimentos ────────────────────────────────────────────────
-- user_id null = alimento global (semilla compartida). Con user_id = catálogo personal,
-- que es lo que hace que la estimación mejore con el uso: cada corrección tuya se vuelve
-- una referencia que el prompt le pasa al modelo la próxima vez.

create table if not exists public.skandi_foods (
  id             uuid primary key default uuid_generate_v4(),
  user_id        uuid references public.profiles(id) on delete cascade,
  name           text not null,
  brand          text,
  barcode        text,
  serving_label  text,                    -- '1 taza', '1 pieza', '2 tortillas'
  serving_grams  numeric(7,2) check (serving_grams is null or serving_grams between 0 and 5000),
  kcal_100g      numeric(7,2) not null check (kcal_100g between 0 and 1000),
  protein_100g   numeric(6,2) not null default 0 check (protein_100g between 0 and 100),
  carbs_100g     numeric(6,2) not null default 0 check (carbs_100g between 0 and 100),
  fat_100g       numeric(6,2) not null default 0 check (fat_100g between 0 and 100),
  fiber_100g     numeric(6,2) not null default 0 check (fiber_100g between 0 and 100),
  source         text not null default 'manual' check (source in ('ai','manual','catalog','off')),
  times_used     integer not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- Un mismo nombre no se duplica dentro del catálogo de una persona (ni entre los globales).
create unique index if not exists idx_skandi_foods_user_name
  on public.skandi_foods(coalesce(user_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name), coalesce(lower(brand), ''));
create index if not exists idx_skandi_foods_user_used
  on public.skandi_foods(user_id, times_used desc);
create index if not exists idx_skandi_foods_barcode
  on public.skandi_foods(barcode) where barcode is not null;

-- ── 2. Comidas ──────────────────────────────────────────────────────────────
-- La fila se crea ANTES de llamar al modelo (analysis_status='pending'). Si la IA tarda o
-- falla, la comida ya quedó registrada: un diario que pierde entradas por un timeout no se
-- usa dos semanas. 'failed' permite reintentar y 'manual' es la salida sin IA.

create table if not exists public.skandi_meals (
  id              uuid primary key default uuid_generate_v4(),
  user_id         uuid references public.profiles(id) on delete cascade not null,
  eaten_at        timestamptz not null default now(),
  meal_type       text not null default 'snack'
                    check (meal_type in ('desayuno','comida','cena','snack')),
  photo_path      text,                   -- ruta dentro del bucket privado skandi-meals
  note            text,
  kcal            numeric(8,2) not null default 0,   -- mantenidos por trigger
  protein_g       numeric(7,2) not null default 0,
  carbs_g         numeric(7,2) not null default 0,
  fat_g           numeric(7,2) not null default 0,
  fiber_g         numeric(7,2) not null default 0,
  analysis_status text not null default 'manual'
                    check (analysis_status in ('pending','ready','failed','manual')),
  analysis_error  text,
  ai_confidence   numeric(3,2) check (ai_confidence is null or ai_confidence between 0 and 1),
  created_at      timestamptz not null default now()
);

create index if not exists idx_skandi_meals_user_eaten
  on public.skandi_meals(user_id, eaten_at desc);

-- ── 3. Renglones de cada comida ─────────────────────────────────────────────

create table if not exists public.skandi_meal_items (
  id            uuid primary key default uuid_generate_v4(),
  meal_id       uuid references public.skandi_meals(id) on delete cascade not null,
  user_id       uuid references public.profiles(id) on delete cascade not null,
  food_id       uuid references public.skandi_foods(id) on delete set null,
  label         text not null,
  grams         numeric(7,2) check (grams is null or grams between 0 and 5000),
  kcal          numeric(7,2) not null default 0 check (kcal between 0 and 10000),
  protein_g     numeric(6,2) not null default 0 check (protein_g between 0 and 1000),
  carbs_g       numeric(6,2) not null default 0 check (carbs_g between 0 and 1000),
  fat_g         numeric(6,2) not null default 0 check (fat_g between 0 and 1000),
  fiber_g       numeric(6,2) not null default 0 check (fiber_g between 0 and 1000),
  source        text not null default 'manual' check (source in ('ai','manual','catalog')),
  ai_confidence numeric(3,2) check (ai_confidence is null or ai_confidence between 0 and 1),
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now()
);

create index if not exists idx_skandi_meal_items_meal
  on public.skandi_meal_items(meal_id, sort_order);

-- ── 4. Trigger de totales ───────────────────────────────────────────────────

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
    from public.skandi_meal_items where meal_id = target
  ) t
  where m.id = target;
  return null;
end;
$$;

drop trigger if exists trg_skandi_meal_items_totals on public.skandi_meal_items;
create trigger trg_skandi_meal_items_totals
  after insert or update or delete on public.skandi_meal_items
  for each row execute function public.skandi_recalc_meal_totals();

-- ── 5. Metas diarias ────────────────────────────────────────────────────────
-- Una fila por persona. auto = recalcular kcal/macros solos cuando registres peso nuevo
-- (Mifflin-St Jeor x factor de actividad, ajustado por el modo). Editables a mano: si
-- pones un número tú, manda el tuyo.

create table if not exists public.skandi_nutrition_targets (
  user_id          uuid primary key references public.profiles(id) on delete cascade,
  mode             text not null default 'mantenimiento'
                     check (mode in ('deficit','mantenimiento','superavit')),
  kcal_target      integer not null check (kcal_target between 800 and 8000),
  protein_g_target integer not null check (protein_g_target between 0 and 500),
  carbs_g_target   integer not null check (carbs_g_target between 0 and 1200),
  fat_g_target     integer not null check (fat_g_target between 0 and 400),
  activity_factor  numeric(3,2) not null default 1.55 check (activity_factor between 1.0 and 2.5),
  auto             boolean not null default true,
  updated_at       timestamptz not null default now()
);

-- ── 6. Cuota de IA ──────────────────────────────────────────────────────────
-- El endpoint incrementa con service-role antes de llamar al modelo. Vive en la base
-- justamente para que ningún bug del cliente pueda saltársela.

create table if not exists public.skandi_ai_usage (
  user_id    uuid references public.profiles(id) on delete cascade not null,
  day        date not null default current_date,
  calls      integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

-- ── 7. RLS ──────────────────────────────────────────────────────────────────

alter table public.skandi_foods enable row level security;
alter table public.skandi_meals enable row level security;
alter table public.skandi_meal_items enable row level security;
alter table public.skandi_nutrition_targets enable row level security;
alter table public.skandi_ai_usage enable row level security;

-- Alimentos: lees los tuyos y los globales; escribes solo los tuyos.
drop policy if exists "Skandi read own and global foods" on public.skandi_foods;
create policy "Skandi read own and global foods"
  on public.skandi_foods for select
  using (user_id is null or user_id = auth.uid());

drop policy if exists "Skandi manage own foods" on public.skandi_foods;
create policy "Skandi manage own foods"
  on public.skandi_foods for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Comidas, renglones y metas: estrictamente privados. Sin excepción para el crew.
drop policy if exists "Skandi manage own meals" on public.skandi_meals;
create policy "Skandi manage own meals"
  on public.skandi_meals for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Skandi manage own meal items" on public.skandi_meal_items;
create policy "Skandi manage own meal items"
  on public.skandi_meal_items for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Skandi manage own nutrition targets" on public.skandi_nutrition_targets;
create policy "Skandi manage own nutrition targets"
  on public.skandi_nutrition_targets for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Cuota: la lees para pintar "te quedan N análisis hoy"; escribirla es cosa del servidor.
drop policy if exists "Skandi read own ai usage" on public.skandi_ai_usage;
create policy "Skandi read own ai usage"
  on public.skandi_ai_usage for select
  using (user_id = auth.uid());

-- ── 8. Bucket privado de fotos ──────────────────────────────────────────────
-- OJO: privado. El bucket de media de ejercicios (058) es público porque es un catálogo
-- compartido; las fotos de tu comida no lo son. Se sirven con signed URL.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'skandi-meals',
  'skandi-meals',
  false,
  10485760, -- 10 MB: la app sube ~150 KB (lado largo 1024 px, JPEG 0.8)
  array['image/jpeg','image/jpg','image/png','image/webp','image/heic']
)
on conflict (id) do nothing;

-- Cada quien manda solo en su carpeta: skandi-meals/{user_id}/{uuid}.jpg
drop policy if exists "Skandi meal photos are per-user" on storage.objects;
create policy "Skandi meal photos are per-user"
  on storage.objects for all
  to authenticated
  using (bucket_id = 'skandi-meals' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'skandi-meals' and (storage.foldername(name))[1] = auth.uid()::text);

-- ── 9. RPC: guardar el resultado del análisis en una sola transacción ───────
-- El endpoint reemplaza los renglones de una comida de golpe. Si esto fueran tres llamadas
-- desde el cliente, un corte de red a la mitad dejaría la comida con la mitad de la
-- comida. security definer + verificación explícita del dueño.

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
     source, ai_confidence, sort_order)
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
    coalesce(nullif(item->>'sort_order','')::integer, ordinality::integer)
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
