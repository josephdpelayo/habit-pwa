-- Skandi Fit: parciales por km de Strava — la columna que la 104 dejó a propósito sin dueño.
--
-- La 104 (docs/PLAN_ENTRENAMIENTO_SKANDI.md, fase T2) trajo `splits jsonb` al documento de
-- planeación pero no a la base: sin un importador que la llenara, hubiera sido una columna
-- muerta. Este es ese importador.
--
-- Por qué no llega en el jalón masivo (`strava-sync`, backfill de hasta 365 días): Strava solo
-- manda `splits_metric` en el endpoint de UNA actividad (`GET /activities/{id}`), no en la lista
-- (`GET /athlete/activities`) que usa el backfill. Pedirle el detalle a cada actividad del
-- backfill sería N llamadas extra por sincronización — con el límite de Strava (100 req/15min en
-- una app sin aprobar) un historial de 200 carreras agotaría la cuota solo por los splits de una
-- sincronización. El webhook (una actividad a la vez) YA pide ese detalle para todo lo demás, así
-- que ahí los splits llegan gratis. Para lo ya importado sin webhook, `api/skandi.js` gana la
-- acción `strava-splits`: un miembro pide los parciales de UNA actividad al abrir su detalle, no
-- de todo su historial de una vez — el mismo principio de "se lee completo, nunca se consulta la
-- historia entera" que ya rige `skandi_planned_sessions.structure`.

alter table public.skandi_external_activities
  add column if not exists splits jsonb;

comment on column public.skandi_external_activities.splits is
  'Parciales por km de Strava: [{km, sec, elev_m, hr}, ...]. Null hasta que el webhook lo trae solo o alguien pide "ver parciales" en el detalle de la actividad (api/skandi.js, acción strava-splits). No existe para actividades manuales ni de Intervals.';
