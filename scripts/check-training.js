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
