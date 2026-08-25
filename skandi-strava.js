// Skandi Fit — Strava: traducir una actividad de Strava a un renglón de
// `skandi_external_activities`. Sin DOM y sin Supabase, igual que skandi-recovery.js y
// skandi-nutrition.js: recibe el JSON de Strava, devuelve el objeto que se va a insertar.
//
// A diferencia de sus hermanos, este NO se carga en el navegador: la traducción solo ocurre
// del lado del servidor (api/skandi.js lo require). Se queda con la misma envoltura y la
// misma disciplina de módulo puro porque eso es lo que lo hace probable desde Node:
//
//   node -e "const S=require('./skandi-strava.js'); console.log(S.toActivityRow({...}, {userId:'x'}))"

(function(global){
'use strict';

const Recovery = (typeof module !== 'undefined' && module.exports)
  ? require('./skandi-recovery.js')
  : global.SkandiRecovery;

// ---- De los ~50 deportes de Strava a nuestros seis ----
// La reducción es con pérdida a propósito: `activity_type` existe para escoger el mapa
// muscular del motor de fatiga (SkandiRecovery.ACTIVITY_MUSCLE_MAP), y un TrailRun y un Run
// castigan las mismas piernas. Lo que se pierde al reducir se guarda crudo en
// `external_type`, así que ningún dato de Strava se tira.
const SPORT_TYPE_MAP = {
  Run: 'running', TrailRun: 'running', VirtualRun: 'running',

  Ride: 'cycling', GravelRide: 'cycling', MountainBikeRide: 'cycling',
  EBikeRide: 'cycling', EMountainBikeRide: 'cycling', VirtualRide: 'cycling',
  Handcycle: 'cycling', Velomobile: 'cycling',

  Swim: 'swimming',

  Rowing: 'rowing', VirtualRow: 'rowing',
  Kayaking: 'rowing', Canoeing: 'rowing', StandUpPaddling: 'rowing',

  Walk: 'walking', Hike: 'walking', Snowshoe: 'walking',

  // hiit/hyrox son tipos reales desde la 104 (docs/PLAN_ENTRENAMIENTO_SKANDI.md, fase T2): antes
  // caían en 'other' y le mentían a la figura muscular con el reparto genérico. 'Crossfit' se
  // queda fuera a propósito: sigue en SKIPPED_SPORT_TYPES más abajo, no se reclasifica aquí.
  HighIntensityIntervalTraining: 'hiit',
};

// Lo que NO se importa. No es que no cuente: es que Skandi ya lo cuenta mejor. Una sesión de
// fuerza vive en `skandi_sessions` con sus series, sus repeticiones y su RIR, y el motor de
// fatiga ya la consume. Importarla otra vez como "actividad externa" sumaría el mismo
// entrenamiento dos veces al mismo músculo, que es peor que no tenerlo.
const SKIPPED_SPORT_TYPES = new Set(['WeightTraining', 'Crossfit']);

const DEFAULT_INTENSITY = 5;

function sportTypeOf(activity){
  // sport_type es el campo nuevo; type es el viejo y sigue llegando en actividades antiguas.
  return String(activity.sport_type || activity.type || '').trim();
}

function isSkipped(activity){
  return SKIPPED_SPORT_TYPES.has(sportTypeOf(activity));
}

function mapActivityType(activity){
  return SPORT_TYPE_MAP[sportTypeOf(activity)] || 'other';
}

// El esfuerzo, en orden de qué tan directo es el dato:
//   1. perceived_exertion — el atleta lo tecleó en Strava. Nada le gana a eso.
//   2. %FCmáx — objetivo, comparable entre personas, es la ruta normal con reloj.
//   3. 5 y una marca de "revísalo" — nunca un número inventado que se vea como medido.
function deriveIntensity(activity, maxHeartRate, zoneBounds){
  const rpe = Number(activity.perceived_exertion);
  if (rpe >= 1 && rpe <= 10) {
    return { intensity: Math.round(rpe), source: 'manual' };
  }
  const fromHr = Recovery.heartRateIntensity(activity.average_heartrate, maxHeartRate, zoneBounds);
  if (fromHr !== null && fromHr !== undefined) {
    return { intensity: Math.round(fromHr), source: 'heart_rate' };
  }
  return { intensity: DEFAULT_INTENSITY, source: 'default' };
}

function round(n, decimals){
  const f = Math.pow(10, decimals);
  return Math.round(n * f) / f;
}

function clampInt(value, min, max){
  const n = Math.round(Number(value));
  if (!Number.isFinite(n) || n < min || n > max) return null;
  return n;
}

// Devuelve la fila lista para upsert, o null si la actividad no debe importarse.
// `maxHeartRate` es opcional: sin ella la intensidad cae a bandas absolutas de bpm.
function toActivityRow(activity, { userId, maxHeartRate, hrZones } = {}){
  if (!activity || !activity.id || isSkipped(activity)) return null;

  // moving_time y no elapsed_time: el semáforo en el que estuviste parado no fatiga nada.
  // Strava siempre manda los dos; en una actividad manual pueden venir iguales.
  const seconds = Number(activity.moving_time) || Number(activity.elapsed_time) || 0;
  const durationMin = Math.max(1, Math.min(1440, Math.round(seconds / 60)));

  const meters = Number(activity.distance) || 0;
  const distanceKm = meters > 0 ? Math.min(1000, round(meters / 1000, 2)) : null;

  const { intensity, source } = deriveIntensity(activity, maxHeartRate, hrZones);

  return {
    user_id: userId,
    activity_type: mapActivityType(activity),
    performed_at: new Date(activity.start_date).toISOString(),
    duration_min: durationMin,
    distance_km: distanceKm,
    avg_heart_rate: clampInt(activity.average_heartrate, 30, 230),
    max_heart_rate: clampInt(activity.max_heartrate, 30, 230),
    elevation_gain_m: Number(activity.total_elevation_gain) > 0
      ? Math.min(20000, round(Number(activity.total_elevation_gain), 1)) : null,
    calories: clampInt(activity.calories, 0, 20000),
    intensity,
    intensity_source: source,
    note: String(activity.name || '').trim().slice(0, 200) || null,
    external_source: 'strava',
    external_id: String(activity.id),
    external_type: sportTypeOf(activity) || null,
  };
}

// ---- Duplicados: la misma carrera capturada a mano y luego importada ----
//
// Esto no es de Strava, opera sobre filas de `skandi_external_activities` de cualquier
// origen. Vive aquí porque este módulo ya es el que traduce y compara esas filas, y abrir un
// quinto módulo para una sola función sería peor que la incomodidad del nombre.
//
// El caso real: registras la carrera del viernes en la app y al día siguiente el reloj la
// manda por Intervals. Son dos renglones del mismo entrenamiento y el motor de fatiga los
// suma dos veces. La solución NO es borrar el tuyo: puede traer una nota, el plan de cardio
// al que pertenece (`template_id`) y, sobre todo, puede estar enlazado a un día del
// calendario (`skandi_planned_sessions.activity_id`). Se absorbe: la fila tuya se queda con
// su id y recibe lo que el reloj midió mejor. Es la misma decisión que ya se tomó en fuerza,
// donde la actividad del reloj enriquece la sesión que tú registraste en vez de duplicarla.

const DUPLICATE_OVERLAP_MS = 10 * 60e3;
const DUPLICATE_START_MS = 90 * 60e3;

function activitySpan(row){
  const start = new Date(row.performed_at).getTime();
  const minutes = Number(row.duration_min) || 0;
  if (!Number.isFinite(start) || minutes <= 0) return null;
  return { start, end: start + minutes * 60e3, minutes };
}

// Dos entrenamientos del mismo tipo que empiezan cerca pero duran cosas muy distintas son
// dos entrenamientos, no uno mal capturado. Sin esta guarda, una sesión doble el mismo día
// se comería a la otra.
function similarDuration(a, b){
  const gap = Math.abs(a.minutes - b.minutes);
  return gap <= Math.max(15, Math.max(a.minutes, b.minutes) * 0.5);
}

function matchImportedToManual(rows){
  const imported = (rows || []).filter(r => r && r.external_source);
  const manual = (rows || []).filter(r => r && !r.external_source);
  const used = new Set();
  const pairs = [];

  for (const row of imported) {
    const span = activitySpan(row);
    if (!span) continue;
    let best = null;
    for (const candidate of manual) {
      if (used.has(candidate.id)) continue;
      if (candidate.activity_type !== row.activity_type) continue;
      const other = activitySpan(candidate);
      if (!other || !similarDuration(span, other)) continue;
      const overlap = Math.max(0, Math.min(span.end, other.end) - Math.max(span.start, other.start));
      const startDelta = Math.abs(span.start - other.start);
      if (overlap < DUPLICATE_OVERLAP_MS && startDelta > DUPLICATE_START_MS) continue;
      const score = startDelta - overlap;
      if (!best || score < best.score) best = { manual: candidate, score };
    }
    if (best) {
      used.add(best.manual.id);
      pairs.push({ imported: row, manual: best.manual });
    }
  }
  return pairs;
}

const api = {
  SPORT_TYPE_MAP, SKIPPED_SPORT_TYPES, DEFAULT_INTENSITY,
  sportTypeOf, isSkipped, mapActivityType, deriveIntensity, toActivityRow,
  matchImportedToManual,
};

if (typeof module !== 'undefined' && module.exports) module.exports = api;
else global.SkandiStrava = api;

})(typeof window !== 'undefined' ? window : globalThis);
