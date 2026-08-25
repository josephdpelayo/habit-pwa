// Skandi Fit — el porqué del día.
//
// La app ya sabía todo lo necesario para explicar un día: qué toca, en qué semana del bloque
// vas, cómo dormiste, qué músculos siguen cansados, cuánta carga llevas y cuánto deberías
// comer. Lo que no hacía era juntarlo en una frase que le diga a una persona por qué el
// entrenamiento de hoy es el que es. Sin ese porqué, un plan se ejecuta por obediencia, y lo
// que se ejecuta por obediencia se abandona en la primera semana difícil.
//
// Devuelve CLAVES de traducción con sus parámetros, no texto: la copia vive en el i18n de
// skandi.html y aquí solo vive la decisión de qué decir. Eso es lo que hace probable la regla
// sin arrastrar el idioma.
//
// Deliberadamente NO usa el modelo de IA. Un resumen que cambia de redacción cada mañana no se
// puede auditar, cuesta por día y no funciona sin señal a bordo. Las reglas de abajo son
// explícitas, gratis y siempre dicen lo mismo ante los mismos datos.

(function(global){
'use strict';

// Umbrales: por debajo de esto un músculo todavía no está listo para volver a cargarse, y una
// noche corta deja de ser ruido de medición.
const TIRED_MUSCLE = 60;        // % de frescura
const SLEEP_GAP_MIN = 45;
const RESTING_HR_JUMP = 3;
const EASY_ZONE = 2;
const HARD_ZONE = 4;

const ENDURANCE = new Set(['run','bike','swim','row','walk']);

function isHard(p){
  return p.discipline === 'hiit' || p.discipline === 'hyrox' || Number(p.target_zone) >= HARD_ZONE;
}

// El objetivo de UNA sesión. El orden importa: lo específico primero, porque un día de
// habilidad en zona 2 es un día de habilidad, no un rodaje.
function sessionPurpose(p, ctx){
  const { exercisesOf, isDeload } = ctx;
  if (p.discipline === 'rest') return { key: 'brief.train.rest' };
  if (p.discipline === 'mobility') return { key: 'brief.train.mobility' };

  if (p.discipline === 'strength') {
    const list = (exercisesOf ? exercisesOf(p) : []) || [];
    const skills = list.filter(e => e && e.progression_group);
    if (skills.length) {
      return { key: isDeload ? 'brief.train.skillDeload' : 'brief.train.skill',
               params: { name: skills[0].name, n: skills.length } };
    }
    return { key: isDeload ? 'brief.train.strengthDeload' : 'brief.train.strength' };
  }

  if (p.discipline === 'hiit' || p.discipline === 'hyrox') {
    return { key: 'brief.train.hiit', params: { min: p.target_duration_min || 0 } };
  }

  if (ENDURANCE.has(p.discipline)) {
    const zone = Number(p.target_zone) || 0;
    const min = p.target_duration_min || 0;
    if (p.discipline === 'swim' && !zone) return { key: 'brief.train.swimTechnique' };
    if (zone >= HARD_ZONE) return { key: 'brief.train.threshold', params: { min, zone } };
    if (zone === 3) return { key: 'brief.train.tempo', params: { min } };
    if (zone && zone <= EASY_ZONE) return { key: 'brief.train.base', params: { min } };
    return { key: 'brief.train.easy', params: { min } };
  }
  return { key: 'brief.train.other' };
}

// La línea de arriba: qué clase de día es este. Una sola, y la más específica que aplique.
function headline(sessions, ctx){
  if (ctx.isDeload) return { key: 'brief.head.deload', params: { week: ctx.blockWeek, total: ctx.blockTotal } };
  if (!sessions.length) return { key: 'brief.head.empty' };
  if (sessions.every(p => p.discipline === 'rest')) return { key: 'brief.head.rest' };
  const real = sessions.filter(p => p.discipline !== 'rest');
  if (real.some(isHard)) return { key: 'brief.head.quality' };
  if (real.length > 1) return { key: 'brief.head.double', params: { n: real.length } };
  if (real.every(p => p.discipline === 'strength')) return { key: 'brief.head.strength' };
  return { key: 'brief.head.base' };
}

// Lo que hay que cuidar hoy. Solo se dice cuando hay algo que decir: una lista de avisos que
// aparece todos los días deja de leerse a la tercera mañana.
function cautions(sessions, ctx){
  const out = [];
  const { sleepGapMin, restingHrJump, loadLevel, tiredMuscles = [] } = ctx;

  if (sleepGapMin != null && sleepGapMin <= -SLEEP_GAP_MIN) {
    out.push({ key: 'brief.caution.sleep', params: { min: Math.abs(Math.round(sleepGapMin)) } });
  }
  if (restingHrJump != null && restingHrJump >= RESTING_HR_JUMP) {
    out.push({ key: 'brief.caution.hr', params: { n: Math.round(restingHrJump) } });
  }
  if (loadLevel === 'high') out.push({ key: 'brief.caution.load' });
  if (loadLevel === 'deloadWeak') out.push({ key: 'brief.caution.deloadWeak' });

  // A joint (wrist/elbow/shoulder) whose recent load is ramping faster than its 4-week average
  // is the overuse-injury pattern, not the muscle-soreness one — worth its own line since it
  // reads and means something different from the whole-body load caution above.
  if (ctx.jointHigh) out.push({ key: 'brief.caution.joint', params: { name: ctx.jointHigh.name, pct: ctx.jointHigh.pct } });

  // Un músculo cansado solo importa si HOY se entrena.
  const trainsStrength = sessions.some(p => p.discipline === 'strength');
  if (trainsStrength && tiredMuscles.length) {
    const worst = tiredMuscles.slice().sort((a, b) => a.freshness - b.freshness)[0];
    if (worst && worst.freshness < TIRED_MUSCLE) {
      out.push({ key: 'brief.caution.muscle', params: { muscle: worst.label || worst.muscle, pct: Math.round(worst.freshness) } });
    }
  }
  return out;
}

// La comida del día, explicada por su causa: cuánto y POR QUÉ ese número hoy y no otro.
function fuel(sessions, ctx){
  const { rec, targets, fuelFor, isDeload } = ctx;
  const out = [];
  if (!rec || !targets) return out;

  out.push({ key: 'brief.fuel.target', params: {
    kcal: Math.round(rec.kcalTarget), protein: Math.round(targets.protein_g_target || 0),
    carbs: Math.round(rec.carbsTarget)
  }});

  if (rec.delta) {
    const stepsOnly = rec.stepsDelta && Math.abs(rec.stepsDelta) >= Math.abs(rec.delta) * 0.6;
    out.push({ key: rec.delta > 0
        ? (stepsOnly ? 'brief.fuel.upSteps' : 'brief.fuel.upTraining')
        : (isDeload ? 'brief.fuel.downDeload' : 'brief.fuel.down'),
      params: { delta: Math.abs(Math.round(rec.delta)) } });
  } else {
    out.push({ key: 'brief.fuel.flat' });
  }

  const main = sessions.filter(p => p.discipline !== 'rest')[0];
  const plan = main && fuelFor ? fuelFor(main) : null;
  if (plan) {
    if (plan.before) out.push({ key: 'brief.fuel.before', params: { carbs: plan.before.carbs_g, min: plan.before.minutes_before } });
    else out.push({ key: 'brief.fuel.noPre' });
    if (plan.during) out.push({ key: 'brief.fuel.during', params: { carbs: plan.during.carbs_g_per_hour } });
    if (plan.after) out.push({ key: 'brief.fuel.after', params: { carbs: plan.after.carbs_g, protein: plan.after.protein_g } });
  } else if (sessions.every(p => p.discipline === 'rest')) {
    out.push({ key: 'brief.fuel.restDay' });
  }
  return out;
}

function today(ctx){
  const sessions = (ctx && ctx.sessions) || [];
  return {
    headline: headline(sessions, ctx),
    training: sessions.map(p => ({ session: p, purpose: sessionPurpose(p, ctx) })),
    cautions: cautions(sessions, ctx),
    fuel: fuel(sessions, ctx),
  };
}

const api = { TIRED_MUSCLE, SLEEP_GAP_MIN, RESTING_HR_JUMP, isHard, sessionPurpose, headline, cautions, fuel, today };
if (typeof module !== 'undefined' && module.exports) module.exports = api;
else global.SkandiBrief = api;

})(typeof window !== 'undefined' ? window : globalThis);
