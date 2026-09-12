// Skandi Fit — el lastre suma al peso corporal (Fase 0 de
// docs/PREVENCION_LESIONES_HOMBRO_CODO.md). Lo que estas aserciones protegen:
//   1. que meter lastre SUBA la carga calculada y no la baje;
//   2. que sin `bodyweight_share` el cálculo sea idéntico al de antes, porque HABIT carga este
//      mismo motor y su catálogo no tiene esa columna.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const Recovery = require('../skandi-recovery.js');
const JointLoad = require('../skandi-joint-load.js');

const migration = fs.readFileSync('migrations/118_skandi_bodyweight_share.sql', 'utf8');
const skandi = fs.readFileSync('skandi.html', 'utf8');

const BW = 78;                       // peso corporal de ejemplo
const REF = Recovery.SET_WORK_REFERENCE;
const PROXY = Recovery.BODYWEIGHT_KG_PROXY;
const dipSet = {done: true, reps: 8, weight_kg: null};
const weightedDipSet = {done: true, reps: 8, weight_kg: 15};
const share = {bodyweightShare: 1, bodyweightKg: BW};

// ── 1. Compatibilidad: sin opts, exactamente lo de siempre ──────────────────
assert.equal(Recovery.setStimulusUnits(weightedDipSet), 15 * 8 / REF);
assert.equal(Recovery.setStimulusUnits(dipSet), PROXY * 8 / REF);
assert.equal(Recovery.setStimulusUnits({done: false, reps: 8, weight_kg: 15}), 0);
// Un ejercicio sin la columna (o con ella nula) también cae al camino viejo.
assert.equal(Recovery.setStimulusUnits(weightedDipSet, {bodyweightShare: null, bodyweightKg: BW}),
  15 * 8 / REF);

// ── 2. El bug: con lastre tiene que pesar MÁS ───────────────────────────────
const withBelt = Recovery.setStimulusUnits(weightedDipSet, share);
const withoutBelt = Recovery.setStimulusUnits(dipSet, share);
assert.equal(withBelt, (BW + 15) * 8 / REF);
assert.equal(withoutBelt, BW * 8 / REF);
assert.ok(withBelt > withoutBelt, 'lastre suma');
// Y antes del arreglo pasaba lo contrario, por goleada.
assert.ok(Recovery.setStimulusUnits(weightedDipSet) < Recovery.setStimulusUnits(dipSet));

// ── 3. Peso corporal real vs proxy ──────────────────────────────────────────
assert.equal(Recovery.setLoadKg(dipSet, {bodyweightShare: 1}), PROXY);       // sin pesaje
assert.equal(Recovery.setLoadKg(dipSet, share), BW);
assert.equal(Recovery.setLoadKg({weight_kg: 20}, {bodyweightShare: 0.5, bodyweightKg: BW}), BW * 0.5 + 20);
// Holds: 60 s cuentan como 2 repeticiones equivalentes, con el cuerpo entero de carga.
assert.equal(Recovery.setStimulusUnits({done: true, seconds: 60, weight_kg: null}, share), BW * 2 / REF);

// ── 4. De punta a punta: la figura muscular ─────────────────────────────────
const exercises = [
  {id: 'e-dip', slug: 'dips', muscles: {Triceps: 40, Chest: 35, Shoulders: 15, Core: 10}, bodyweight_share: 1},
  {id: 'e-curl', slug: 'dumbbell-curl', muscles: {Biceps: 80, Forearms: 20}, bodyweight_share: null}
];
const now = Date.now();
const sessions = [{id: 'sess', user_id: 'u', completed_at: new Date(now - 3600e3).toISOString()}];
const mkSets = weight => [
  {id: 's1', session_id: 'sess', user_id: 'u', exercise_id: 'e-dip', done: true, reps: 8, weight_kg: weight},
  {id: 's2', session_id: 'sess', user_id: 'u', exercise_id: 'e-curl', done: true, reps: 10, weight_kg: 12}
];
const tricepsOf = sets => Recovery.computeMuscleRecovery({
  sets, sessions, exercises, activities: [], userId: 'u', now, bodyweightKg: BW
}).find(m => m.name === 'Triceps');

assert.ok(tricepsOf(mkSets(15)).fatigue > tricepsOf(mkSets(null)).fatigue,
  'unos fondos lastrados fatigan el tríceps más que los mismos sin lastre');
// El curl no se mueve: su carga es solo la externa, con columna o sin ella.
const biceps = sets => Recovery.computeMuscleRecovery({
  sets, sessions, exercises, activities: [], userId: 'u', now, bodyweightKg: BW
}).find(m => m.name === 'Biceps').fatigue;
assert.equal(biceps(mkSets(15)), biceps(mkSets(null)));

// ── 5. Carga articular (codo en fondos lastrados) ───────────────────────────
const elbowLoad = weight => JointLoad.dailyJointSeries({
  sets: mkSets(weight), sessions, exercises, userId: 'u', joint: 'elbow', bodyweightKg: BW, now
}).reduce((a, r) => a + r.load, 0);
assert.ok(elbowLoad(15) > elbowLoad(null), 'el codo también ve el lastre');
assert.ok(elbowLoad(null) > 0, 'y sigue viendo los fondos sin lastre');

// ── 6. Cableado: la app tiene que pasar el peso corporal ────────────────────
assert.match(migration, /add column if not exists bodyweight_share/);
assert.match(migration, /'weighted-pull-up'/);
assert.match(migration, /'dips'/);
assert.equal((skandi.match(/bodyweightKg:latestWeightKg\(\)/g) || []).length, 3,
  'recuperación, brief y tarjeta de carga pasan el peso corporal');

// Compila el script principal de skandi.html sin ejecutarlo, para que un paréntesis roto en el
// HTML monolítico se caiga aquí y no en el teléfono (mismo truco que check-training.js).
const start = skandi.indexOf('<script>');
const end = skandi.lastIndexOf('</script>');
assert.ok(start >= 0 && end > start, 'script principal de skandi.html encontrado');
new Function(skandi.slice(start + '<script>'.length, end));

console.log('Skandi recuperación: 21 aserciones OK');
