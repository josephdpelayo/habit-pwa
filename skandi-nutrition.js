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

// La proteína depende del objetivo, no es un número fijo. Morton 2018 (meta-análisis) y la
// evidencia que resume la guía de nutrición híbrida sitúan la ingesta típica de un atleta
// concurrente en 1.4-1.6 g/kg/día, y reservan la banda alta (hasta 2.0-2.2) para déficits
// calóricos marcados o volumen de entrenamiento muy alto — no para todos los días por default,
// que es lo que hacía un 2.0 g/kg fijo sin importar el modo.
const PROTEIN_G_PER_KG_BY_MODE = { deficit: 2.0, mantenimiento: 1.6, superavit: 1.8 };
// 0.9 g/kg de grasa protege la función hormonal. Los carbohidratos son el resto: son el
// combustible, así que absorben tanto el déficit como el superávit.
const FAT_G_PER_KG = 0.9;
const KCAL_PER_G = { protein: 4, carbs: 4, fat: 9 };

// RED-S (Mountjoy et al., 2018): por debajo de ~30 kcal/kg de masa libre de grasa al día
// empiezan a aparecer alteraciones hormonales y peor recuperación. La app no mide % de grasa,
// así que 30 contra el peso TOTAL saldría casi siempre por debajo del umbral real — hasta el
// déficit del -15% que la propia app sugiere arriba ronda 29 kcal/kg y lo dispararía sin que
// haya nada raro. Por eso el piso vive más abajo: no es "¿tu meta calculada es un déficit?",
// es "¿alguien escribió un número que ni el déficit más agresivo de la app propondría?". No
// se usa dentro de suggestTargets (que nunca baja de esto) sino al validar un número que el
// usuario tecleó a mano.
const LOW_ENERGY_KCAL_PER_KG_FLOOR = 24;

// ¿Este número de calorías, para este peso, es tan bajo que ni siquiera es una decisión de
// déficit — es un dato que probablemente se tecleó mal, o que necesita supervisión aparte?
function isLowEnergy(kcal, weightKg) {
  const w = num(weightKg);
  if (w <= 0) return false;
  return num(kcal) < w * LOW_ENERGY_KCAL_PER_KG_FLOOR;
}

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

  const protein = round(weightKg * PROTEIN_G_PER_KG_BY_MODE[mode], 5);
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
  // added_sugar_g llega undefined en todo renglón leído antes de correr la migración 089 (la
  // columna no existe todavía): num() lo convierte en 0, así que la suma es correcta con o sin
  // la migración corrida, y se pone al día sola en cuanto exista la columna.
  const total = { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0, sugar_g: 0, added_sugar_g: 0 };
  (items || []).forEach(it => {
    if (it && it.included === false) return;
    total.kcal += num(it.kcal);
    total.protein_g += num(it.protein_g);
    total.carbs_g += num(it.carbs_g);
    total.fat_g += num(it.fat_g);
    total.fiber_g += num(it.fiber_g);
    total.sugar_g += num(it.sugar_g);
    total.added_sugar_g += num(it.added_sugar_g);
  });
  Object.keys(total).forEach(k => { total[k] = Math.round(total[k] * 10) / 10; });
  return total;
}

