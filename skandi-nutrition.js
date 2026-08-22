// Skandi Fit — matemáticas de nutrición.
//
// Sin DOM y sin Supabase, igual que skandi-recovery.js: recibe filas, devuelve números, y se
// puede probar desde Node:
//   node -e "const N=require('./skandi-nutrition.js'); console.log(N.suggestTargets({weightKg:80}))"
//
// Sobre la meta calórica: usamos una estimación por peso corporal, no Mifflin-St Jeor, porque
// Mifflin necesita estatura, edad y sexo — tres datos que la app no tiene y que tendría que
// pedir en un formulario antes de dejarte registrar tu primera comida. La estimación por peso
// es menos precisa en el papel y prácticamente igual de útil en la realidad, porque una meta
// calórica NO se acierta de entrada: se ajusta contra la tendencia del peso a las 2-3 semanas.
// El número inicial solo tiene que estar en el estadio correcto. Además siempre es editable.
(function(global){
'use strict';

// kcal por kg de peso al día, antes del factor de actividad. 22 x 1.55 ≈ 34 kcal/kg para
// alguien que entrena 4-5 veces por semana, que es el rango que la literatura usa para
// mantenimiento en gente activa.
const KCAL_PER_KG_BASE = 22;

// Ajuste por objetivo. -15% es un déficit sostenible (≈0.5 kg/semana en un adulto de 80 kg);
// +10% es un superávit que gana músculo sin engordar de más.
const MODE_FACTOR = { deficit: 0.85, mantenimiento: 1, superavit: 1.10 };

// 2 g/kg de proteína cubre a cualquiera que levante pesas sin caer en el exceso inútil.
// 0.9 g/kg de grasa protege la función hormonal. Los carbohidratos son el resto: son el
// combustible, así que absorben tanto el déficit como el superávit.
const PROTEIN_G_PER_KG = 2.0;
const FAT_G_PER_KG = 0.9;
const KCAL_PER_G = { protein: 4, carbs: 4, fat: 9 };

const ACTIVITY_FACTORS = {
  sedentario: 1.25,
  ligero: 1.4,
  activo: 1.55,
  muyActivo: 1.75,
  atleta: 1.9
};

const round = (n, step = 1) => Math.round(n / step) * step;
const num = v => { const n = Number(v); return Number.isFinite(n) ? n : 0; };

// ---- Metas ----

function suggestTargets(opts) {
  const weightKg = num(opts && opts.weightKg);
  if (weightKg <= 0) return null;
  const activityFactor = num(opts.activityFactor) || ACTIVITY_FACTORS.activo;
  const mode = MODE_FACTOR[opts.mode] ? opts.mode : 'mantenimiento';

  const maintenance = weightKg * KCAL_PER_KG_BASE * activityFactor;
  const kcal = round(maintenance * MODE_FACTOR[mode], 10);

  const protein = round(weightKg * PROTEIN_G_PER_KG, 5);
  const fat = round(weightKg * FAT_G_PER_KG, 5);
  // Los carbohidratos salen por diferencia y nunca bajan de cero: en un déficit agresivo
  // sobre alguien muy pesado, proteína + grasa solas podrían pasarse de la meta.
  // Piso, no redondeo: así los macros nunca suman más que la meta de calorías.
  const carbs = Math.max(0, Math.floor((kcal - protein * KCAL_PER_G.protein - fat * KCAL_PER_G.fat) / KCAL_PER_G.carbs / 5) * 5);

  // Azúcar: techo en 10% de las calorías (la recomendación de la OMS), en gramos.
  // Fibra: 14 g por cada 1000 kcal, que es la referencia dietética habitual.
  const sugar = round((kcal * 0.10) / KCAL_PER_G.carbs, 5);
  const fiber = round((kcal / 1000) * 14, 5);

  return { kcal, protein_g: protein, carbs_g: carbs, fat_g: fat, sugar_g: sugar, fiber_g: fiber,
           maintenance: round(maintenance, 10), mode, activityFactor };
}

// Coherencia: lo que suman los macros contra lo que dice la meta de kcal. Sirve para avisar
// cuando alguien edita los números a mano y se le desbalancean.
function kcalFromMacros(protein, carbs, fat) {
  return round(num(protein) * KCAL_PER_G.protein + num(carbs) * KCAL_PER_G.carbs + num(fat) * KCAL_PER_G.fat);
}

// ---- Sumas del día ----

// Los renglones desmarcados (el aceite que no usaste) no cuentan. Es la misma regla que el
// trigger de la base, repetida aquí porque la UI suma en vivo mientras editas, antes de que
// nada llegue al servidor.
function itemsTotal(items) {
  const total = { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0, sugar_g: 0 };
  (items || []).forEach(it => {
    if (it && it.included === false) return;
    total.kcal += num(it.kcal);
    total.protein_g += num(it.protein_g);
    total.carbs_g += num(it.carbs_g);
    total.fat_g += num(it.fat_g);
    total.fiber_g += num(it.fiber_g);
    total.sugar_g += num(it.sugar_g);
  });
  Object.keys(total).forEach(k => { total[k] = Math.round(total[k] * 10) / 10; });
  return total;
}

function dayTotals(meals) {
  return itemsTotal((meals || []).map(m => ({
    kcal: m.kcal, protein_g: m.protein_g, carbs_g: m.carbs_g, fat_g: m.fat_g,
    fiber_g: m.fiber_g, sugar_g: m.sugar_g
  })));
}

// Negativo = te pasaste. Devolverlo con signo, en vez de recortarlo en cero, es lo que
// permite pintar "te pasaste por 240" en vez de un cero mentiroso.
function remaining(targets, totals) {
  if (!targets) return null;
  return {
    kcal: round(num(targets.kcal_target) - num(totals.kcal)),
    protein_g: round(num(targets.protein_g_target) - num(totals.protein_g)),
    carbs_g: round(num(targets.carbs_g_target) - num(totals.carbs_g)),
    fat_g: round(num(targets.fat_g_target) - num(totals.fat_g)),
    // El azúcar es un techo, no una meta: aquí "restante" significa cuánto te queda antes de
    // pasarte. Sin techo definido no hay nada que comparar.
    sugar_g: targets.sugar_g_target == null ? null : round(num(targets.sugar_g_target) - num(totals.sugar_g))
  };
}

function pct(value, target) {
  const t = num(target);
  if (t <= 0) return 0;
  return Math.max(0, Math.round((num(value) / t) * 100));
}

// ---- Alimentos del catálogo ----

// Escalar los macros por 100 g a la porción que se comió. Es el nivel 2 de la escalera de
// costo: "180 g de pechuga" es una multiplicación, no un problema de visión artificial.
function scaleFood(food, grams) {
  const g = Math.max(0, Math.min(num(grams), 5000));
  const k = g / 100;
  const cap = (v, max) => Math.min(Math.round(num(v) * k * 10) / 10, max);
  return {
    grams: Math.round(g * 10) / 10,
    kcal: cap(food.kcal_100g, 10000),
    protein_g: cap(food.protein_100g, 1000),
    carbs_g: cap(food.carbs_100g, 1000),
    fat_g: cap(food.fat_100g, 1000),
    fiber_g: cap(food.fiber_100g, 1000),
    sugar_g: cap(food.sugar_100g, 1000)
  };
}

// Reescalar un renglón ya estimado cuando corriges los gramos: mantiene la densidad que el
// modelo (o tú) le asignaron y solo cambia la cantidad. Si el renglón no traía gramos, no hay
// densidad que conservar y se devuelve igual.
function rescaleItem(item, newGrams) {
  const oldG = num(item.grams);
  const g = Math.max(0, Math.min(num(newGrams), 5000));
  if (oldG <= 0 || g <= 0) return Object.assign({}, item, { grams: g });
  const k = g / oldG;
  const cap = (v, max) => Math.min(Math.round(num(v) * k * 10) / 10, max);
  return Object.assign({}, item, {
    grams: Math.round(g * 10) / 10,
    kcal: cap(item.kcal, 10000),
    protein_g: cap(item.protein_g, 1000),
    carbs_g: cap(item.carbs_g, 1000),
    fat_g: cap(item.fat_g, 1000),
    fiber_g: cap(item.fiber_g, 1000),
    sugar_g: cap(item.sugar_g, 1000)
  });
}

// Un renglón corregido a mano vale como alimento del catálogo: guardamos su densidad por
// 100 g para poder reusarlo. Sin gramos no hay densidad posible.
function itemToFood(item) {
  const g = num(item.grams);
  if (g <= 0) return null;
  const per100 = v => Math.round((num(v) / g) * 100 * 100) / 100;
  return {
    name: String(item.label || '').trim().slice(0, 120),
    kcal_100g: Math.min(per100(item.kcal), 1000),
    protein_100g: Math.min(per100(item.protein_g), 100),
    carbs_100g: Math.min(per100(item.carbs_g), 100),
    fat_100g: Math.min(per100(item.fat_g), 100),
    fiber_100g: Math.min(per100(item.fiber_g), 100),
    sugar_100g: Math.min(per100(item.sugar_g), 100),
    serving_grams: Math.round(g * 10) / 10
  };
}

// ---- El entrenamiento del día ----
//
// Aquí hay una trampa fácil de pisar: el factor de actividad de la meta YA incluye que
// entrenas. Sumarle a la meta las calorías del entrenamiento de hoy sería contarlas dos
// veces, y es el error que hace que una app te diga que te comas 3,400 kcal por haber
// corrido 5 km.
//
// Lo correcto es ajustar por la DIFERENCIA contra tu día promedio de la semana: si hoy
// entrenas más que tu promedio, te faltan calorías; si hoy descansas, te sobran. Un día
// promedio no ajusta nada, que es exactamente como debe ser.
//
// El ajuste va a carbohidratos. La proteína es por kilo de peso y no cambia porque hoy
// corras, y la grasa tiene un piso hormonal que no conviene mover día con día.

const MET = {
  running: 9.8, cycling: 7.5, swimming: 7.0, rowing: 7.0,
  walking: 3.5, hiit: 9.0, strength_class: 6.0, other: 5.0
};
const STRENGTH_MET = 5.0;   // levantar pesas con descansos reales, no en circuito
const MIN_PER_SET = 3.5;    // serie + descanso: la duración de una sesión sale de sus series
const NEUTRAL_DELTA = 120;  // por debajo de esto, el día no se considera distinto al promedio

// El esfuerzo percibido (RPE 1-10) modula el MET: correr a 5 no quema lo mismo que a 9.
function effortFactor(intensity) {
  const rpe = num(intensity) || 5;
  return Math.max(0.6, Math.min(1.35, 0.75 + (rpe - 5) * 0.05));
}

function activityKcal(activity, weightKg) {
  const w = num(weightKg);
  const minutes = num(activity && activity.duration_min);
  if (w <= 0 || minutes <= 0) return 0;
  const met = MET[activity.activity_type] || MET.other;
  return Math.round(met * w * (minutes / 60) * effortFactor(activity.intensity));
}

function strengthKcal(sets, weightKg) {
  const w = num(weightKg);
  const n = num(sets);
  if (w <= 0 || n <= 0) return 0;
  return Math.round(STRENGTH_MET * w * ((n * MIN_PER_SET) / 60));
}

// Lo que un día de la semana tiene PLANEADO quemar, según la rutina y el plan de cardio
// asignados a ese día. dow: 0 = lunes, como en todo el resto de la app.
function plannedDayKcal(dow, plan) {
  const { templates = [], templateItems = [], activityTemplates = [], weightKg } = plan || {};
  let kcal = 0;
  templates.filter(tp => tp.weekday === dow).forEach(tp => {
    const sets = templateItems
      .filter(it => it.template_id === tp.id)
      .reduce((acc, it) => acc + (num(it.target_sets) || 3), 0);
    kcal += strengthKcal(sets, weightKg);
  });
  activityTemplates.filter(at => at.weekday === dow).forEach(at => {
    kcal += activityKcal({
      activity_type: at.activity_type,
      duration_min: at.target_duration_min || estimateMinutesFromDistance(at),
      // Sin RPE en un plan, la zona de FC es la mejor pista: zona 2 es suave, zona 4-5 es dura.
      intensity: at.target_zone ? at.target_zone * 2 : 5
    }, weightKg);
  });
  return kcal;
}

// Un plan que solo dice "5 km" sí tiene duración: la del ritmo objetivo, o un ritmo típico.
function estimateMinutesFromDistance(at) {
  const km = num(at && at.target_distance_km);
  if (km <= 0) return 0;
  const pace = num(at.target_pace_sec_per_km) || 330; // 5:30/km por defecto
  return Math.round((km * pace) / 60);
}

function weeklyPlan(plan) {
  const byDow = [0, 1, 2, 3, 4, 5, 6].map(d => plannedDayKcal(d, plan));
  const total = byDow.reduce((a, b) => a + b, 0);
  return { byDow, total, avgDaily: Math.round(total / 7) };
}

// La recomendación del día. `loggedKcal` son las actividades YA registradas hoy: si ya
// corriste, manda lo que hiciste sobre lo que estaba planeado — un plan no es un hecho.
function dayRecommendation(opts) {
  const { targets, plan, dow, loggedKcal = 0, hasLoggedActivity = false } = opts || {};
  if (!targets) return null;
  const week = weeklyPlan(plan);
  const planned = plannedDayKcal(dow, plan);
  const today = hasLoggedActivity ? Math.max(loggedKcal, 0) : planned;
  const delta = round(today - week.avgDaily, 10);
  const meaningful = Math.abs(delta) >= NEUTRAL_DELTA;

  return {
    plannedKcal: planned,
    todayKcal: today,
    avgDaily: week.avgDaily,
    weeklyKcal: week.total,
    fromLog: hasLoggedActivity,
    delta: meaningful ? delta : 0,
    level: !meaningful ? 'normal' : delta > 0 ? 'alto' : 'bajo',
    // La meta ajustada: solo los carbos se mueven.
    kcalTarget: num(targets.kcal_target) + (meaningful ? delta : 0),
    carbsTarget: Math.max(0, round(num(targets.carbs_g_target) + (meaningful ? delta / KCAL_PER_G.carbs : 0), 5))
  };
}

const api = {
  KCAL_PER_G, ACTIVITY_FACTORS, MODE_FACTOR, MET,
  suggestTargets, kcalFromMacros, itemsTotal, dayTotals, remaining, pct,
  scaleFood, rescaleItem, itemToFood,
  activityKcal, strengthKcal, plannedDayKcal, weeklyPlan, dayRecommendation
};

if (typeof module !== 'undefined' && module.exports) module.exports = api;
global.SkandiNutrition = api;

})(typeof globalThis !== 'undefined' ? globalThis : this);
