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
function deriveIntensity(activity, maxHeartRate){
  const rpe = Number(activity.perceived_exertion);
  if (rpe >= 1 && rpe <= 10) {
    return { intensity: Math.round(rpe), source: 'manual' };
  }
  const fromHr = Recovery.heartRateIntensity(activity.average_heartrate, maxHeartRate);
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
function toActivityRow(activity, { userId, maxHeartRate } = {}){
  if (!activity || !activity.id || isSkipped(activity)) return null;

  // moving_time y no elapsed_time: el semáforo en el que estuviste parado no fatiga nada.
  // Strava siempre manda los dos; en una actividad manual pueden venir iguales.
  const seconds = Number(activity.moving_time) || Number(activity.elapsed_time) || 0;
  const durationMin = Math.max(1, Math.min(1440, Math.round(seconds / 60)));

  const meters = Number(activity.distance) || 0;
  const distanceKm = meters > 0 ? Math.min(1000, round(meters / 1000, 2)) : null;

  const { intensity, source } = deriveIntensity(activity, maxHeartRate);

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

const api = {
  SPORT_TYPE_MAP, SKIPPED_SPORT_TYPES, DEFAULT_INTENSITY,
  sportTypeOf, isSkipped, mapActivityType, deriveIntensity, toActivityRow,
};

if (typeof module !== 'undefined' && module.exports) module.exports = api;
else global.SkandiStrava = api;

})(typeof window !== 'undefined' ? window : globalThis);
