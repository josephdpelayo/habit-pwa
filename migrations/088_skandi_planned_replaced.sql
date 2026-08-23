-- Skandi Fit: separar "no lo hice" de "esto ya no va".
--
-- La 080 dejó un solo estado, 'skipped', haciendo dos trabajos distintos:
--
--   1. La lápida que evita que `skandi_ensure_week` vuelva a estampar una sesión que se quitó
--      del plan. Sin ella, borrar un día lo resucitaba al reabrir la semana.
--   2. El registro honesto de un día que estaba planeado y no se entrenó.
--
-- Son cosas distintas y se ven distinto. Un día que no hiciste merece aparecer tachado: es
-- información. Un día que reemplazaste al cambiar de programa no debería aparecer — nunca fue
-- tu plan para ese día. Al cargar la semana de descarga las seis rutinas del programa viejo
-- quedaron tachadas debajo de las nuevas, y el calendario mostraba dos planes encimados.
--
-- 'replaced' es la lápida sin la culpa: sigue impidiendo el re-estampado y desaparece de la
-- vista y de la adherencia.

alter table public.skandi_planned_sessions
  drop constraint if exists skandi_planned_sessions_status_check;

alter table public.skandi_planned_sessions
  add constraint skandi_planned_sessions_status_check
  check (status in ('planned','done','partial','skipped','moved','replaced'));

comment on column public.skandi_planned_sessions.status is
  'planned/done/partial = el ciclo normal. skipped = estaba planeado y no lo hiciste (se ve tachado). replaced = lo sacaste del plan al cambiarlo (invisible, pero impide que la plantilla lo vuelva a estampar). moved = se pasó a otro día.';

-- La semana de descarga (086) apagó el programa viejo con 'skipped' porque 'replaced' todavía
-- no existía. Eso es exactamente lo que hay que corregir: no es que no las hicieras, es que
-- las reemplazaste.
update public.skandi_planned_sessions
   set status = 'replaced'
 where day between date '2026-08-24' and date '2026-08-30'
   and status = 'skipped'
   and source = 'template'
   and session_id is null
   and activity_id is null;
