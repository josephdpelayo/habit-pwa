-- Skandi Fit: metas de nutrición por fecha específica, y dos tipos de comida nuevos.
--
-- Por qué por FECHA y no por día de la semana: skandi_nutrition_targets (migración 073) es una
-- sola fila por persona porque una meta normal no cambia día a día. Pero una semana de descarga
-- (o de viaje, o de refeed) sí trae números distintos cada día, y esos números son de ESA semana
-- en particular — igual que skandi_planned_sessions guarda `day` (fecha) y no `weekday`, para
-- justo no contaminar las semanas futuras (ver el comentario de la migración 086). Una fila por
-- (user_id, target_date): la semana normal sigue viviendo en skandi_nutrition_targets sin tocarla,
-- y cuando exista una fila aquí para el día que se está viendo, esa fila manda.
--
-- Columnas nullable a propósito: la tabla de tu coach normalmente solo mueve kcal y carbohidratos
-- (proteína y grasa se quedan igual todos los días), así que un override puede fijar nada más esos
-- dos y dejar que proteína/grasa/azúcar caigan a la meta base de skandi_nutrition_targets.

create table if not exists public.skandi_nutrition_target_overrides (
  id                    uuid primary key default uuid_generate_v4(),
  user_id               uuid references public.profiles(id) on delete cascade not null,
  target_date           date not null,
  kcal_target           integer check (kcal_target is null or kcal_target between 800 and 8000),
  protein_g_target      integer check (protein_g_target is null or protein_g_target between 0 and 500),
  carbs_g_target        integer check (carbs_g_target is null or carbs_g_target between 0 and 1200),
  fat_g_target          integer check (fat_g_target is null or fat_g_target between 0 and 400),
  note                  text,
  created_at            timestamptz not null default now(),
  unique (user_id, target_date)
);

alter table public.skandi_nutrition_target_overrides enable row level security;

drop policy if exists "Skandi manage own nutrition target overrides" on public.skandi_nutrition_target_overrides;
create policy "Skandi manage own nutrition target overrides"
  on public.skandi_nutrition_target_overrides for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── Dos tipos de comida más ──────────────────────────────────────────────────
-- 'pre_entreno' / 'post_entreno': cuándo se comió importa tanto como qué, sobre todo alrededor
-- de una sesión — desayuno/comida/cena/snack no dicen si algo se comió a propósito antes o
-- después de entrenar. guessMealType() en skandi.html no cambia: sigue proponiendo por hora del
-- día, y estos dos quedan como elección explícita, no adivinada.

alter table public.skandi_meals drop constraint if exists skandi_meals_meal_type_check;
alter table public.skandi_meals add constraint skandi_meals_meal_type_check
  check (meal_type in ('desayuno','comida','cena','snack','pre_entreno','post_entreno'));
