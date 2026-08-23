-- Skandi Fit: suplementos + catálogo semilla de alimentos.
--
-- Dos features chicas, una migración porque ninguna necesita las 12 líneas de una propia.

-- ── 1. Suplementos ───────────────────────────────────────────────────────────
--
-- Lo que un miembro toma (creatina, omega-3, magnesio...) y si lo tomó hoy. Es un check-off
-- diario, no un diario de dosis reales: `dose`/`unit`/`timing` describen el plan de la persona
-- ("5 g", "diario", "en la noche"), no lo que efectivamente se tomó cada vez — eso lo dice el
-- propio checkbox marcado ese día.

create table if not exists public.skandi_supplements (
  id         uuid primary key default uuid_generate_v4(),
  user_id    uuid references public.profiles(id) on delete cascade not null,
  name       text not null,
  dose       text,
  timing     text,
  active     boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_skandi_supplements_user
  on public.skandi_supplements(user_id, sort_order);

create table if not exists public.skandi_supplement_logs (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid references public.profiles(id) on delete cascade not null,
  supplement_id uuid references public.skandi_supplements(id) on delete cascade not null,
  taken_on      date not null default current_date,
  created_at    timestamptz not null default now(),
  unique(supplement_id, taken_on)
);

create index if not exists idx_skandi_supplement_logs_user_date
  on public.skandi_supplement_logs(user_id, taken_on desc);

alter table public.skandi_supplements enable row level security;
alter table public.skandi_supplement_logs enable row level security;

drop policy if exists "Skandi manage own supplements" on public.skandi_supplements;
create policy "Skandi manage own supplements"
  on public.skandi_supplements for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Skandi manage own supplement logs" on public.skandi_supplement_logs;
create policy "Skandi manage own supplement logs"
  on public.skandi_supplement_logs for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── 2. Catálogo semilla de alimentos ─────────────────────────────────────────
--
-- `skandi_foods.user_id is null` ya es, desde la 073, el mecanismo pensado para esto ("alimento
-- global"): visible para cualquier tripulante vía la política de SELECT, sin necesitar el
-- user_id de nadie. Veinte básicos genéricos (valores nutricionales de referencia, no una dieta
-- de nadie en particular) para que el catálogo no arranque vacío para ningún miembro nuevo — el
-- escalón "platillo guardado -> catálogo -> IA" de la 076 necesita algo en el catálogo para
-- poder empezar ahí.

insert into public.skandi_foods
  (user_id, name, serving_label, kcal_100g, protein_100g, carbs_100g, fat_100g, fiber_100g, source)
values
  (null, 'Pechuga de pollo', '1 pieza ~150 g', 165, 31,   0,    3.6,  0,    'catalog'),
  (null, 'Pechuga de pavo',  '1 pieza ~150 g', 135, 30,   0,    1,    0,    'catalog'),
  (null, 'Atún en agua',     '1 lata ~140 g',  116, 26,   0,    0.8,  0,    'catalog'),
  (null, 'Salmón',           '1 filete ~150 g',208, 20,   0,    13,   0,    'catalog'),
  (null, 'Huevo entero',     '1 pieza ~50 g',  155, 13,   1.1,  11,   0,    'catalog'),
  (null, 'Queso panela',     '1 rebanada ~30 g',250,18,   3,    19,   0,    'catalog'),
  (null, 'Yogur griego natural','1 taza ~200 g',59, 10,   3.6,  0.4,  0,    'catalog'),
  (null, 'Leche descremada', '1 taza ~240 g',  34,  3.4,  5,    0.1,  0,    'catalog'),
  (null, 'Proteína de suero (whey)','1 scoop ~30 g',400,80,8,   6.7,  0,    'catalog'),
  (null, 'Arroz blanco cocido','1 taza ~180 g',130, 2.7,  28,   0.3,  0.4,  'catalog'),
  (null, 'Avena',            '1/2 taza ~40 g', 389, 16.9, 66,   6.9,  10.6, 'catalog'),
  (null, 'Camote cocido',    '1 pieza ~150 g', 90,  2,    21,   0.1,  3.3,  'catalog'),
  (null, 'Pasta cocida',     '1 taza ~140 g',  131, 5,    25,   1.1,  1.8,  'catalog'),
  (null, 'Tortilla de maíz', '1 pieza ~25 g',  218, 5.7,  44.6, 2.3,  6.3,  'catalog'),
  (null, 'Frijol negro cocido','1 taza ~170 g',132, 8.9,  23.7, 0.5,  8.7,  'catalog'),
  (null, 'Lentejas cocidas', '1 taza ~200 g',  116, 9,    20,   0.4,  7.9,  'catalog'),
  (null, 'Plátano',          '1 pieza ~120 g', 89,  1.1,  22.8, 0.3,  2.6,  'catalog'),
  (null, 'Aguacate',         '1/2 pieza ~100 g',160,2,    8.5,  14.7, 6.7,  'catalog'),
  (null, 'Almendras',        '1 puño ~30 g',   579, 21,   22,   50,   12.5, 'catalog'),
  (null, 'Aceite de oliva',  '1 cda ~14 g',    884, 0,    0,    100,  0,    'catalog')
on conflict do nothing;
