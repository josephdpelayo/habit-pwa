const assert = require('node:assert/strict');
const fs = require('node:fs');
const training = require('../habit-training');

const app = fs.readFileSync('app.html', 'utf8');
const migration = fs.readFileSync('migrations/117_training_reliability_and_admin.sql', 'utf8');

assert.equal(training.metricType({repsType: 'time'}), 'time');
assert.equal(training.metricType({default_tracking: 'reps'}), 'reps');
assert.equal(training.parseSeconds('1:30'), 90);
assert.equal(training.parseSeconds('2 min'), 120);
assert.equal(Math.round(training.estimated1RM(100, 5)), 117);

const merged = training.mergeEntries([], {table: 'coaching_session_sets', id: 's1', patch: {weight: 40}}, 1);
const mergedAgain = training.mergeEntries(merged, {table: 'coaching_session_sets', id: 's1', patch: {done: true}}, 2);
assert.equal(mergedAgain.length, 1);
assert.deepEqual(mergedAgain[0].patch, {weight: 40, done: true});
assert.deepEqual(training.applyPending(mergedAgain, 'coaching_session_sets', [{id: 's1', weight: 20, done: false}])[0],
  {id: 's1', weight: 40, done: true, _pendingSync: true});

assert.equal(training.weeklyStreak(['2026-08-24','2026-08-31'], '2026-09-07', '2026-08-31'), 2);
assert.equal(training.weeklyStreak(['2026-08-31','2026-09-07'], '2026-09-07', '2026-08-31'), 2);

// Icono por patrón de movimiento: lo específico gana a lo genérico.
const pat = name => training.exercisePattern({name});
assert.equal(pat('Dominadas pronas'), 'pull');
assert.equal(pat('Fondos en paralelas'), 'dip');
assert.equal(pat('Pike push up'), 'overhead');
assert.equal(pat('Flexiones de pica'), 'overhead');
assert.equal(pat('Retracción-protracción escapular en flexión (calentamiento)'), 'pushup');
assert.equal(pat('Calentamiento: entrada en calor y movilidad'), 'mobility');
assert.equal(pat('Remadora 500 m'), 'cardio');
assert.equal(pat('Remo con mancuerna'), 'row');
assert.equal(pat('Plancha frontal'), 'core');
assert.equal(pat('Tuck planche'), 'planche');
assert.equal(pat('Flexiones lean planche'), 'planche');
assert.equal(pat('Aguante de 90 grados'), 'planche');
assert.equal(pat('Front press + negativa + aguante'), 'lever');
assert.equal(pat('Touch tuck advanced'), 'lever');
assert.equal(pat('Flexiones de pino libre'), 'handstand');
assert.equal(pat('Retracciones escapulares colgado (calentamiento)'), 'pull');
assert.equal(pat('Abdominal en banco declinado'), 'core');
assert.equal(pat('Press de banca'), 'bench');
assert.equal(pat('Curl femoral'), 'hinge');
assert.equal(pat('Curl de bíceps'), 'arms');
assert.equal(pat('Flexión de cadera con banda'), 'mobility');
assert.equal(pat('Parada de manos contra la pared'), 'handstand');
assert.equal(training.exercisePattern({name: 'Ejercicio X', primary_muscle: 'Cuádriceps'}), 'squat');
assert.equal(training.exercisePattern({name: 'Ejercicio X'}), 'strength');

assert.match(migration, /idx_coaching_schedule_one_active/);
assert.match(migration, /start_training_session/);
assert.match(migration, /exercise_snapshot/);
assert.match(migration, /save_coaching_week/);
assert.match(migration, /guard_profile_privileges/);
assert.match(app, /loadActiveCoachingSessionSb\(\)\.catch/);
assert.match(app, /HabitTraining\.applyPending/);
assert.match(app, /coaching_plan_change_requests/);

// Compila el script principal sin ejecutarlo para detectar llaves, comillas o
// expresiones rotas en el HTML monolítico.
const start = app.indexOf('<script>');
const end = app.lastIndexOf('</script>');
assert.ok(start >= 0 && end > start, 'main inline script found');
new Function(app.slice(start + '<script>'.length, end));

console.log('HABIT Entrenar: 22 assertions OK');
