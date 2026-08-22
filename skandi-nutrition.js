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
  const carbs = Math.max(0, round((kcal - protein * KCAL_PER_G.protein - fat * KCAL_PER_G.fat) / KCAL_PER_G.carbs, 5));

  return { kcal, protein_g: protein, carbs_g: carbs, fat_g: fat, maintenance: round(maintenance, 10), mode, activityFactor };
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
  const total = { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 };
  (items || []).forEach(it => {
    if (it && it.included === false) return;
    total.kcal += num(it.kcal);
    total.protein_g += num(it.protein_g);
    total.carbs_g += num(it.carbs_g);
    total.fat_g += num(it.fat_g);
    total.fiber_g += num(it.fiber_g);
  });
  Object.keys(total).forEach(k => { total[k] = Math.round(total[k] * 10) / 10; });
  return total;
}

function dayTotals(meals) {
  return itemsTotal((meals || []).map(m => ({
    kcal: m.kcal, protein_g: m.protein_g, carbs_g: m.carbs_g, fat_g: m.fat_g, fiber_g: m.fiber_g
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
    fat_g: round(num(targets.fat_g_target) - num(totals.fat_g))
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
    fiber_g: cap(food.fiber_100g, 1000)
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
    fiber_g: cap(item.fiber_g, 1000)
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
    serving_grams: Math.round(g * 10) / 10
  };
}

const api = {
  KCAL_PER_G, ACTIVITY_FACTORS, MODE_FACTOR,
  suggestTargets, kcalFromMacros, itemsTotal, dayTotals, remaining, pct,
  scaleFood, rescaleItem, itemToFood
};

if (typeof module !== 'undefined' && module.exports) module.exports = api;
global.SkandiNutrition = api;

})(typeof globalThis !== 'undefined' ? globalThis : this);
