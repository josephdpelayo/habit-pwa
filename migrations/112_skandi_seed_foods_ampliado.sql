-- Skandi Fit: catálogo de alimentos, segunda pasada — mucho más amplio.
--
-- La 093 sembró 20 básicos, la 111 sumó ~48 más (fruta, pan, proteína, alacena). Esta agrega
-- el resto de lo que aparece a diario en una cocina mexicana normal y no estaba cubierto:
-- huevo en sus preparaciones más comunes, más quesos, más leches, más cortes de carne, más
-- verdura y guarniciones, y los básicos de alacena seca (azúcar, café, mermelada) que hacen
-- falta para registrar un desayuno completo sin tocar la IA. Mismo mecanismo de siempre
-- (`user_id is null` = global, visible a todo el crew) y mismos valores de referencia
-- (USDA / bases públicas), no la dieta de nadie en particular.

insert into public.skandi_foods
  (user_id, name, serving_label, kcal_100g, protein_100g, carbs_100g, fat_100g, fiber_100g,
   sugar_100g, added_sugar_100g, source)
values
  -- Huevo, más preparaciones
  (null, 'Huevo cocido',        '1 pieza ~50 g',   155, 12.6,  1.1, 10.6, 0,    1.1, 0,   'catalog'),
  (null, 'Huevo frito',         '1 pieza ~50 g',   196, 13.6,  0.8, 15.2, 0,    0.8, 0,   'catalog'),
  (null, 'Huevo revuelto',      '2 piezas ~110 g', 149, 10.0,  1.6, 11.0, 0,    1.1, 0,   'catalog'),
  -- Quesos
  (null, 'Queso manchego',      '1 porción ~30 g', 380, 25.0,  1.0, 30.0, 0,    0.5, 0,   'catalog'),
  (null, 'Queso mozzarella',    '1 porción ~30 g', 300, 22.0,  2.2, 22.0, 0,    1.0, 0,   'catalog'),
  (null, 'Queso crema',         '2 cdas ~30 g',    342,  6.2,  4.1, 34.0, 0,    3.2, 0,   'catalog'),
  (null, 'Queso Chihuahua',     '1 porción ~30 g', 356, 24.0,  2.4, 28.8, 0,    1.0, 0,   'catalog'),
  (null, 'Requesón',            '1/2 taza ~110 g', 138, 11.4,  5.1,  7.9, 0,    0.3, 0,   'catalog'),
  (null, 'Queso fresco',        '1 porción ~30 g', 264, 18.0,  3.2, 20.0, 0,    2.5, 0,   'catalog'),
  (null, 'Queso parmesano',     '2 cdas ~15 g',    431, 38.0,  4.1, 29.0, 0,    0.9, 0,   'catalog'),
  -- Leches y bebidas vegetales
  (null, 'Leche de almendra',   '1 taza ~240 g',    17,  0.6,  1.5,  1.1, 0.4,  1.0, 0,   'catalog'),
  (null, 'Leche de coco (bebida)','1 taza ~240 g',   45,  0.5,  4.0,  3.0, 0.2,  3.0, 0,   'catalog'),
  (null, 'Leche de soya',       '1 taza ~240 g',     33,  3.3,  1.8,  1.8, 0.6,  1.0, 0,   'catalog'),
  (null, 'Leche evaporada',     '1/4 taza ~60 g',   134,  6.8, 10.0,  7.6, 0,   10.0, 0,   'catalog'),
  (null, 'Leche condensada',    '1 cda ~20 g',      321,  7.9, 54.4,  8.7, 0,   54.0, 42.0,'catalog'),
  (null, 'Leche semidescremada','1 taza ~240 g',     50,  3.4,  4.9,  2.0, 0,    5.1, 0,   'catalog'),
  (null, 'Leche deslactosada',  '1 taza ~240 g',     46,  3.4,  5.0,  1.6, 0,    5.1, 0,   'catalog'),
  -- Más carne, pescado y embutidos
  (null, 'Chuleta de cerdo',    '1 pieza ~150 g',  231, 25.0,  0,   14.0, 0,    0,   0,   'catalog'),
  (null, 'Lomo de cerdo',       '1 pieza ~150 g',  143, 26.0,  0,    3.5, 0,    0,   0,   'catalog'),
  (null, 'Pollo rostizado (con piel)','1 pieza ~150 g',239,27.0, 0,   14.0, 0,   0,   0,   'catalog'),
  (null, 'Salmón ahumado',      '1 porción ~80 g', 117, 18.3,  0,    4.3, 0,    0,   0,   'catalog'),
  (null, 'Pulpo cocido',        '1 taza ~140 g',    82, 14.9,  2.2,  1.0, 0,    0,   0,   'catalog'),
  (null, 'Chorizo',             '1 pieza ~50 g',   455, 24.0,  1.9, 38.0, 0,    0,   0,   'catalog'),
  (null, 'Tocino',              '2 rebanadas ~16 g',541, 37.0,  1.4, 42.0, 0,    0,   0,   'catalog'),
  (null, 'Salchicha',           '1 pieza ~50 g',   301, 11.0,  3.0, 27.0, 0,    1.0, 0,   'catalog'),
  (null, 'Jamón de pierna',     '2 rebanadas ~50 g',145, 21.0,  1.5,  5.5, 0,    1.0, 0,   'catalog'),
  (null, 'Pavo molido',         '1 taza ~140 g',   149, 18.7,  0,    8.0, 0,    0,   0,   'catalog'),
  (null, 'Costilla de res',     '1 pieza ~150 g',  291, 24.0,  0,   21.0, 0,    0,   0,   'catalog'),
  (null, 'Cecina',              '1 porción ~80 g', 250, 34.0,  0,   12.0, 0,    0,   0,   'catalog'),
  -- Más carbohidratos
  (null, 'Arroz integral cocido','1 taza ~195 g',  123,  2.7, 25.8,  1.0, 1.6,  0.4, 0,   'catalog'),
  (null, 'Quinoa cocida',       '1 taza ~185 g',   120,  4.4, 21.3,  1.9, 2.8,  0.9, 0,   'catalog'),
  (null, 'Papa cocida',         '1 pieza ~150 g',   87,  1.9, 20.1,  0.1, 1.8,  0.9, 0,   'catalog'),
  (null, 'Puré de papa',        '1 taza ~210 g',   113,  2.0, 17.0,  4.2, 1.5,  1.0, 0,   'catalog'),
  (null, 'Betabel cocido',      '1 taza ~170 g',    44,  1.7, 10.0,  0.2, 2.0,  7.0, 0,   'catalog'),
  (null, 'Nopales',             '1 taza ~86 g',     16,  1.3,  3.3,  0.1, 2.2,  1.5, 0,   'catalog'),
  (null, 'Cuscús cocido',       '1 taza ~157 g',   112,  3.8, 23.2,  0.2, 1.4,  0.1, 0,   'catalog'),
  (null, 'Pan árabe (pita)',    '1 pieza ~60 g',   275,  9.1, 55.7,  1.2, 2.2,  1.6, 0,   'catalog'),
  (null, 'Galletas Marías',     '4 piezas ~28 g',  440,  7.5, 75.0, 12.0, 2.0, 20.0, 18.0,'catalog'),
  (null, 'Amaranto',            '1/4 taza ~40 g',  371, 13.6, 65.2,  7.0, 6.7,  1.7, 0,   'catalog'),
  -- Más fruta
  (null, 'Toronja',             '1/2 pieza ~120 g', 42,  0.8, 10.7,  0.1, 1.6,  6.9, 0,   'catalog'),
  (null, 'Durazno',             '1 pieza ~150 g',   39,  0.9,  9.5,  0.3, 1.5,  8.4, 0,   'catalog'),
  (null, 'Ciruela',             '2 piezas ~130 g',  46,  0.7, 11.4,  0.3, 1.4,  9.9, 0,   'catalog'),
  (null, 'Guayaba',             '1 pieza ~90 g',    68,  2.6, 14.3,  1.0, 5.4,  8.9, 0,   'catalog'),
  (null, 'Melón',               '1 taza ~160 g',    34,  0.8,  8.2,  0.2, 0.9,  7.9, 0,   'catalog'),
  (null, 'Zarzamora',           '1 taza ~145 g',    43,  1.4,  9.6,  0.5, 5.3,  4.9, 0,   'catalog'),
  (null, 'Cereza',              '1 taza ~150 g',    63,  1.1, 16.0,  0.2, 2.1, 12.8, 0,   'catalog'),
  (null, 'Coco (pulpa)',        '1/4 taza ~20 g',  354,  3.3, 15.2, 33.5, 9.0,  6.2, 0,   'catalog'),
  (null, 'Chabacano',           '3 piezas ~105 g',  48,  1.4, 11.1,  0.4, 2.0,  9.2, 0,   'catalog'),
  -- Más verdura
  (null, 'Champiñones',         '1 taza ~70 g',     22,  3.1,  3.3,  0.3, 1.0,  2.0, 0,   'catalog'),
  (null, 'Coliflor',            '1 taza ~100 g',    25,  1.9,  5.0,  0.3, 2.0,  1.9, 0,   'catalog'),
  (null, 'Apio',                '1 taza ~100 g',    16,  0.7,  3.0,  0.2, 1.6,  1.3, 0,   'catalog'),
  (null, 'Rábano',              '1 taza ~115 g',    16,  0.7,  3.4,  0.1, 1.6,  1.9, 0,   'catalog'),
  (null, 'Chayote',             '1 taza ~130 g',    19,  0.8,  4.5,  0.1, 1.7,  1.7, 0,   'catalog'),
  (null, 'Ejotes',              '1 taza ~100 g',    31,  1.8,  7.0,  0.2, 3.4,  3.3, 0,   'catalog'),
  (null, 'Pimiento morrón',     '1 pieza ~120 g',   31,  1.0,  6.0,  0.3, 2.1,  4.2, 0,   'catalog'),
  (null, 'Cebolla',             '1 pieza ~110 g',   40,  1.1,  9.3,  0.1, 1.7,  4.2, 0,   'catalog'),
  (null, 'Col',                 '1 taza ~90 g',     25,  1.3,  5.8,  0.1, 2.5,  3.2, 0,   'catalog'),
  (null, 'Acelga',              '1 taza ~36 g',     19,  1.8,  3.7,  0.2, 1.6,  1.1, 0,   'catalog'),
  -- Más leguminosas
  (null, 'Habas cocidas',       '1 taza ~170 g',   110,  7.6, 19.7,  0.4, 5.4,  1.8, 0,   'catalog'),
  (null, 'Frijol pinto cocido', '1 taza ~170 g',   143,  9.0, 26.2,  0.6, 9.0,  0.3, 0,   'catalog'),
  -- Más grasas, nueces y semillas
  (null, 'Nuez de la india',    '1 puño ~30 g',    553, 18.2, 30.2, 43.9, 3.3,  5.9, 0,   'catalog'),
  (null, 'Pistache',            '1 puño ~30 g',    560, 20.6, 27.2, 45.3, 10.6, 7.7, 0,   'catalog'),
  (null, 'Semillas de girasol', '1 puño ~30 g',    584, 20.8, 20.0, 51.5, 8.6,  2.6, 0,   'catalog'),
  (null, 'Pepitas (semilla de calabaza)','1 puño ~30 g',559,30.2,10.7, 49.0, 6.0,  1.4, 0,   'catalog'),
  (null, 'Aceite de canola',    '1 cda ~14 g',     884,  0,    0,  100.0, 0,    0,   0,   'catalog'),
  (null, 'Aceite de aguacate',  '1 cda ~14 g',     884,  0,    0,  100.0, 0,    0,   0,   'catalog'),
  (null, 'Mayonesa',            '1 cda ~14 g',     680,  1.0,  0.6, 75.0, 0,    0.6, 0,   'catalog'),
  (null, 'Crema (mexicana)',    '2 cdas ~30 g',    293,  2.2,  4.3, 30.0, 0,    4.3, 0,   'catalog'),
  -- Alacena seca y bebidas comunes
  (null, 'Azúcar',              '1 cda ~12 g',     387,  0,  100.0,  0,   0,  100.0, 100.0,'catalog'),
  (null, 'Mermelada',           '1 cda ~20 g',     250,  0.4, 65.0,  0.1, 1.0, 60.0, 55.0,'catalog'),
  (null, 'Cacao en polvo',      '1 cda ~7 g',      228, 19.6, 57.9, 13.7,33.2,  1.8,  0,   'catalog'),
  (null, 'Chocolate amargo (70%+)','30 g',         546,  7.8, 45.9, 31.3,10.9, 24.0, 20.0,'catalog'),
  (null, 'Café negro',          '1 taza ~240 g',     1,  0.1,  0,    0,   0,    0,   0,   'catalog'),
  (null, 'Jugo de naranja',     '1 taza ~240 g',    45,  0.7, 10.4,  0.2, 0.2,  8.4,  0,   'catalog'),
  (null, 'Refresco de cola',    '1 lata ~355 g',    41,  0,   10.6,  0,   0,   10.6, 10.6,'catalog'),
  (null, 'Cerveza',             '1 lata ~355 g',    43,  0.5,  3.6,  0,   0,    0,   0,   'catalog'),
  (null, 'Vino tinto',          '1 copa ~150 g',    85,  0.1,  2.6,  0,   0,    0.6, 0,   'catalog')
on conflict do nothing;
