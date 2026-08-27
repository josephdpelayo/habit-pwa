-- Un tap de "Es mi semana de descarga" (attentionBannerHtml / progressSummaryTab) crea un
-- skandi_training_blocks con build_weeks = 0: cero semanas de carga, solo la semana de
-- descarga en curso, sin pasar por el formulario que pide cuántas semanas de carga anteceden.
-- El check original (066) exigía build_weeks entre 1 y 8, lo que forzaba a fingir semanas de
-- carga que nunca ocurrieron para poder marcar una sola semana puntual como descarga.

alter table public.skandi_training_blocks drop constraint if exists skandi_training_blocks_build_weeks_check;
alter table public.skandi_training_blocks add constraint skandi_training_blocks_build_weeks_check
  check (build_weeks between 0 and 8);
