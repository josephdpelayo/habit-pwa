// Adaptador puro: una actividad de Intervals.icu se normaliza al formato que ya entiende
// el importador de Strava y después se marca con su procedencia real. Solo aceptamos el
// origen Garmin Connect para no duplicar actividades que también hayan llegado por Strava.

'use strict';

const Strava = require('./skandi-strava.js');

const STRENGTH_TYPES = new Set(['weighttraining', 'strengthtraining', 'functionalstrengthtraining', 'crossfit']);

function isGarminActivity(activity) {
  return String(activity && activity.source || '').toUpperCase() === 'GARMIN_CONNECT';
}

function rpeOf(activity) {
  return activity.perceived_exertion || activity.icu_rpe || activity.session_rpe || null;
}

function strengthTypeOf(activity) {
  return String(activity && activity.type || '').replace(/[^a-z]/gi, '').toLowerCase();
}

function isStrengthActivity(activity) {
  return isGarminActivity(activity) && STRENGTH_TYPES.has(strengthTypeOf(activity));
}

function clampInt(value, min, max) {
  const number = Math.round(Number(value));
  return Number.isFinite(number) && number >= min && number <= max ? number : null;
}

function strengthMetrics(activity, { maxHeartRate } = {}) {
  if (!isStrengthActivity(activity) || !activity.id) return null;
  const startedAt = activity.start_date || activity.start_date_local;
  const startMs = new Date(startedAt).getTime();
  if (!Number.isFinite(startMs)) return null;
  // En fuerza los descansos entre series son parte del entrenamiento, por eso elapsed_time
  // tiene prioridad sobre moving_time (al revés que en carrera o ciclismo).
  const durationSec = Math.round(Number(activity.elapsed_time) || Number(activity.moving_time) || 0);
  if (durationSec < 1 || durationSec > 86400) return null;
  const effort = Strava.deriveIntensity({
    perceived_exertion: rpeOf(activity),
    average_heartrate: activity.average_heartrate,
  }, maxHeartRate || activity.athlete_max_hr || null);
  return {
    externalId: String(activity.id),
    startedAt: new Date(startMs).toISOString(),
    durationSec,
    avgHeartRate: clampInt(activity.average_heartrate, 30, 230),
    maxHeartRate: clampInt(activity.max_heartrate, 30, 230),
    calories: clampInt(activity.calories, 0, 20000),
    intensity: effort.intensity,
    intensitySource: effort.source,
    deviceName: String(activity.device_name || '').trim().slice(0, 120) || null,
    activityName: String(activity.name || '').trim().slice(0, 200) || null,
  };
}

// Devuelve parejas inequívocas actividad↔sesión. Una actividad ya enlazada conserva su
// sesión; para una nueva se exige solapamiento o inicios a <= 90 minutos. Cada sesión solo
// puede consumir una actividad Garmin.
function matchStrengthActivities(activities, sessions, { maxHeartRate } = {}) {
  const metrics = (activities || []).map(a => strengthMetrics(a, { maxHeartRate })).filter(Boolean);
  const available = (sessions || []).filter(s => s && s.id && s.completed_at);
  const used = new Set();
  const matches = [];
  const unmatched = [];

  for (const metric of metrics) {
    const already = available.find(s => String(s.garmin_external_id || '') === metric.externalId);
    if (already) {
      used.add(already.id);
      matches.push({ session: already, metric });
      continue;
    }
    const start = new Date(metric.startedAt).getTime();
    const end = start + metric.durationSec * 1000;
    let best = null;
    for (const session of available) {
      if (used.has(session.id) || session.garmin_external_id) continue;
      const sessionStart = new Date(session.started_at).getTime();
      const sessionEnd = new Date(session.completed_at).getTime();
      if (!Number.isFinite(sessionStart) || !Number.isFinite(sessionEnd)) continue;
      const overlap = Math.max(0, Math.min(end, sessionEnd) - Math.max(start, sessionStart));
      const startDelta = Math.abs(start - sessionStart);
      if (overlap < 10 * 60e3 && startDelta > 90 * 60e3) continue;
      const sessionDuration = Math.max(60e3, sessionEnd - sessionStart);
      const score = startDelta + Math.abs(metric.durationSec * 1000 - sessionDuration) * 0.35 - overlap * 0.5;
      if (!best || score < best.score) best = { session, score };
    }
    if (best) {
      used.add(best.session.id);
      matches.push({ session: best.session, metric });
    } else {
      // Un entrenamiento de fuerza del reloj sin sesión en Skandi no se enlaza a nada y
      // tampoco se importa como actividad (duplicaría la fatiga). Devolverlo, y no solo
      // contarlo, es lo que permite decir CUÁL falta en vez de dejar un hueco silencioso.
      unmatched.push(metric);
    }
  }
  return { matches, unmatched, strengthActivities: metrics.length };
}

