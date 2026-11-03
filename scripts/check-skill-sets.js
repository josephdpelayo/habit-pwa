// La progresión como carga (migración 146, docs/PROGRAMA_HANDSTAND.md §10).
//
// El caso que esto existe para resolver es el entreno real de Joseph: en una misma sesión de
// front lever el aguante va en straddle, las negativas suben en una pierna y bajan en tuck
// avanzado, y los touch y las dominadas se hacen en tuck. Cuatro escalones de la MISMA línea
// el mismo día. Con una progresión por ejercicio eso no se puede escribir, y la marca de la
// escalera salía adivinada del ex_key; con rung_id por serie sale de la serie misma.
//
// Lo que se prueba:
//   1. qué es un ejercicio de línea y qué no;
//   2. en qué escalón arranca la siguiente serie, y que nunca sea uno fuera de la escalera;
//   3. el objetivo sembrado, incluso cuando la línea mezcla segundos y repeticiones;
//   4. que las marcas salgan separadas por escalón, con las sesiones de la más nueva a la más
//      vieja, que es como readiness() las lee;
//   5. que la 146 traiga la columna y su índice.
const assert = require('node:assert/strict');
const fs = require('node:fs');

global.HabitTraining = require('../habit-training.js');
const S = require('../habit-skills.js');

