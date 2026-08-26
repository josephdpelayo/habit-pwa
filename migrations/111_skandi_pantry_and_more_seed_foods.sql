-- Skandi Fit: alacena + catálogo de alimentos más grande.
--
-- Dos cosas, una migración: la segunda no existe sin la primera teniendo de dónde elegir.

-- ── 1. Alacena ───────────────────────────────────────────────────────────────
--
-- "Lo que tengo ahorita a bordo" — un miembro marca alimentos de su catálogo (propio o
-- global) como disponibles, y esa lista es lo primero que la sugerencia de qué comer
-- (`action:'meal-suggestion'`) intenta usar antes de inventar algo con lo que probablemente
-- no cuenta hoy. No es un conteo de existencias (cuántos gramos quedan): es un check-off,
-- igual de deliberadamente simple que skandi_supplements (093) — la fila existe o no existe,
-- sin columna de cantidad que mantener honesta.

create table if not exists public.skandi_pantry (
  id         uuid primary key default uuid_generate_v4(),
  user_id    uuid references public.profiles(id) on delete cascade not null,
  food_id    uuid references public.skandi_foods(id) on delete cascade not null,
  created_at timestamptz not null default now()
);

-- Un alimento no se marca dos veces en la misma alacena.
create unique index if not exists idx_skandi_pantry_user_food
  on public.skandi_pantry(user_id, food_id);
create index if not exists idx_skandi_pantry_user
  on public.skandi_pantry(user_id, created_at desc);

alter table public.skandi_pantry enable row level security;

drop policy if exists "Skandi manage own pantry" on public.skandi_pantry;
create policy "Skandi manage own pantry"
  on public.skandi_pantry for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── 2. Más alimentos globales ─────────────────────────────────────────────────
--
-- La 093 sembró 20 básicos. La alacena solo sirve si lo que la gente de verdad tiene a bordo
-- está en el catálogo para poder marcarlo — fruta, pan, más variantes de proteína. Mismo
-- mecanismo (`user_id is null` = visible para todo el crew), mismos valores de referencia
-- (USDA / bases de datos públicas), no la dieta de nadie en particular. Nombres que ya
-- existen de la 093 (Plátano, Avena, Aceite de oliva, Atún en agua...) se omiten aquí.

insert into public.skandi_foods
  (user_id, name, serving_label, kcal_100g, protein_100g, carbs_100g, fat_100g, fiber_100g, sugar_100g, source)
