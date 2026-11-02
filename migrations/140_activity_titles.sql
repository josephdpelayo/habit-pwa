-- 140 · El nombre de un entreno, cambiado por quien lo hizo (Actividad, habit-activity.js)
--
-- Joseph: «poderle cambiar el nombre al entrenamiento de ese día». Lo que pide es el nombre de
-- ESE entreno —el que sale en Actividad y en su sticker—, no el de la rutina:
--
-- * Un entreno de la app se llama como su rutina (`coaching_schedule.board_name`, copiado al
--   estampar la semana). Cambiar ese campo renombraría la rutina de ese día a medias, y
--   `guard_member_schedule_update` ni siquiera lo deja cuando la rutina la puso el coach. Va
--   en una columna propia, `title`, que el guard no mira y nadie más escribe.
-- * Del reloj, el nombre es `skandi_external_activities.note`, y cada sincronización con
--   Intervals.icu o Strava lo vuelve a escribir (api/skandi.js actualiza la fila completa). El
--   nombre que uno le pone va aparte, en `custom_title`, que la importación no conoce.
--
-- Lo registrado a mano (`training_activities.title`) y las sesiones de Skandi
-- (`skandi_sessions.title`) ya tenían su nombre: se cambia ahí mismo.
--
-- Las dos columnas son de la persona: la RLS de cada tabla ya le deja actualizar sus filas.
-- Vacío no existe: borrar el nombre es volver a null, y entonces sale el de siempre.

alter table public.coaching_schedule add column if not exists title text;
alter table public.coaching_schedule drop constraint if exists coaching_schedule_title_check;
alter table public.coaching_schedule add constraint coaching_schedule_title_check
  check (title is null or char_length(btrim(title)) between 1 and 80);

alter table public.skandi_external_activities add column if not exists custom_title text;
alter table public.skandi_external_activities drop constraint if exists skandi_external_activities_custom_title_check;
alter table public.skandi_external_activities add constraint skandi_external_activities_custom_title_check
  check (custom_title is null or char_length(btrim(custom_title)) between 1 and 80);

comment on column public.coaching_schedule.title is
  'Nombre que la persona le puso a este entreno (Actividad). Null: el de la rutina, board_name.';
comment on column public.skandi_external_activities.custom_title is
  'Nombre que la persona le puso (HABIT · Actividad). La importación del reloj no lo toca; note sí.';
