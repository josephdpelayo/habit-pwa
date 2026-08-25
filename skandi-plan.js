// Skandi Fit — resistencia estructurada. Matemáticas puras: sin DOM y sin Supabase, igual que
// skandi-recovery.js / skandi-load.js. Recibe un `structure` jsonb (la lista de pasos de un
// entrenamiento) y devuelve totales, una etiqueta corta y un ritmo real cuando hay umbrales.
// Se prueba desde Node:
//   node -e "const P=require('./skandi-plan.js'); console.log(P.expand(P.parse('series 6x400m Z4 rest 90s Z1').steps))"
//
// Por qué jsonb y no una tabla `skandi_workout_steps` (docs/PLAN_ENTRENAMIENTO_SKANDI.md §4):
// un entrenamiento estructurado siempre se lee y se escribe completo, nunca se consulta "todos
// los intervalos de mi historia". Este módulo es el único lugar que entiende ese jsonb.
//
// `parse(text)` no está en el documento original: existe porque construir un editor de pasos
// campo por campo es una pantalla más que nadie iba a abrir en un teléfono a bordo. Una línea
// de texto por paso —el mismo patrón que ya usa la app para comida en texto libre— es lo que
// de verdad se teclea entre remos.

(function(global){
'use strict';

const Recovery = (typeof module !== 'undefined' && module.exports)
  ? require('./skandi-recovery.js')
  : global.SkandiRecovery;

const KINDS = ['warmup','steady','interval','tempo','recovery','cooldown','station'];

// Alias en español y variantes cortas -> el kind canónico que vive en el jsonb. Sin esto, a
// bordo sin internet nadie va a acordarse de teclear "warmup" en inglés.
const KIND_ALIASES = {
  warmup:'warmup', calentamiento:'warmup', calienta:'warmup',
  steady:'steady', constante:'steady', rodaje:'steady', suave:'steady',
  interval:'interval', intervalo:'interval', intervalos:'interval', series:'interval', serie:'interval',
  tempo:'tempo',
  recovery:'recovery', recuperacion:'recovery', recuperación:'recovery', trote:'recovery',
  cooldown:'cooldown', enfriamiento:'cooldown', enfria:'cooldown',
  station:'station', estacion:'station', estación:'station'
};

// RPE por tipo de paso cuando no hay zona (§6 del plan: sRPE de Foster para todo). Warmup y
// cooldown son casi siempre trote suave; interval y station son el esfuerzo alto de la sesión.
const RPE_BY_KIND = { warmup:3, recovery:3, cooldown:3, steady:5, tempo:7, interval:8, station:7 };

// Factor sobre el ritmo/potencia umbral por zona. Números más altos de sec/km = más lento, así
// que Z1 es el factor más grande y Z5 el más chico — al revés que en potencia, donde Z5 es el
// factor más grande. Aproximación estándar de entrenamiento por zonas (McMillan / Coggan), no
// una medición propia: sin potenciómetro ni prueba de laboratorio, esto es lo mejor disponible.
const RUN_PACE_FACTOR = [1.29, 1.16, 1.06, 1.00, 0.90];   // x umbral sec/km, Z1..Z5
const SWIM_PACE_FACTOR = [1.24, 1.13, 1.05, 1.00, 0.92];  // x CSS sec/100m, Z1..Z5
const BIKE_POWER_FACTOR = [0.50, 0.65, 0.82, 0.98, 1.15]; // x FTP watts, Z1..Z5

function clampZone(z){
  const n = Number(z);
  return (Number.isInteger(n) && n >= 1 && n <= 5) ? n : null;
}

function rpeForStep(step, zones){
  const zone = clampZone(step && step.zone);
  if (zone) return Recovery.ZONE_INTENSITY[zone - 1];
  return RPE_BY_KIND[step && step.kind] || 5;
}

// Segundos/km, segundos/100m o watts para una zona, según la disciplina — o null si no hay
// umbral guardado (skandi_settings.run_threshold_sec_km / swim_css_sec_100m / bike_ftp_w) o la
// disciplina no tiene noción de ritmo (fuerza, HIIT por rondas, movilidad).
function paceValueFor(zone, discipline, zones){
  const z = clampZone(zone);
  if (!z || !zones) return null;
  if (discipline === 'run' && zones.runThresholdSecKm) {
    return { kind:'pace', unit:'/km', sec: Math.round(zones.runThresholdSecKm * RUN_PACE_FACTOR[z - 1]) };
  }
  if (discipline === 'swim' && zones.swimCssSec100m) {
    return { kind:'pace', unit:'/100m', sec: Math.round(zones.swimCssSec100m * SWIM_PACE_FACTOR[z - 1]) };
  }
  if (discipline === 'bike' && zones.bikeFtpW) {
    return { kind:'power', unit:'W', watts: Math.round(zones.bikeFtpW * BIKE_POWER_FACTOR[z - 1]) };
  }
  return null;
}

function fmtMinSec(totalSec){
  const s = Math.round(totalSec);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

// "4:35/km", "1:52/100m", "182W" — o null cuando no hay umbral cargado, y entonces quien llama
// se cae a mostrar la zona a secas ("Z4"), como ya hacía la app antes de este módulo.
function paceFor(zone, discipline, zones){
  const v = paceValueFor(zone, discipline, zones);
  if (!v) return null;
  return v.kind === 'power' ? `${v.watts}W` : `${fmtMinSec(v.sec)}${v.unit}`;
}

// Minutos de un paso: los que trae explícitos, o los que se derivan de distancia/reps cuando
// hay umbral para convertir ritmo -> tiempo. Nunca las dos cosas a la vez: un paso trae
// duración O distancia (§4), así que aquí solo se llena el hueco, no se contradice lo que ya
// está.
function stepMinutes(step, discipline, zones){
  if (Number.isFinite(step.min)) return step.min;
  const distM = Number(step.dist_m);
  if (!distM) return 0;
  const v = paceValueFor(step.zone, discipline, zones);
  if (!v || v.kind !== 'pace') return 0; // sin umbral no se inventa un tiempo
  const units = discipline === 'swim' ? distM / 100 : distM / 1000;
  return (units * v.sec) / 60;
}

function stepDistanceKm(step, discipline){
  const distM = Number(step.dist_m);
  if (!distM) return 0;
  return discipline === 'swim' ? 0 : distM / 1000; // el total en km es de disciplinas terrestres; nado se lee en metros
}

// sRPE de un solo paso (minutos x esfuerzo), reps incluidas. Es la misma moneda que
// skandi-load.js usa para todo lo demás (§6: "una sola moneda de carga").
function estimateLoad(step, opts){
  opts = opts || {};
  const reps = Math.max(1, Number(step.reps) || 1);
  const minutesPerRep = stepMinutes(step, opts.discipline, opts.zones);
  const restMin = step.rest ? (Number(step.rest.min) || 0) : 0;
  const workLoad = reps * minutesPerRep * rpeForStep(step, opts.zones);
  // El descanso entre repeticiones no es cero: sigue siendo tiempo de sesión, a un esfuerzo
  // bajo fijo (RPE 2) salvo que el propio descanso traiga su zona.
  const restLoad = step.rest ? reps * restMin * (clampZone(step.rest.zone) ? Recovery.ZONE_INTENSITY[clampZone(step.rest.zone) - 1] : 2) : 0;
  return Math.round(workLoad + restLoad);
}

// El total de un entrenamiento estructurado: duración, distancia y carga, sumando cada paso
// las veces que se repite. `opts.discipline` es la de la fila del calendario (run/bike/swim/…);
// sin ella no se puede convertir distancia a tiempo, y el total de duración solo cuenta los
// pasos que ya traían minutos explícitos.
function expand(structure, opts){
  opts = opts || {};
  const steps = Array.isArray(structure) ? structure : [];
  let durationMin = 0, distanceKm = 0, load = 0;
  steps.forEach(step => {
    const reps = Math.max(1, Number(step.reps) || 1);
    const minutesPerRep = stepMinutes(step, opts.discipline, opts.zones);
    const restMin = step.rest ? (Number(step.rest.min) || 0) : 0;
    durationMin += reps * (minutesPerRep + restMin);
    distanceKm += reps * stepDistanceKm(step, opts.discipline);
    load += estimateLoad(step, opts);
  });
  return {
    duration_min: Math.round(durationMin),
    distance_km: Math.round(distanceKm * 100) / 100,
    load,
    steps
  };
}

// Una línea para una celda de calendario: "6×400 Z4 · 45 min". Solo números y unidades, nunca
// palabras traducidas — la regla de siempre es que la matemática no decide el idioma.
function label(structure){
  const steps = Array.isArray(structure) ? structure : [];
  if (!steps.length) return '';
  // El paso "más grande" es el que manda el titular: el primer interval/tempo/station: si no
  // hay ninguno, el primer paso con distancia o duración.
  const main = steps.find(s => s.kind === 'interval' || s.kind === 'tempo' || s.kind === 'station')
    || steps.find(s => s.dist_m || s.min)
    || steps[0];
  const parts = [];
  if (main) {
    const reps = Number(main.reps) || 0;
    if (reps > 1 && main.dist_m) parts.push(`${reps}×${main.dist_m}${main.dist_m >= 1000 ? 'km' : 'm'}`.replace('1000m','1km'));
    else if (reps > 1 && main.min) parts.push(`${reps}×${main.min}'`);
    else if (main.dist_m) parts.push(main.dist_m >= 1000 ? `${main.dist_m / 1000}km` : `${main.dist_m}m`);
    else if (main.min) parts.push(`${main.min}'`);
    if (main.zone) parts.push(`Z${main.zone}`);
  }
  const total = expand(structure);
  if (total.duration_min) parts.push(`${total.duration_min} min`);
  return parts.join(' · ');
}

// ---- El mini-DSL de texto libre: una línea por paso -------------------------------------
//
// "series 6x400m Z4 rest 90s Z1"  ->  {kind:'interval', reps:6, dist_m:400, zone:4,
//                                       rest:{min:1.5, zone:1}}
// "calentamiento 10min Z1"        ->  {kind:'warmup', min:10, zone:1}
// "estacion sled push 50m"        ->  {kind:'station', name:'sled push', dist_m:50}
//
// No lanza excepciones: una línea que no calza se reporta en `errors` con su número de línea y
// se ignora, para que el resto del entrenamiento sí se guarde. Un entrenamiento a medio
// teclear no debería perder lo que sí se entendió.
function parseAmount(tok){
  if (!tok) return {};
  let m = tok.match(/^(\d+(?:\.\d+)?)(min|m|km|s|')$/i);
  if (!m) return null;
  const n = Number(m[1]);
  const unit = m[2].toLowerCase();
  if (unit === 'min' || unit === "'") return { min: n };
  if (unit === 's') return { min: n / 60 };
  if (unit === 'km') return { dist_m: Math.round(n * 1000) };
  if (unit === 'm') return { dist_m: Math.round(n) };
  return null;
}

function parseZoneToken(tok){
  const m = tok && tok.match(/^Z([1-5])$/i);
  return m ? Number(m[1]) : null;
}

function parseLine(line){
  const raw = line.replace(/#.*/, '').trim();
  if (!raw) return null;
  const tokens = raw.split(/\s+/);
  const kindWord = tokens[0].toLowerCase().replace(/[^a-záéíóúñ]/gi, '');
  const kind = KIND_ALIASES[kindWord];
  if (!kind) return { error: `tipo de paso desconocido: "${tokens[0]}"` };

  if (kind === 'station') {
    // "estacion sled push 50m" — todo entre el kind y el último token (una distancia) es el
    // nombre; si no hay un token de distancia al final, el nombre es todo lo que sigue.
    const rest = tokens.slice(1);
    const lastAmount = rest.length ? parseAmount(rest[rest.length - 1]) : null;
    if (lastAmount && lastAmount.dist_m) {
      return { step: { kind, name: rest.slice(0, -1).join(' ') || null, dist_m: lastAmount.dist_m } };
    }
    return { step: { kind, name: rest.join(' ') || null } };
  }

  // "6x400m" ó "6x90s" como segundo token: reps explícitas.
  let reps = null, amountTok = tokens[1];
  const repsMatch = tokens[1] && tokens[1].match(/^(\d+)[x×](.+)$/i);
  if (repsMatch) { reps = Number(repsMatch[1]); amountTok = repsMatch[2]; }

  const amount = parseAmount(amountTok);
  if (!amount) return { error: `no entendí la duración/distancia en: "${raw}"` };

  const step = { kind, ...amount };
  if (reps) step.reps = reps;

  let i = repsMatch ? 2 : 2;
  const zone = parseZoneToken(tokens[i]);
  if (zone) { step.zone = zone; i++; }

  if (tokens[i] && tokens[i].toLowerCase() === 'rest') {
    const restAmount = parseAmount(tokens[i + 1]);
    if (restAmount) {
      step.rest = { min: restAmount.min || 0 };
      const restZone = parseZoneToken(tokens[i + 2]);
      if (restZone) step.rest.zone = restZone;
    }
  }

  return { step };
}

function parse(text){
  const lines = String(text || '').split('\n');
  const steps = [], errors = [];
  lines.forEach((line, i) => {
    const result = parseLine(line);
    if (!result) return; // línea vacía
    if (result.error) errors.push({ line: i + 1, message: result.error, text: line });
    else steps.push(result.step);
  });
  return { steps, errors };
}

// El texto de vuelta a partir del jsonb, para poder reabrir y editar lo que ya se guardó sin
// perder el formato de línea por paso.
function toText(structure){
  const steps = Array.isArray(structure) ? structure : [];
  return steps.map(s => {
    if (s.kind === 'station') {
      return ['estacion', s.name, s.dist_m ? `${s.dist_m}m` : ''].filter(Boolean).join(' ');
    }
    const amount = s.dist_m ? `${s.dist_m}m` : `${s.min}min`;
    const parts = [s.kind, s.reps > 1 ? `${s.reps}x${amount}` : amount];
    if (s.zone) parts.push(`Z${s.zone}`);
    if (s.rest) parts.push('rest', `${Math.round((s.rest.min || 0) * 60)}s`, ...(s.rest.zone ? [`Z${s.rest.zone}`] : []));
    return parts.join(' ');
  }).join('\n');
}

const api = {
  KINDS, RUN_PACE_FACTOR, SWIM_PACE_FACTOR, BIKE_POWER_FACTOR,
  expand, label, paceFor, estimateLoad,
  parse, parseLine, toText
};

if (typeof module !== 'undefined' && module.exports) module.exports = api;
global.SkandiPlan = api;

})(typeof globalThis !== 'undefined' ? globalThis : this);