function toActivityRow(activity, { userId, maxHeartRate } = {}) {
  if (!activity || !activity.id || !isGarminActivity(activity) || isStrengthActivity(activity)) return null;
  const start = activity.start_date || activity.start_date_local;
  if (!start || Number.isNaN(new Date(start).getTime())) return null;

  const normalized = {
    ...activity,
    start_date: start,
    sport_type: activity.type,
    perceived_exertion: rpeOf(activity),
  };
  const row = Strava.toActivityRow(normalized, {
    userId,
    maxHeartRate: maxHeartRate || activity.athlete_max_hr || null,
  });
  if (!row) return null;
  return {
    ...row,
    external_source: 'intervals',
    external_id: String(activity.id),
    external_type: String(activity.type || '').trim() || null,
  };
}

// ---- Bienestar diario ----
// Un renglón de /wellness es un DÍA, no una actividad: sueño, pulso en reposo, HRV, pasos y
// peso. Intervals devuelve el día completo aunque no haya nada medido, así que un renglón sin
// un solo dato útil se descarta en vez de escribir una fila vacía por cada día del año.

function num(value, min, max, decimals) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < min || n > max) return null;
  const f = Math.pow(10, decimals || 0);
  return Math.round(n * f) / f;
}

function toWellnessRow(entry, { userId } = {}) {
  const day = String(entry && entry.id || '').slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return null;
  const row = {
    user_id: userId,
    day,
    sleep_secs: num(entry.sleepSecs, 0, 86400),
    sleep_score: num(entry.sleepScore, 0, 100),
    sleep_quality: num(entry.sleepQuality, 1, 5),
    avg_sleeping_hr: num(entry.avgSleepingHR, 20, 150),
    resting_hr: num(entry.restingHR, 20, 150),
    hrv: num(entry.hrv, 0, 500, 1),
    steps: num(entry.steps, 0, 200000),
    readiness: num(entry.readiness, 0, 100),
    source: 'intervals',
    synced_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
  const measured = ['sleep_secs','sleep_score','sleep_quality','avg_sleeping_hr','resting_hr','hrv','steps','readiness']
    .some(key => row[key] !== null);
  return measured ? row : null;
}

// El peso sale aparte porque su casa es skandi_bodyweight_logs (migración 067), no la tabla
// de bienestar: ahí lo leen la tarjeta de peso, las metas de nutrición y progreso.
function toWeightRow(entry, { userId } = {}) {
  const day = String(entry && entry.id || '').slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return null;
  const weight = num(entry.weight, 20, 300, 2);
  if (weight === null) return null;
  return { user_id: userId, logged_at: day, weight_kg: weight, source: 'intervals' };
}

module.exports = {
  STRENGTH_TYPES, isGarminActivity, rpeOf, strengthTypeOf, isStrengthActivity,
  strengthMetrics, matchStrengthActivities, toActivityRow,
  toWellnessRow, toWeightRow,
};