values
  -- Fruta
  (null, 'Manzana',            '1 pieza ~180 g',  52,  0.3, 13.8, 0.2, 2.4, 10.4, 'catalog'),
  (null, 'Fresas',              '1 taza ~150 g',   32,  0.7,  7.7, 0.3, 2.0,  4.9, 'catalog'),
  (null, 'Dátiles',             '3 piezas ~30 g', 282,  2.5, 75.0, 0.4, 8.0, 63.0, 'catalog'),
  (null, 'Naranja',             '1 pieza ~130 g',  47,  0.9, 11.8, 0.1, 2.4,  9.4, 'catalog'),
  (null, 'Pera',                '1 pieza ~180 g',  57,  0.4, 15.2, 0.1, 3.1,  9.8, 'catalog'),
  (null, 'Uva',                 '1 taza ~150 g',   69,  0.7, 18.1, 0.2, 0.9, 15.5, 'catalog'),
  (null, 'Sandía',              '1 taza ~150 g',   30,  0.6,  7.6, 0.2, 0.4,  6.2, 'catalog'),
  (null, 'Papaya',              '1 taza ~145 g',   43,  0.5, 10.8, 0.3, 1.7,  7.8, 'catalog'),
  (null, 'Mango',               '1 pieza ~200 g',  60,  0.8, 15.0, 0.4, 1.6, 13.7, 'catalog'),
  (null, 'Piña',                '1 taza ~165 g',   50,  0.5, 13.1, 0.1, 1.4,  9.9, 'catalog'),
  (null, 'Arándanos',           '1 taza ~150 g',   57,  0.7, 14.5, 0.3, 2.4,  10.0, 'catalog'),
  (null, 'Fresa deshidratada',  '1 puño ~20 g',   339,  4.7, 76.0, 3.7, 8.0, 60.0, 'catalog'),
  -- Pan y cereales
  (null, 'Pan blanco',          '1 rebanada ~30 g',266, 9.0, 50.0, 3.3, 2.4,  5.0, 'catalog'),
  (null, 'Pan integral',        '1 rebanada ~30 g',247, 13.0, 41.0, 4.2, 7.0,  5.7, 'catalog'),
  (null, 'Tortilla de harina',  '1 pieza ~30 g',   312, 8.2, 51.0, 8.4, 2.4,  1.9, 'catalog'),
  (null, 'Cereal de maíz',      '1 taza ~30 g',    357,  7.0, 84.0, 0.9, 3.0,  9.0, 'catalog'),
  (null, 'Granola',             '1/2 taza ~40 g',  471,  10.0, 64.0, 20.0, 7.0, 24.0, 'catalog'),
  -- Proteína
  (null, 'Medallón de atún fresco', '1 pieza ~150 g', 144, 23.3, 0,   4.9, 0,    0,  'catalog'),
  (null, 'Atún en aceite',      '1 lata ~140 g',   198, 25.0,  0,   10.2, 0,    0,  'catalog'),
  (null, 'Carne molida de res (90/10)','1 taza ~150 g',176, 20.0, 0, 10.0, 0,    0,  'catalog'),
  (null, 'Bistec de res',       '1 pieza ~150 g',  217, 26.1,  0,  11.8, 0,    0,  'catalog'),
  (null, 'Milanesa de pollo empanizada','1 pieza ~150 g',245,15.0, 15.0, 13.0, 1.0, 1.0, 'catalog'),
  (null, 'Camarón',             '1 taza ~140 g',    99, 24.0,  0.2, 0.3, 0,    0,  'catalog'),
  (null, 'Filete de tilapia',   '1 pieza ~150 g',   96, 20.1,  0,   1.7, 0,    0,  'catalog'),
  (null, 'Jamón de pavo',       '2 rebanadas ~50 g',102, 17.0,  2.0, 2.0, 0,    1.0, 'catalog'),
  (null, 'Clara de huevo',      '1 taza ~240 g',    52, 10.9,  0.7, 0.2, 0,    0.7, 'catalog'),
  -- Lácteos
  (null, 'Queso cottage',       '1/2 taza ~110 g', 98, 11.1,  3.4, 4.3, 0,    2.7, 'catalog'),
  (null, 'Queso oaxaca',        '1 porción ~30 g', 344, 25.0,  1.0, 26.0, 0,   1.0, 'catalog'),
  (null, 'Queso amarillo',      '1 rebanada ~20 g',337, 22.0,  4.0, 27.0, 0,   1.0, 'catalog'),
  (null, 'Yogur natural',       '1 taza ~200 g',    61,  3.5,  4.7, 3.3, 0,    4.7, 'catalog'),
  (null, 'Leche entera',        '1 taza ~240 g',    61,  3.2,  4.8, 3.3, 0,    5.1, 'catalog'),
  -- Legumbres y verdura
  (null, 'Garbanzo cocido',     '1 taza ~165 g',   164,  8.9, 27.4, 2.6, 7.6,  4.8, 'catalog'),
  (null, 'Edamame',             '1 taza ~155 g',   122, 11.9,  8.9, 5.2, 5.2,  2.2, 'catalog'),
  (null, 'Brócoli',             '1 taza ~90 g',     34,  2.8,  6.6, 0.4, 2.6,  1.7, 'catalog'),
  (null, 'Espinaca',            '1 taza ~30 g',     23,  2.9,  3.6, 0.4, 2.2,  0.4, 'catalog'),
  (null, 'Jitomate',            '1 pieza ~120 g',   18,  0.9,  3.9, 0.2, 1.2,  2.6, 'catalog'),
  (null, 'Zanahoria',           '1 pieza ~60 g',    41,  0.9,  9.6, 0.2, 2.8,  4.7, 'catalog'),
  (null, 'Pepino',              '1 pieza ~150 g',   15,  0.7,  3.6, 0.1, 0.5,  1.7, 'catalog'),
  (null, 'Lechuga',             '1 taza ~50 g',     15,  1.4,  2.9, 0.2, 1.3,  0.8, 'catalog'),
  (null, 'Calabacita',          '1 taza ~120 g',    17,  1.2,  3.1, 0.3, 1.0,  2.5, 'catalog'),
  (null, 'Elote',               '1 pieza ~150 g',   96,  3.4, 21.0, 1.5, 2.4,  4.5, 'catalog'),
  -- Grasas y frutos secos
  (null, 'Cacahuate',           '1 puño ~30 g',    567, 25.8, 16.1, 49.2, 8.5,  4.7, 'catalog'),
  (null, 'Nuez',                '1 puño ~30 g',    654, 15.2, 13.7, 65.2, 6.7,  2.6, 'catalog'),
  (null, 'Mantequilla de maní', '1 cda ~16 g',     588, 25.1, 20.0, 50.4, 6.0,  9.2, 'catalog'),
  (null, 'Chía',                '1 cda ~12 g',     486, 16.5, 42.1, 30.7, 34.4, 0,  'catalog'),
  (null, 'Linaza',              '1 cda ~10 g',     534, 18.3, 28.9, 42.2, 27.3, 1.6, 'catalog'),
  (null, 'Aceite de coco',      '1 cda ~14 g',     862,  0,    0,  100.0, 0,    0,  'catalog'),
  (null, 'Mantequilla',         '1 cda ~14 g',     717,  0.9,  0.1, 81.1, 0,    0.1, 'catalog'),
  -- Otros
  (null, 'Miel',                '1 cda ~21 g',     304,  0.3, 82.4, 0,    0.2, 82.1, 'catalog')
on conflict do nothing;
