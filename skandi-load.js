// Skandi Fit — carga de entrenamiento. Matemáticas puras: sin DOM y sin Supabase, recibe
// filas y devuelve números, igual que skandi-recovery.js y skandi-nutrition.js.
//
// Contesta tres preguntas que la app tenía los datos para responder y no respondía:
//   1. ¿Cuánta carga llevo esta semana comparada con las anteriores?
//   2. ¿La estoy subiendo demasiado rápido?
//   3. ¿Esta semana de descarga de verdad está descargando?
//
// La moneda es el sRPE de Foster: minutos × esfuerzo (1-10). Se eligió sobre TSS o TRIMP
// porque no necesita potenciómetro ni banda de pecho, está validada en deporte real, y —lo
// que aquí importa más— significa lo mismo en fuerza, en carrera y en un HIIT. Sin una unidad
// común no se pueden sumar, y sin sumarlas no hay forma de saber cuánto entrenas.
//
// Ojo con lo que NO es: esto mide carga sistémica, no daño muscular. Esa otra pregunta la
// contesta skandi-recovery.js con sus unidades de estímulo por músculo. Dos preguntas, dos
// métricas; mezclarlas fue el error que este módulo evita.

(function(global){
'use strict';

const Recovery = (typeof module !== 'undefined' && module.exports)
  ? require('./skandi-recovery.js')
  : global.SkandiRecovery;

const ACUTE_DAYS = 7;
const CHRONIC_DAYS = 28;
// Los umbrales clásicos de Gabbett: debajo de 0.8 la carga aguda va tan por debajo de la
// crónica que se pierde adaptación; arriba de 1.5 el salto es el que se asocia a lesión.
const ACWR_LOW = 0.8;
const ACWR_HIGH = 1.5;
// Una descarga de verdad baja el volumen 30-40%. Por debajo de -25% respecto al promedio
// reciente cuenta como descarga; si no, es una semana normal con menos ganas.
const DELOAD_DROP = 0.25;

const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
const mean = list => list.length ? list.reduce((a, b) => a + b, 0) / list.length : null;

// Fecha local en YYYY-MM-DD. Local y no UTC: en Mazatlán (UTC-7) todo lo entrenado después de
// las 5 de la tarde caería al día siguiente.
function localDay(value){
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

// El esfuerzo de una sesión de fuerza. El RIR que registraste serie a serie es el mejor dato:
// RIR 2 es un 8 de 10. Sin RIR se cae a cómo la calificaste al terminar.
function strengthRpe(session, sets){
  const rirs = (sets || []).filter(s => s.done && s.rir != null).map(s => Number(s.rir))
    .filter(Number.isFinite);
  const avg = mean(rirs);
  if (avg !== null) return clamp(10 - avg, 4, 10);
  const d = session && session.report_difficulty;
  return d === 'facil' ? 5 : d === 'pesado' ? 9 : 7;
}

function sessionLoad(session, sets){
  const minutes = (Number(session && session.duration_sec) || 0) / 60;
  if (minutes <= 0) return 0;
  return Math.round(minutes * strengthRpe(session, sets));
}

// Misma precedencia que el motor de fatiga —lo declarado gana, si no manda el pulso, y el 5 de
// relleno es el último recurso— porque las dos pantallas tienen que contar la misma historia.
function activityLoad(activity, refs){
  const minutes = Number(activity && activity.duration_min) || 0;
  if (minutes <= 0) return 0;
  const declared = activity.intensity_source === 'manual' ? Number(activity.intensity) : NaN;
  const rpe = (declared >= 1 && declared <= 10)
    ? declared
    : (Recovery.heartRateIntensity(activity.avg_heart_rate, refs && refs.maxHeartRate, refs && refs.hrZones)
       ?? (Number(activity.intensity) || 5));
  return Math.round(minutes * rpe);
}

// Carga por día, del más viejo al más nuevo, sin huecos: un día sin entrenar vale 0 y tiene
// que existir en la serie, porque los promedios de 7 y 28 días se calculan sobre días
// calendario. Saltárselos inflaría la carga de quien entrena poco.
function dailySeries(opts){
  const { sessions = [], sets = [], activities = [], userId, refs, days = CHRONIC_DAYS, now = Date.now() } = opts || {};
  const setsBySession = new Map();
  sets.forEach(s => {
    if (!setsBySession.has(s.session_id)) setsBySession.set(s.session_id, []);
    setsBySession.get(s.session_id).push(s);
  });

  const byDay = new Map();
  const add = (day, kind, load) => {
    if (!day || !load) return;
    if (!byDay.has(day)) byDay.set(day, { day, load: 0, strength: 0, endurance: 0 });
    const row = byDay.get(day);
    row.load += load;
    row[kind] += load;
  };

  sessions.filter(s => s.completed_at && (!userId || s.user_id === userId)).forEach(s => {
    add(localDay(s.completed_at), 'strength', sessionLoad(s, setsBySession.get(s.id) || []));
  });
  activities.filter(a => !userId || a.user_id === userId).forEach(a => {
    add(localDay(a.performed_at), 'endurance', activityLoad(a, refs));
  });

  const out = [];
  const cursor = new Date(now);
  cursor.setHours(0, 0, 0, 0);
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(cursor);
    d.setDate(d.getDate() - i);
    const key = localDay(d);
    out.push(byDay.get(key) || { day: key, load: 0, strength: 0, endurance: 0 });
  }
  return out;
}

const sumLoad = rows => rows.reduce((a, r) => a + r.load, 0);

// Días transcurridos desde el primer entrenamiento registrado. No es lo mismo que el largo de
// la serie: la serie siempre trae 28 o 56 días, aunque el usuario lleve tres.
function historyDays(series){
  const first = series.findIndex(r => r.load > 0);
  return first === -1 ? 0 : series.length - first;
}

// Aguda (7 días) contra crónica (el promedio semanal de 28 días). La crónica se expresa por
// semana y no por día para que el cociente sea comparable con lo que publica la literatura.
//
// Y NO se calcula con menos de 28 días de historial. Con una sola semana registrada, esa
// semana se reparte entre cuatro y el cociente sale 4.0: la app decía "llevas 300% arriba de
// tu promedio" cuando no había promedio del cual estar arriba. Un número aritméticamente
// correcto y completamente falso es peor que ningún número — manda a descargar a alguien que
// apenas empezó.
function acwr(series){
  const acute = sumLoad(series.slice(-ACUTE_DAYS));
  const history = historyDays(series);
  if (history < CHRONIC_DAYS) {
    return { acute, chronic: null, ratio: null, history, ready: false };
  }
  const chronicTotal = sumLoad(series.slice(-CHRONIC_DAYS));
  const chronic = chronicTotal / (CHRONIC_DAYS / ACUTE_DAYS);
  return {
    acute,
    chronic: Math.round(chronic),
    ratio: chronic > 0 ? Math.round((acute / chronic) * 100) / 100 : null,
    history,
    ready: true,
  };
}

// Carga por semana natural (lunes a domingo), de la más vieja a la más nueva.
function weeklyLoads(series){
  const weeks = new Map();
  series.forEach(row => {
    const d = new Date(row.day + 'T00:00:00');
    d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
    const key = localDay(d);
    if (!weeks.has(key)) weeks.set(key, { weekStart: key, load: 0, strength: 0, endurance: 0, days: 0 });
    const w = weeks.get(key);
    w.load += row.load; w.strength += row.strength; w.endurance += row.endurance;
    if (row.load > 0) w.days += 1;
  });
  return [...weeks.values()].sort((a, b) => a.weekStart.localeCompare(b.weekStart));
}

// Una frase, no un tablero. El objetivo del módulo entero es este retorno: si no se puede
// decir qué hacer con el número, el número no vale la pena enseñarlo.
function readout(opts){
  const { series, isDeloadWeek = false } = opts || {};
  const ratios = acwr(series);
  const weeks = weeklyLoads(series);
  const current = weeks[weeks.length - 1];
  const previous = weeks.slice(0, -1);
  const baseline = mean(previous.map(w => w.load));
  const drop = baseline ? (baseline - (current ? current.load : 0)) / baseline : null;

  let level = 'ok', key = 'load.ok';
  // Sin 4 semanas de historial no hay comparación posible, y decirlo es más útil que inventar
  // un cociente. Las barras por semana sí sirven desde el primer día: enseñan el volumen real.
  if (!ratios.ready) { level = 'building'; key = 'load.building'; }
  else if (!ratios.ratio) { level = 'none'; key = 'load.none'; }
  else if (isDeloadWeek) {
    level = drop !== null && drop >= DELOAD_DROP ? 'deload' : 'deloadWeak';
    key = level === 'deload' ? 'load.deloadOk' : 'load.deloadWeak';
  }
  else if (ratios.ratio > ACWR_HIGH) { level = 'high'; key = 'load.high'; }
  else if (ratios.ratio < ACWR_LOW) { level = 'low'; key = 'load.low'; }

  return {
    ...ratios,
    weeks,
    currentWeek: current ? current.load : 0,
    baselineWeek: baseline === null ? null : Math.round(baseline),
    dropPct: drop === null ? null : Math.round(drop * 100),
    historyDays: ratios.history,
    weeksLogged: Math.ceil(ratios.history / 7),
    level,
    key,
  };
}

const api = {
  ACUTE_DAYS, CHRONIC_DAYS, ACWR_LOW, ACWR_HIGH, DELOAD_DROP,
  localDay, strengthRpe, sessionLoad, activityLoad, dailySeries, historyDays, acwr, weeklyLoads, readout,
};

if (typeof module !== 'undefined' && module.exports) module.exports = api;
else global.SkandiLoad = api;

})(typeof window !== 'undefined' ? window : globalThis);
