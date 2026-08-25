// Skandi Fit — carga articular por zona (muñeca, codo, hombro). Matemáticas puras: sin DOM y
// sin Supabase, igual que skandi-recovery.js y skandi-load.js.
//
// Por qué esto es un módulo aparte y no una fila más en skandi-recovery.js: el músculo se
// recupera y listo — dolor de hoy, fresco en 2-3 días, y el modelo de decaimiento exponencial
// de skandi-recovery.js contesta exactamente eso. El tendón no funciona así: una tendinopatía
// de muñeca o codo no aparece por una sesión dura, aparece por semanas de volumen subiendo más
// rápido de lo que el tejido conectivo se adapta — el mismo patrón de "carga que sube demasiado
// rápido" que skandi-load.js ya mide para el cuerpo entero con el cociente agudo:crónico de
// Gabbett. Por eso este módulo NO reimplementa esa matemática: reusa Load.acwr() tal cual,
// solo que alimentada con una serie diaria por articulación en vez de sRPE de cuerpo entero.
//
// Y por qué exactamente muñeca/codo/hombro: son los tres puntos donde la calistenia de
// estáticos concentra la carga que un entrenamiento de fuerza normal reparte entre muchos más
// grupos — front lever y muscle-up cargan codo en extensión/flexión sostenida, handstand y
// planche cargan la muñeca en extensión bajo el peso completo del cuerpo. Es exactamente el
// perfil de lesión típico de quien hace calistenia en serio (tendinopatía de muñeca, epicondilitis).

(function(global){
'use strict';

const Recovery = (typeof module !== 'undefined' && module.exports)
  ? require('./skandi-recovery.js')
  : global.SkandiRecovery;
const Load = (typeof module !== 'undefined' && module.exports)
  ? require('./skandi-load.js')
  : global.SkandiLoad;

const JOINTS = ['wrist', 'elbow', 'shoulder'];

// Reparto por línea de progresión, no por ejercicio individual: afirmar un porcentaje exacto
// por ejercicio sería tan poco defendible como inventar el nombre de un ejercicio — ya nos
// costó caro una vez en esta misma app (el front lever confundido con straddle). Esto dice
// "front lever carga codo y hombro fuerte, muñeca casi nada" — cierto para cualquier escalón de
// esa línea, que es el nivel de precisión que el dato categórico realmente sostiene.
const JOINT_LOAD_MAP = {
  'front-lever':       { elbow: 45, shoulder: 40, wrist: 15 },
  'front-lever-raise': { elbow: 45, shoulder: 40, wrist: 15 },
  'back-lever':        { elbow: 40, shoulder: 45, wrist: 15 },
  handstand:           { wrist: 70, shoulder: 30 },
  planche:             { wrist: 55, shoulder: 35, elbow: 10 },
};

// Ejercicios fuera de una línea de progresión que igual cargan estas articulaciones con
// fuerza — coincidencia por slug/nombre, deliberadamente aproximada (ver nota arriba).
const SLUG_JOINT_MAP = [
  [/dip/, { elbow: 55, shoulder: 35, wrist: 10 }],
  [/muscle-up|pull-up|pullup|chin-up|\brow\b/, { elbow: 50, shoulder: 35, wrist: 15 }],
  [/push-up|hspu/, { wrist: 60, shoulder: 30, elbow: 10 }],
];

function jointSplitFor(exercise){
  if (!exercise) return null;
  if (exercise.progression_group && JOINT_LOAD_MAP[exercise.progression_group]) {
    return JOINT_LOAD_MAP[exercise.progression_group];
  }
  const slug = (exercise.slug || exercise.name || '').toLowerCase();
  const hit = SLUG_JOINT_MAP.find(([re]) => re.test(slug));
  return hit ? hit[1] : null;
}

// Estímulo diario para UNA articulación, del más viejo al más nuevo, sin huecos — mismo
// requisito que dailySeries() en skandi-load.js, por la misma razón: el promedio de 28 días
// tiene que caer sobre días calendario reales, no solo los días entrenados.
function dailyJointSeries({ sets = [], sessions = [], exercises = [], userId, joint, days = Load.CHRONIC_DAYS, now = Date.now() }){
  const exerciseById = new Map(exercises.map(e => [e.id, e]));
  const sessionById = new Map(sessions.map(s => [s.id, s]));
  const byDay = new Map();
  sets.forEach(s => {
    if (!s.done || (userId && s.user_id !== userId)) return;
    const session = sessionById.get(s.session_id);
    if (!session || !session.completed_at) return;
    const split = jointSplitFor(exerciseById.get(s.exercise_id));
    if (!split || !split[joint]) return;
    const su = Recovery.setStimulusUnits(s) * split[joint] / 100;
    if (!su) return;
    const day = Load.localDay(session.completed_at);
    if (!day) return;
    byDay.set(day, (byDay.get(day) || 0) + su);
  });
  const out = [];
  const cursor = new Date(now);
  cursor.setHours(0, 0, 0, 0);
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(cursor);
    d.setDate(d.getDate() - i);
    const key = Load.localDay(d);
    out.push({ day: key, load: byDay.get(key) || 0 });
  }
  return out;
}

// Una articulación que nunca ha cargado nada (el usuario no entrena handstand/front lever/etc)
// es 'none', no 'building' — 'building' es para cuando SÍ hay carga pero todavía no las 4
// semanas de historial que el cociente agudo:crónico necesita para significar algo.
function jointReadout(opts){
  const { joint } = opts;
  const series = dailyJointSeries({ ...opts, days: Load.CHRONIC_DAYS * 2 });
  const total = series.reduce((a, r) => a + r.load, 0);
  if (!total) return { joint, acute: 0, chronic: null, ratio: null, history: 0, ready: false, level: 'none', key: 'joint.none' };
  const r = Load.acwr(series);
  let level, key;
  if (!r.ready) { level = 'building'; key = 'joint.building'; }
  else if (!r.ratio) { level = 'none'; key = 'joint.none'; }
  else if (r.ratio > Load.ACWR_HIGH) { level = 'high'; key = 'joint.high'; }
  else if (r.ratio < Load.ACWR_LOW) { level = 'low'; key = 'joint.low'; }
  else { level = 'ok'; key = 'joint.ok'; }
  return { joint, ...r, level, key };
}

// Las tres, ordenadas por riesgo: primero la que va alta, luego la que va baja/perdiendo
// entrenamiento, luego las normales, luego las que no tienen suficiente historial o no cargan
// nada — para que la tarjeta pueda mostrar "esto es lo que de verdad importa hoy" sin que el
// llamador tenga que decidir el orden.
function allJointsReadout(opts){
  const rank = { high: 0, low: 1, ok: 2, building: 3, none: 4 };
  return JOINTS.map(joint => jointReadout({ ...opts, joint }))
    .sort((a, b) => (rank[a.level] - rank[b.level]) || ((b.ratio || 0) - (a.ratio || 0)));
}

const api = { JOINTS, JOINT_LOAD_MAP, jointSplitFor, dailyJointSeries, jointReadout, allJointsReadout };

if (typeof module !== 'undefined' && module.exports) module.exports = api;
else global.SkandiJointLoad = api;

})(typeof window !== 'undefined' ? window : globalThis);
