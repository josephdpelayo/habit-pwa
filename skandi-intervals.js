// Adaptador puro: una actividad de Intervals.icu se normaliza al formato que ya entiende
// el importador de Strava y después se marca con su procedencia real. Solo aceptamos el
// origen Garmin Connect para no duplicar actividades que también hayan llegado por Strava.

'use strict';

const Strava = require('./skandi-strava.js');

function isGarminActivity(activity) {
  return String(activity && activity.source || '').toUpperCase() === 'GARMIN_CONNECT';
}

function rpeOf(activity) {
  return activity.perceived_exertion || activity.icu_rpe || activity.session_rpe || null;
}

function toActivityRow(activity, { userId, maxHeartRate } = {}) {
  if (!activity || !activity.id || !isGarminActivity(activity)) return null;
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

module.exports = { isGarminActivity, rpeOf, toActivityRow };
