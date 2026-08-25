-- Skandi Fit: enlazar la semana de descarga al programa que la generó.
--
-- skandi_training_blocks (066, N semanas de carga + 1 de descarga) y skandi_programs (069,
-- foto fija de una semana) nunca se tocaron entre sí: cargar un programa re-estampaba la
-- semana, pero no decía cuántas semanas iba a durar ni cuándo llegaba la descarga, y la
-- tarjeta de "semana de descarga" no decía de qué programa venía.
--
-- program_id es nullable a propósito: un bloque suelto (sin programa detrás, como los que ya
-- existen) sigue siendo válido. skandi_training_blocks sigue siendo "la fila con el
-- start_date más reciente gana" -- esto solo le agrega de dónde salió, no cambia ese diseño.

alter table public.skandi_training_blocks
  add column if not exists program_id uuid references public.skandi_programs(id) on delete set null;
