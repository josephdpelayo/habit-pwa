-- Skandi Fit: notas de dieta por miembro, para que "¿Qué como?" (meal-suggestion, api/skandi.js)
-- se base en el plan real de CADA quien en vez de un genérico de comida mexicana de casa.
--
-- Por qué un campo de texto libre y no una estructura: el plan de un coach (comidas por
-- horario, reglas de timing, "tu mano es la medida") no encaja en columnas tipadas sin perder
-- justo lo que lo hace útil — el criterio en prosa. Es opcional (null = seguir con el genérico
-- de siempre) y es DEL MIEMBRO, no del código: nadie hardcodea el plan de una persona en el
-- prompt compartido de api/skandi.js (ver el comentario de skandi_dishes en la migración 093
-- sobre por qué un plan de coach no es contenido para el código fuente). Cada quien pega el
-- suyo en Ajustes → Meta de nutrición, o no pone nada.

alter table public.skandi_nutrition_targets
  add column if not exists diet_notes text check (diet_notes is null or char_length(diet_notes) <= 4000);