function dayTotals(meals) {
  return itemsTotal((meals || []).map(m => ({
    kcal: m.kcal, protein_g: m.protein_g, carbs_g: m.carbs_g, fat_g: m.fat_g,
    fiber_g: m.fiber_g, sugar_g: m.sugar_g, added_sugar_g: m.added_sugar_g
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
    sugar_g: targets.sugar_g_target == null ? null : round(num(targets.sugar_g_target) - num(totals.sugar_g)),
    added_sugar_g: targets.added_sugar_g_target == null ? null
      : round(num(targets.added_sugar_g_target) - num(totals.added_sugar_g))
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
    sugar_g: cap(food.sugar_100g, 1000),
    added_sugar_g: cap(food.added_sugar_100g, 1000)
  };
}

// ---- ¿Me conviene? Verdicto informativo para UN alimento, antes de decidir si comerlo ----
//
// No llama a ningún modelo: es aritmética contra lo que ya sabemos (tus metas y lo que llevas
// hoy). El caso real es escanear un código de barras sin saber si vale la pena — "informativo,
// para decidir yo", no una regla que bloquea nada. Nunca dice "esto es malo": dice contra qué
// techo o meta específica choca, con el número, para que la decisión siga siendo tuya. Devuelve
// motivos como datos ({kind,...}), no texto — igual que fuelPlan(), la traducción es cosa de
// quien llama esto.
// scaled trae las mismas siete llaves que produce scaleFood()/itemsTotal(): kcal, protein_g,
// carbs_g, fat_g, fiber_g, sugar_g, added_sugar_g — venga de un alimento del catálogo escalado
// por gramos, o de la suma de varios renglones que ya vienen en absoluto (una foto analizada).
function evaluateScaled(scaled, remaining, targets) {
  const reasons = [];
  let verdict = 'good';

  // Azúcar (añadida si existe la columna, si no la total) es un TECHO: lo único que de verdad
  // amerita una alerta, porque pasarse no se "compensa" comiendo menos de otra cosa hoy.
  const sugarCap = targets && (targets.added_sugar_g_target != null ? targets.added_sugar_g_target : targets.sugar_g_target);
  const sugarLeft = remaining && (remaining.added_sugar_g != null ? remaining.added_sugar_g : remaining.sugar_g);
  const sugarHere = scaled.added_sugar_g || scaled.sugar_g;
  if (sugarCap != null && sugarLeft != null && sugarHere > 0) {
    if (sugarLeft <= 0) {
      verdict = 'bad';
      reasons.push({ kind: 'sugar_over', g: round(sugarHere) });
    } else if (sugarHere > sugarLeft) {
      verdict = 'caution';
      reasons.push({ kind: 'sugar_tight', g: round(sugarHere), left: round(sugarLeft) });
    }
  }

  // Una sola porción que se lleva más de la mitad de las kcal que te quedan hoy no está "mal",
  // pero si te la comes casi no queda espacio para nada más y conviene saberlo antes, no después.
  if (verdict !== 'bad' && remaining && remaining.kcal > 0 && scaled.kcal > remaining.kcal * 0.5) {
    verdict = 'caution';
    reasons.push({ kind: 'kcal_heavy', kcal: round(scaled.kcal), left: round(remaining.kcal) });
  }

  // Poca proteína por muchas kcal, cuando todavía te falta proteína del día: no es que el
  // alimento esté mal, es que no es el que te acerca a tu meta de proteína de hoy.
  if (verdict === 'good' && remaining && remaining.protein_g > 15 && scaled.kcal > 0) {
    const proteinShare = (scaled.protein_g * KCAL_PER_G.protein) / scaled.kcal;
    if (proteinShare < 0.08) {
      verdict = 'caution';
      reasons.push({ kind: 'low_protein', g: round(scaled.protein_g) });
    }
  }

  if (verdict === 'good' && !reasons.length) reasons.push({ kind: 'fits' });
  return { verdict, reasons };
}

// Wrapper para un alimento del catálogo (código de barras, "del catálogo"): escala primero,
// evalúa después. Para renglones que YA vienen en absoluto (una foto analizada, varios a la
// vez), usa evaluateScaled() directo sobre su suma (itemsTotal()).
function evaluateFood(food, grams, remaining, targets) {
  const scaled = scaleFood(food, grams);
  return Object.assign({ scaled }, evaluateScaled(scaled, remaining, targets));
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
    sugar_g: cap(item.sugar_g, 1000),
    added_sugar_g: cap(item.added_sugar_g, 1000)
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
    added_sugar_100g: Math.min(per100(item.added_sugar_g), 100),
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
//
// Qué cuenta como "planeado" hoy y en la semana no es cosa de esta función: se lo pasa
// quien llama (plannedKcal, avgDaily), calculado a partir del calendario real
// (skandi_planned_sessions), que es la única fuente que ve tanto la semana recurrente
// normal como una semana especial (descarga, viaje) con rutinas fuera del día de la
// semana de siempre.

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

// La recomendación del día. `loggedKcal` son las actividades YA registradas hoy: si ya
// corriste, manda lo que hiciste sobre lo que estaba planeado — un plan no es un hecho.
// ---- Los pasos del día ----
//
// Un día de 15,000 pasos y uno de 5,000 no piden la misma comida, y esa diferencia (~350 kcal
// para 70 kg) es del tamaño de una comida entera. Pero se usa la DIFERENCIA contra tu propio
// promedio, nunca el gasto absoluto de caminar, por dos razones que apuntan al mismo error:
// el `activity_factor` de tus metas ya asume tu nivel normal de movimiento, y los pasos de
// una carrera ya están contados como carrera. Restar tu promedio cancela las dos.
//
// El costo por paso escala con la masa (~0.0005 kcal por paso y por kg: 0.035 para 70 kg,
// dentro del rango de 0.03-0.05 que reportan los estudios de podometría).
const KCAL_PER_STEP_PER_KG = 0.0005;
const STEPS_ADJUST_CAP = 400;   // un GPS loco o un día de senderismo no reescriben tu meta

function stepsAdjustmentKcal(opts) {
  const { steps, avgSteps, weightKg } = opts || {};
  const today = num(steps), average = num(avgSteps), weight = num(weightKg);
  if (!today || !average || !weight) return 0;
  const kcal = (today - average) * weight * KCAL_PER_STEP_PER_KG;
  return round(Math.max(-STEPS_ADJUST_CAP, Math.min(STEPS_ADJUST_CAP, kcal)), 10);
}

function dayRecommendation(opts) {
  const { targets, plannedKcal = 0, avgDaily = 0, loggedKcal = 0, hasLoggedActivity = false,
          steps = null, avgSteps = null, weightKg = null } = opts || {};
  if (!targets) return null;
  const average = num(avgDaily);
  const planned = num(plannedKcal);
  // Haber registrado algo no significa haber terminado el día: si todavía falta la mitad de
  // lo planeado, la meta del día no debe encogerse ni deben desaparecer los consejos de la
  // sesión que falta. Por eso el día vale lo MAYOR entre lo hecho y lo planeado.
  const today = Math.max(num(loggedKcal), planned);
  const pendingKcal = Math.max(0, planned - num(loggedKcal));
  // "Terminado" = ya se hizo el grueso de lo planeado (o no había plan y entrenó de más).
  const finished = hasLoggedActivity && pendingKcal <= planned * 0.3;
  // El entrenamiento y el movimiento del día son dos desviaciones distintas del mismo
  // promedio, así que se suman antes de decidir si el día se salió de lo normal.
  const stepsDelta = stepsAdjustmentKcal({ steps, avgSteps, weightKg });
  const delta = round(today - average + stepsDelta, 10);
  const meaningful = Math.abs(delta) >= NEUTRAL_DELTA;

  return {
    plannedKcal: planned,
    todayKcal: today,
    loggedKcal: num(loggedKcal),
    pendingKcal,
    avgDaily: average,
    hasLog: hasLoggedActivity,
    fromLog: finished,
    delta: meaningful ? delta : 0,
    stepsDelta,
    level: !meaningful ? 'normal' : delta > 0 ? 'alto' : 'bajo',
    // La meta ajustada: solo los carbos se mueven.
    kcalTarget: num(targets.kcal_target) + (meaningful ? delta : 0),
    carbsTarget: Math.max(0, round(num(targets.carbs_g_target) + (meaningful ? delta / KCAL_PER_G.carbs : 0), 5))
  };
}

// ---- Cómo comerlo, no solo cuánto ----
//
// Saber que hoy te faltan 400 kcal no te dice qué hacer. Lo accionable es el TIMING: unos
// carbos antes de la carrera, algo de proteína al terminar. Las cantidades siguen las
// referencias estándar de nutrición deportiva, escaladas a tu peso:
//
//   Antes  : ~1 g/kg de carbos 60-90 min antes, solo si la sesión lo amerita.
//   Durante: 30-60 g/hora, y solo por arriba de ~75 min. Abajo de eso no hace falta nada.
//   Después: ~1 g/kg de carbos y ~0.3 g/kg de proteína en la primera hora y media.
//
// La regla que evita el consejo tonto: una sesión corta y suave NO necesita carga previa.
// Decirle a alguien que se coma 80 g de carbos antes de trotar 25 minutos es empujarlo a
// comer de más con cara de consejo experto.

const FUEL = {
  PRE_G_PER_KG: 1.0,
  POST_CARB_G_PER_KG: 1.0,
  POST_PROTEIN_G_PER_KG: 0.3,
  PRE_MINUTES: 75,
  POST_MINUTES: 90,
  DURING_MIN_MINUTES: 75,
  DURING_G_PER_HOUR: 45,
  // Debajo de esto (y a intensidad baja) no hay nada que cargar antes.
  EASY_MINUTES: 45,
  EASY_RPE: 6
};

function fuelPlan(session, weightKg) {
  const w = num(weightKg);
  const minutes = num(session && session.minutes);
  if (w <= 0 || minutes <= 0) return null;

  const easy = minutes < FUEL.EASY_MINUTES && num(session.intensity) <= FUEL.EASY_RPE;
  const long = minutes >= FUEL.DURING_MIN_MINUTES;

  return {
    kind: session.kind,
    activity_type: session.activity_type,
    minutes,
    distance_km: session.distance_km || null,
    kcal: session.kcal || 0,
    // Una sesión corta y suave se puede hacer en ayunas sin problema: no inventamos una carga.
    before: easy ? null : {
      carbs_g: round(w * FUEL.PRE_G_PER_KG * (session.kind === 'strength' ? 0.6 : 1), 5),
      minutes_before: FUEL.PRE_MINUTES
    },
    // Solo en cardio largo. Comer carbos a media sesión de pesas no es una recomendación
    // real, es ruido con cara de consejo experto.
    during: long && session.kind === 'endurance' ? { carbs_g_per_hour: FUEL.DURING_G_PER_HOUR } : null,
    after: {
      carbs_g: round(w * FUEL.POST_CARB_G_PER_KG * (easy ? 0.5 : 1), 5),
      protein_g: round(w * FUEL.POST_PROTEIN_G_PER_KG, 5),
      minutes_after: FUEL.POST_MINUTES
    },
    easy
  };
}

// La correlación que docs/PROYECTO_SKANDI_V2.md (Fase 2) pedía y nunca se construyó: "si el
// estancamiento coincide con déficit calórico". `days` es un día por fila de la ventana de la
// racha estancada — `{actual, target}` en kcal, uno por fecha del calendario, con `actual` null
// o 0 si ese día no se registró comida. `target` viene de `targetsForDay()` en el cliente, así
// que ya trae el override del coach si lo hay: esto nunca recalcula la meta, solo la compara.
//
// Cobertura mínima antes de decir nada: un estancamiento junto a dos comidas registradas en
// nueve días no es un patrón, es una coincidencia con cara de dato. Y el umbral en kcal, no en
// porcentaje, porque "15% abajo" en una meta de 1,800 y en una de 3,200 son déficits que no se
// sienten igual — 300 kcal es aproximadamente lo que separa "un día flojo comiendo" de "llevas
// una semana comiendo de menos", en cualquier meta.
const DEFICIT_CONTEXT_MIN_COVERAGE = 0.5;
const DEFICIT_CONTEXT_KCAL_THRESHOLD = 300;
function deficitContext(days){
  const withTarget = (days || []).filter(d => d && d.target);
  if (!withTarget.length) return null;
  const logged = withTarget.filter(d => d.actual > 0);
  const coverage = logged.length / withTarget.length;
  if (coverage < DEFICIT_CONTEXT_MIN_COVERAGE) {
    return { significant: false, coverage, daysLogged: logged.length, daysTotal: withTarget.length };
  }
  const avgDeficit = logged.reduce((sum, d) => sum + (d.target - d.actual), 0) / logged.length;
  return {
    significant: avgDeficit >= DEFICIT_CONTEXT_KCAL_THRESHOLD,
    avgDeficit: Math.round(avgDeficit),
    coverage, daysLogged: logged.length, daysTotal: withTarget.length
  };
}

const api = {
  KCAL_PER_G, ACTIVITY_FACTORS, MODE_FACTOR, MET,
  suggestTargets, kcalFromMacros, itemsTotal, dayTotals, remaining, pct,
  scaleFood, rescaleItem, itemToFood, evaluateFood, evaluateScaled,
  activityKcal, strengthKcal, dayRecommendation, stepsAdjustmentKcal,
  FUEL, fuelPlan,
  isLowEnergy, LOW_ENERGY_KCAL_PER_KG_FLOOR,
  deficitContext, DEFICIT_CONTEXT_MIN_COVERAGE, DEFICIT_CONTEXT_KCAL_THRESHOLD
};

if (typeof module !== 'undefined' && module.exports) module.exports = api;
global.SkandiNutrition = api;

})(typeof globalThis !== 'undefined' ? globalThis : this);
