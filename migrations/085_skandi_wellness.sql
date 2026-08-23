-- Skandi Fit: el día completo, no solo el entrenamiento.
--
-- El reloj ya mide lo que decide si un entrenamiento va a salir bien —cuánto dormiste, cómo
-- amaneció tu pulso en reposo, tu HRV, cuánto te moviste— y todo eso viaja a Intervals.icu
-- junto con las actividades. Sin ese dato, cualquier recomendación de la app es ciega en la
-- mitad que más manda: dos personas con la misma carga de la semana pero una durmiendo 5 h y
-- otra 8 h no deben entrenar igual, y hoy la app no puede notar la diferencia.
--
-- Esto es lo que la Fase 2 de docs/PROYECTO_SKANDI_V2.md pedía como `skandi_daily_checkin`
-- (migración 077, nunca escrita) y lo reemplaza: una sola tabla por día, venga del reloj o
-- capturada a mano. Tener dos —una para lo medido y otra para lo tecleado— obligaría a
-- resolver el empate en cada consulta.

create table if not exists public.skandi_daily_wellness (
  user_id          uuid references public.profiles(id) on delete cascade not null,
  day              date not null,

  -- Sueño. sleep_secs es lo que el reloj midió dormido; sleep_score es la calificación de
  -- Garmin (0-100) y sleep_quality la escala 1-4 de Intervals. Se guardan los tres porque no
  -- son el mismo dato: se puede dormir 8 h con una calificación pésima.
  sleep_secs       integer check (sleep_secs is null or sleep_secs between 0 and 86400),
  sleep_score      integer check (sleep_score is null or sleep_score between 0 and 100),
  sleep_quality    integer check (sleep_quality is null or sleep_quality between 1 and 5),
  avg_sleeping_hr  integer check (avg_sleeping_hr is null or avg_sleeping_hr between 20 and 150),

  -- Mañana. El pulso en reposo y la HRV son los dos indicadores que se mueven ANTES de que te
  -- sientas mal, que es justo lo que los hace útiles.
  resting_hr       integer check (resting_hr is null or resting_hr between 20 and 150),
  hrv              numeric(5,1) check (hrv is null or hrv between 0 and 500),

  -- Movimiento del día. Contexto, NO estímulo: los pasos no entran al motor de fatiga. Los
  -- pasos de una carrera ya están contados como carrera, y sumarlos otra vez fatigaría dos
  -- veces las mismas piernas. Sirven para leer un día sedentario contra uno de pie 12 horas.
  steps            integer check (steps is null or steps between 0 and 200000),

  -- La "readiness" que calcula Intervals con sus propios criterios. Se guarda como referencia
  -- externa; el readiness de Skandi (fase T4) se calcula aquí y no se hereda.
  readiness        integer check (readiness is null or readiness between 0 and 100),

  source           text not null default 'intervals' check (source in ('intervals','manual')),
  synced_at        timestamptz,
  updated_at       timestamptz not null default now(),
  primary key (user_id, day)
);

create index if not exists idx_skandi_daily_wellness_user_day
  on public.skandi_daily_wellness(user_id, day desc);

alter table public.skandi_daily_wellness enable row level security;

drop policy if exists "Crew manage own skandi wellness" on public.skandi_daily_wellness;
create policy "Crew manage own skandi wellness"
  on public.skandi_daily_wellness for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ── El peso NO vive aquí ────────────────────────────────────────────────────
-- Intervals también manda el peso, pero ese dato ya tiene casa desde la 067, y la tarjeta de
-- peso, las metas de nutrición (Mifflin-St Jeor usa el peso más reciente) y la pantalla de
-- progreso leen de ahí. Guardarlo en dos tablas obligaría a decidir cuál gana en cada
-- consulta. Se importa a `skandi_bodyweight_logs` y lo único que falta es poder distinguir un
-- pesaje tecleado de uno sincronizado, para que el importador nunca pise el primero.

alter table public.skandi_bodyweight_logs
  add column if not exists source text not null default 'manual'
    check (source in ('manual','intervals'));

comment on column public.skandi_bodyweight_logs.source is
  'manual = lo tecleó la persona y el importador jamás lo pisa; intervals = vino de la báscula vía Intervals.icu';