// ── La escalera de verdad, leída de la 141 ─────────────────────────────────
const ladder = fs.readFileSync('migrations/141_coach_skills.sql', 'utf8');
const rows = [...ladder.matchAll(/^\s*\('front-lever',(\d+),'([a-z0-9-]+)','(time|reps)',(null|\d+),(\d+),$/gm)]
  .map(m => ({
    id: 'id-' + m[2], slug: m[2], name: m[2], progression_group: 'front-lever',
    progression_rank: Number(m[1]), default_tracking: m[3],
    progression_target: m[4] === 'null' ? null : Number(m[4]),
    progression_target_sets: Number(m[5])
  }));
const list = S.rungs(rows, 'front-lever');
assert.equal(list.length, 8, 'la línea de front lever tiene 8 escalones');
const bySlug = s => list.find(r => r.slug === s) || assert.fail('no existe el escalón ' + s);

const TUCK = bySlug('front-lever-tuck');
const ADV = bySlug('front-lever-tuck-avanzado');
const ONE_LEG = bySlug('front-lever-a-una-pierna');
const STRADDLE = bySlug('front-lever-straddle');

// ── 1. Qué es un ejercicio de línea ────────────────────────────────────────
const holdEx = { id: 'ex1', name: 'Aguante de front lever', skillGroup: 'front-lever', sets: 4, rest: '180s' };
const normalEx = { id: 'ex2', name: 'Remo con barra', catalogId: 'abc', sets: 4, reps: '8' };
assert.equal(S.isSkillExercise(holdEx), true);
assert.equal(S.isSkillExercise(normalEx), false);
assert.equal(S.isSkillExercise(null), false);
assert.equal(S.skillGroupOf(holdEx), 'front-lever');
// Un ejercicio que apunta a UNA variante no es de línea: ese ya tiene su progresión decidida.
assert.equal(S.isSkillExercise({ id: 'ex3', catalogId: STRADDLE.id }), false);

// ── 2. Dónde arranca la siguiente serie ────────────────────────────────────
// Lo de esta sesión manda sobre todo lo demás: es el caso de subir y bajar en el mismo día.
assert.equal(S.defaultRung(list, { lastInSession: ADV.id, lastLogged: STRADDLE.id, currentRank: 2 }).slug,
  ADV.slug, 'lo que acabas de hacer manda');
assert.equal(S.defaultRung(list, { lastLogged: STRADDLE.id, currentRank: 2 }).slug,
  STRADDLE.slug, 'si no hay nada en esta sesión, lo último que registraste');
assert.equal(S.defaultRung(list, { currentRank: 3 }).slug, ADV.slug, 'si no, el escalón que llevas');
assert.equal(S.defaultRung(list, {}).progression_rank, 1, 'sin nada, el primero de la escalera');
assert.equal(S.defaultRung([], { currentRank: 3 }), null, 'sin escalera no hay escalón');
// Un id de otra línea (o de un ejercicio borrado) no se cuela.
assert.equal(S.defaultRung(list, { lastInSession: 'id-planche-tuck', currentRank: 4 }).slug, ONE_LEG.slug,
  'un escalón que no es de esta línea se ignora, no revienta');
// Por rank también, que es lo que guarda coach_student_skills.
assert.equal(S.defaultRung(list, { lastInSession: 5 }).slug, STRADDLE.slug);

// ── 3. El objetivo de cada escalón ─────────────────────────────────────────
assert.equal(S.rungTargetText(TUCK), '15s', 'un aguante se siembra en segundos');
assert.equal(S.rungTargetText(bySlug('front-lever-a-un-brazo')), '',
  'el último escalón no tiene estándar: no se siembra nada');
assert.equal(S.rungTargetText(null), '');
// Una línea puede mezclar unidades: en handstand los jalones de talón son repeticiones entre
// aguantes, y cada escalón se siembra con la suya.
const hs = S.rungs([...ladder.matchAll(/^\s*\('handstand',(\d+),'([a-z0-9-]+)','(time|reps)',(null|\d+),(\d+),$/gm)]
  .map(m => ({
    id: 'id-' + m[2], slug: m[2], progression_group: 'handstand', progression_rank: Number(m[1]),
    default_tracking: m[3], progression_target: m[4] === 'null' ? null : Number(m[4]),
    progression_target_sets: Number(m[5])
  })), 'handstand');
assert.equal(S.rungTargetText(S.rungAt(hs, 3)), '60s');
assert.equal(S.rungTargetText(S.rungAt(hs, 4)), '10', 'los jalones de talón son repeticiones');

// ── 4. La sesión de Joseph: cuatro escalones el mismo día ──────────────────
const sesion = 'sched-1';
const set = (rung, i, mark, done = true) => ({
  id: 's' + rung.slug + i, schedule_id: sesion, ex_key: 'ex1', rung_id: rung.id, set_idx: i, done,
  created_at: '2026-11-02T1' + i + ':00:00Z',
  ...(S.markUnit(rung) === 'time' ? { actual_seconds: mark } : { actual_reps: String(mark) })
});
const hoy = [
  set(STRADDLE, 1, 10), set(STRADDLE, 2, 9),          // el aguante, arriba
  set(ONE_LEG, 3, 8), set(ADV, 4, 14),                // negativas: sube y baja
  set(TUCK, 5, 20), set(TUCK, 6, 18)                  // touch y dominadas, abajo
];
const resolve = row => S.rungById(list, row.rung_id);
const marks = S.marksFromRows(hoy, resolve);
assert.deepEqual(Object.keys(marks), ['front-lever'], 'una sola línea');
const fl = marks['front-lever'];
assert.deepEqual(Object.keys(fl).map(Number).sort((a, b) => a - b), [2, 3, 4, 5],
  'cuatro escalones distintos en la misma sesión, cada uno con su marca');
assert.equal(fl[5].mark, 10, 'el straddle guarda su mejor serie, no la del tuck');
assert.equal(fl[2].mark, 20, 'y el tuck la suya');
assert.equal(fl[3].mark, 14);
assert.equal(fl[4].mark, 8);

// Una serie sin palomear no es marca, aunque traiga segundos.
const conFallo = S.marksFromRows([...hoy, set(STRADDLE, 7, 30, false)], resolve);
assert.equal(conFallo['front-lever'][5].mark, 10, 'una serie sin palomear no sube la marca');

// Las sesiones llegan de la más nueva a la más vieja.
const ayer = hoy.map(r => ({ ...r, id: r.id + 'b', schedule_id: 'sched-0', created_at: '2026-10-26T10:00:00Z' }));
const dos = S.marksFromRows([...ayer, ...hoy], resolve);
assert.deepEqual(dos['front-lever'][5].sessions.map(s => s.id), [sesion, 'sched-0'],
  'la sesión más reciente primero: readiness() lee en ese orden');

// Y esto es lo que desbloquea el estándar: dos sesiones seguidas cumpliendo en el escalón.
// El straddle pide 2 series de 12 s y hoy hizo 10 y 9, así que todavía no.
assert.equal(S.readiness(list, 5, dos['front-lever'][5].sessions).ready, false,
  '10 s no cumple un estándar de 12 s');
const bueno = [1, 2].map(i => set(STRADDLE, i, 12));
const dosBuenas = S.marksFromRows(
  [...bueno, ...bueno.map(r => ({ ...r, id: r.id + 'b', schedule_id: 'sched-0', created_at: '2026-10-26T10:00:00Z' }))],
  resolve);
assert.equal(S.readiness(list, 5, dosBuenas['front-lever'][5].sessions).ready, true,
  'dos sesiones seguidas con 2 × 12 s sí cumplen');

// Una serie suelta (sin sesión) cuenta como suya, no se mezcla con otra.
const sueltas = S.marksFromRows(
  [{ ...set(TUCK, 1, 20), schedule_id: null }, { ...set(TUCK, 2, 22), schedule_id: null }], resolve);
assert.equal(sueltas['front-lever'][2].sessions.length, 2, 'dos series sueltas son dos sesiones');

// Una fila cuyo escalón no se puede resolver se ignora en silencio: las series viejas no
// tienen rung_id y no deben tumbar el cálculo.
assert.deepEqual(S.marksFromRows([{ ...set(TUCK, 1, 20), rung_id: null }], resolve), {});

// ── 5. La migración ────────────────────────────────────────────────────────
const sql = fs.readFileSync('migrations/146_set_progression.sql', 'utf8');
assert.match(sql, /add column if not exists rung_id uuid references public\.exercise_catalog\(id\) on delete set null/,
  'la serie guarda su escalón, y borrar un ejercicio no borra la historia');
assert.match(sql, /create index if not exists idx_coaching_session_sets_rung/);

console.log('HABIT progresión por serie: 4 escalones de front lever en una sesión, marcas separadas OK');
