// Programa «Parada de manos en 8 semanas» (migración 145, docs/PROGRAMA_HANDSTAND.md). Lo que
// estas aserciones protegen:
//   1. que cada sesión quepa de verdad en 20 minutos (series × (trabajo + descanso));
//   2. que la prueba de cada fase sea el escalón de la escalera que dice el programa, y que el
//      número que promete su nota («el estándar es 60 s») sea el objetivo de ese escalón;
//   3. que cada texto nuevo venga en español y en inglés, con los mismos cues (requisito
//      permanente de CLAUDE.md);
//   4. que todo ejercicio exista en el catálogo y tenga su figura;
//   5. la lógica pura: por dónde entra cada quien, la fecha de inicio y «repetir la fase».
const assert = require('node:assert/strict');
const fs = require('node:fs');

global.HabitTraining = require('../habit-training.js');
const Skills = require('../habit-skills.js');
const P = Skills.HANDSTAND_PROGRAM;

const sql = fs.readFileSync('migrations/145_handstand_program.sql', 'utf8');
const ladder = fs.readFileSync('migrations/141_coach_skills.sql', 'utf8');
const unq = s => s.replace(/''/g, "'");

// ── Lo que dice la migración ───────────────────────────────────────────────
const boards = [...sql.matchAll(/^\s*\('(\d[abc])',\s*(\d),\s*'([ABC])',\s*'([^']+)',\s*'([^']+)',\s*'(basico|intermedio|avanzado)'\)/gm)]
  .map(m => ({key: m[1], phase: Number(m[2]), kind: m[3], name: m[4], name_en: m[5]}));
assert.equal(boards.length, 12, 'doce rutinas: 4 fases × A/B/C');
for (const ph of [1, 2, 3, 4]) {
  assert.deepEqual(boards.filter(b => b.phase === ph).map(b => b.kind), ['A', 'B', 'C'], `fase ${ph}: A, B y C`);
}

const NOTE = "E'((?:[^']|'')*)'";
const prep = [...sql.matchAll(new RegExp(`^\\s*\\((\\d), '([a-z0-9-]+)', '(\\d+)', '([^']+)', '([^']+)',\\s*\\n\\s*${NOTE},\\s*\\n\\s*${NOTE}\\)`, 'gm'))]
  .map(m => ({ord: Number(m[1]), slug: m[2], sets: m[3], reps: m[4], repsType: 'time', rest: m[5], note: unq(m[6]), note_en: unq(m[7])}));
assert.deepEqual(prep.map(p => p.slug), ['preparacion-de-munecas', 'apertura-de-hombros-en-pared'],
  'la preparación de muñecas y hombros abre todas las sesiones');

const rows = [...sql.matchAll(new RegExp(`^\\s*\\('(\\d[abc])', (\\d+), '([a-z0-9-]+)', '(\\d+)', '([^']+)', '(time|reps)', '([^']+)',\\s*\\n\\s*${NOTE},\\s*\\n\\s*${NOTE}\\)`, 'gm'))]
  .map(m => ({board: m[1], ord: Number(m[2]), slug: m[3], sets: m[4], reps: m[5], repsType: m[6], rest: m[7], note: unq(m[8]), note_en: unq(m[9])}));
assert.ok(rows.length >= 40, 'se leyeron los ejercicios de las rutinas, salieron ' + rows.length);

const exercisesOf = key => [...prep, ...rows.filter(r => r.board === key)].sort((a, b) => a.ord - b.ord);

// ── 1. Veinte minutos ──────────────────────────────────────────────────────
// Más 15 s de transición por ejercicio: cambiar de posición también es tiempo.
for (const b of boards) {
  const list = exercisesOf(b.key);
  assert.deepEqual(list.map(e => e.ord), list.map((_, i) => i + 1), `${b.key}: orden seguido desde 1`);
  assert.equal(new Set(list.map(e => e.slug)).size, list.length,
    `${b.key}: un ejercicio una sola vez (su id es el mismo en las 12 rutinas)`);
  const min = (Skills.sessionSeconds(list) + 15 * list.length) / 60;
  assert.ok(min <= P.minutes, `${b.key} dura ${min.toFixed(1)} min: no cabe en ${P.minutes}`);
  assert.ok(min >= 10, `${b.key} dura ${min.toFixed(1)} min: muy corta para ser la sesión del día`);
}

// ── 2. La prueba de cada fase es su escalón ────────────────────────────────
const rungs = [...ladder.matchAll(/^\s*\('handstand',(\d+),'([a-z0-9-]+)','(time|reps)',(null|\d+),(\d+),$/gm)]
  .map(m => ({rank: Number(m[1]), slug: m[2], unit: m[3], target: m[4] === 'null' ? null : Number(m[4]), sets: Number(m[5])}));
assert.equal(rungs.length, 7, 'la escalera de parada de manos tiene 7 escalones');
for (const phase of P.phases) {
  const rung = rungs.find(r => r.rank === phase.rank);
  assert.ok(rung && rung.target, `fase ${phase.n}: el escalón ${phase.rank} tiene que tener estándar`);
  const test = rows.find(r => r.board === phase.n + 'c' && r.slug === rung.slug);
  assert.ok(test, `${phase.n}C tiene que medir ${rung.slug} (escalón ${phase.rank})`);
  assert.equal(test.reps, 'max', `${phase.n}C: la prueba es un máximo, no un objetivo`);
  assert.ok(Number(test.sets) >= rung.sets, `${phase.n}C: hacen falta al menos ${rung.sets} series para medir el estándar`);
  const promised = test.note.match(/estándar es (?:\d+ series de )?(\d+)/);
  assert.ok(promised, `${phase.n}C: la nota de la prueba dice el estándar`);
  assert.equal(Number(promised[1]), rung.target, `${phase.n}C: la nota promete ${promised[1]} y el escalón pide ${rung.target}`);
  assert.match(test.note, /^PRUEBA/, `${phase.n}C: la prueba empieza con PRUEBA, que es lo que se lee en la hoja`);
  // Y lo que la app compara al cerrar la sesión es ese mismo estándar.
  const r = {progression_target: rung.target, progression_target_sets: rung.sets, default_tracking: rung.unit};
  const hit = Array.from({length: rung.sets}, () => rung.unit === 'time'
    ? {done: true, actual_seconds: rung.target} : {done: true, actual_reps: String(rung.target)});
  assert.equal(Skills.meetsStandard(r, hit).passed, true, `${phase.n}C: cumplir el estándar pasa la prueba`);
  assert.equal(Skills.meetsStandard(r, hit.slice(1)).passed, false, `${phase.n}C: una serie de menos no pasa`);
}
// Solo las C llevan prueba.
for (const r of rows) {
  if (r.note.startsWith('PRUEBA')) assert.match(r.board, /c$/, `${r.board}: solo las sesiones C son prueba`);
}

// ── 3. Español e inglés ────────────────────────────────────────────────────
for (const b of boards) assert.ok(b.name_en && !/[áéíóúñ]/i.test(b.name_en), `${b.key}: nombre en inglés`);
for (const r of [...prep, ...rows]) {
  assert.ok(r.note && r.note_en, `${r.board || 'prep'} ${r.slug}: cues en los dos idiomas`);
  assert.equal(Skills.cueList(r.note).length, Skills.cueList(r.note_en).length,
    `${r.board || 'prep'} ${r.slug}: el inglés tiene que traer los mismos cues que el español`);
}
const newSlugs = [...sql.matchAll(/^\s*\('[^']+','([a-z0-9-]+)','(?:Movilidad|Calistenia)'/gm)].map(m => m[1]);
assert.equal(newSlugs.length, 10, 'diez ejercicios nuevos');
const enInstr = (sql.match(/^\s*'[A-Z][^']*(?:''[^']*)*',\n\s*'\/skill-anim\//gm) || []).length;
assert.equal(enInstr, 10, 'cada ejercicio nuevo trae sus instrucciones en inglés');
assert.match(sql, /name_en/);
assert.match(sql, /'Parada de manos en 8 semanas', 'Handstand in 8 weeks'/);

// ── 4. Catálogo y figuras ──────────────────────────────────────────────────
// Cada ejercicio es uno nuevo de la 145 o uno que ya existía: un escalón de la 141 o lo que
// trajeron la 037 y la 071.
const known = new Set([
  ...newSlugs, ...rungs.map(r => r.slug),
  ...[...fs.readFileSync('migrations/037_exercise_catalog.sql', 'utf8').matchAll(/\('[^']+','([a-z0-9-]+)','/g)].map(m => m[1]),
  ...[...fs.readFileSync('migrations/071_import_skandi_exercise_catalog.sql', 'utf8').matchAll(/\('[a-z0-9-]+','[^']+','([a-z0-9-]+)'\)/g)].map(m => m[1])
]);
const used = new Set([...prep, ...rows].map(r => r.slug));
for (const slug of used) {
  assert.ok(known.has(slug), `${slug} no existe en ninguna migración del catálogo`);
  assert.ok(fs.existsSync(`skill-anim/${slug}.svg`), `${slug} no tiene figura (skill-anim/${slug}.svg)`);
}
for (const m of sql.matchAll(/'\/skill-anim\/([a-z0-9-]+)\.svg'/g)) {
  assert.ok(fs.existsSync(`skill-anim/${m[1]}.svg`), `la 145 enlaza ${m[1]}.svg y no existe`);
}

// Un objetivo de tiempo es un número, no un rango: palomear sin escribir guarda ese número.
for (const r of [...prep, ...rows]) {
  if (r.repsType !== 'time' || r.reps === 'max') continue;
  assert.ok(HabitTraining.parseSeconds(r.reps), `${r.board || 'prep'} ${r.slug}: "${r.reps}" no se lee como segundos`);
}
for (const r of [...prep, ...rows]) {
  assert.match(r.rest, /^\d+s$/, `${r.board || 'prep'} ${r.slug}: el descanso va en segundos ("90s"); "1:30" se leería 1 s`);
}

// ── 5. Lógica pura ─────────────────────────────────────────────────────────
assert.equal(P.weeks, P.phases.length * P.weeksPerPhase, '8 semanas = 4 fases × 2');
assert.match(sql, new RegExp(`generate_series\\(1, ${P.weeks}\\)`), 'la migración estampa las mismas semanas');
assert.match(sql, /\(0, 'A'\), \(1, 'B'\), \(2, 'A'\), \(3, 'B'\), \(4, 'A'\), \(5, 'C'\)/, 'lunes a sábado: A B A B A C');
assert.deepEqual([1, 2, 3, 4, 5, 6, 7, 8].map(w => Skills.programPhase(P, w).n), [1, 1, 2, 2, 3, 3, 4, 4]);
assert.equal(Skills.programPhase(P, 0), null, 'semana 0: el ciclo no empezó');
assert.equal(Skills.programPhase(P, -1), null, 'semana -1: el ciclo terminó');
assert.equal(Skills.programPhase(P, 9), null);
assert.deepEqual([1, 2, 3, 4, 5, 6, 7, 8].map(w => Skills.isPhaseTestWeek(P, w)), [false, true, false, true, false, true, false, true]);
// Entrada por nivel (§4): el escalón en el que va → la primera semana de su fase.
assert.deepEqual([1, 2, 3, 4, 5, 6, 7].map(r => Skills.placementWeek(P, r)), [1, 3, 3, 5, 7, 7, 7]);
assert.equal(Skills.placementWeek(P, 0), 1, 'sin escalón, desde el principio');
// Entrar en la semana 5 es un programa que empezó cuatro semanas antes.
assert.equal(Skills.programStartDate('2026-11-09', 1), '2026-11-09');
assert.equal(Skills.programStartDate('2026-11-09', 5), '2026-10-12');
assert.equal(Skills.addDaysIso('2026-12-28', 7), '2027-01-04', 'cruza el año');
assert.equal(Skills.repeatPhaseStartDate(P, '2026-10-12'), '2026-10-26', 'repetir la fase corre el inicio una fase');
// Un aguante sin marcar no cuenta para la prueba, aunque traiga segundos escritos.
assert.equal(Skills.meetsStandard({progression_target: 60, progression_target_sets: 1, default_tracking: 'time'},
  [{done: false, actual_seconds: 70}]).passed, false);
assert.equal(Skills.meetsStandard({progression_target: null}, [{done: true, actual_seconds: 99}]).passed, false,
  'un escalón sin estándar no se puede «pasar»');

// ── 6. Las figuras nuevas: lo que pide cada posición ───────────────────────
// Igual que las de las escaleras (check-skills.js §9): los puntos de referencia (data-j) en la
// posición dibujada, y la alineación que define el ejercicio.
const joints = slug => {
  const j = {};
  const svg = fs.readFileSync(`skill-anim/${slug}.svg`, 'utf8');
  for (const m of svg.matchAll(/<circle cx="(-?[\d.]+)" cy="(-?[\d.]+)" r="([\d.]+)" fill="#a78bfa" data-j="(\w+)"\/>/g)) {
    j[m[4]] = {x: Number(m[1]), y: Number(m[2])};
  }
  for (const n of ['hand', 'shoulder', 'hip', 'knee', 'foot']) assert.ok(j[n], `${slug}: falta el punto ${n}`);
  assert.match(svg, /<animate(Transform)? /, `${slug}: la figura tiene que moverse (aunque sea apenas)`);
  return j;
};
const TOL = 0.6;
const eq = (a, b, what) => assert.ok(Math.abs(a - b) <= TOL, `${what} (${a} vs ${b})`);
const collinear = (slug, j, names) => {
  const a = j[names[0]], b = j[names[1]], len = Math.hypot(b.x - a.x, b.y - a.y);
  for (const n of names.slice(2)) {
    const off = Math.abs((b.x - a.x) * (j[n].y - a.y) - (b.y - a.y) * (j[n].x - a.x)) / len;
    assert.ok(off <= 0.8, `${slug}: ${n} se sale de la recta ${names.join('-')} por ${off.toFixed(1)}`);
  }
};
{
  const s = 'preparacion-de-munecas', j = joints(s);
  eq(j.hand.x, j.shoulder.x, `${s}: el hombro arranca sobre la muñeca`);
  eq(j.knee.x, j.hip.x, `${s}: la rodilla bajo la cadera`);
  eq(j.knee.y, j.hand.y, `${s}: rodilla y mano en el piso`);
  eq(j.foot.y, j.hand.y, `${s}: el empeine en el piso`);
}
{
  const s = 'apertura-de-hombros-en-pared', j = joints(s);
  eq(j.hand.y, j.shoulder.y, `${s}: brazos en línea con el torso`);
  eq(j.hip.y, j.shoulder.y, `${s}: torso horizontal, cadera a 90°`);
  eq(j.knee.x, j.hip.x, `${s}: piernas verticales`);
  eq(j.foot.x, j.hip.x, `${s}: piernas verticales`);
}
{
  const s = 'hollow-hold', j = joints(s);
  collinear(s, j, ['hand', 'shoulder', 'hip']);
  collinear(s, j, ['hip', 'knee', 'foot']);
  assert.ok(j.hip.y > j.shoulder.y + 8 && j.hip.y > j.foot.y + 20, `${s}: la lumbar abajo, hombros y piernas despegados`);
}
{
  const s = 'encogimientos-en-pica', j = joints(s);
  collinear(s, j, ['hand', 'shoulder', 'hip']);
  collinear(s, j, ['hip', 'knee', 'foot']);
  eq(j.foot.y, j.hand.y, `${s}: manos y pies en el piso`);
  assert.ok(j.hip.y < j.shoulder.y, `${s}: la cadera arriba`);
}
{
  const s = 'parada-de-rana', j = joints(s);
  assert.ok(Math.abs(j.knee.x - j.hand.x) <= 6, `${s}: la rodilla apoyada sobre el brazo, encima de la mano`);
  assert.ok(j.foot.y < j.hand.y - 25, `${s}: los pies despegados`);
  assert.ok(j.shoulder.x > j.hand.x, `${s}: los hombros adelante de las manos`);
}
{
  const s = 'patadas-de-conejo', j = joints(s);
  eq(j.hand.x, j.shoulder.x, `${s}: brazos bloqueados en vertical`);
  assert.ok(j.hip.y < j.shoulder.y, `${s}: arriba, la cadera por encima de los hombros`);
  assert.ok(Math.abs(j.knee.x - j.hip.x) > 20, `${s}: rodillas dobladas`);
}
{
  const s = 'salida-en-rueda', j = joints(s);
  eq(j.hand.x, j.shoulder.x, `${s}: de frente, la mano bajo su hombro`);
  assert.match(fs.readFileSync(`skill-anim/${s}.svg`, 'utf8'), /<g>[\s\S]*<g>/, `${s}: el giro de la pierna va dentro del del cuerpo`);
}
for (const s of ['caminata-en-pared', 'patada-a-la-pared', 'patada-al-equilibrio',
  'toques-de-hombro-en-pared', 'encogimientos-de-frente-a-la-pared']) {
  const j = joints(s);
  eq(j.hand.x, j.shoulder.x, `${s}: arriba, el hombro apilado sobre la muñeca`);
  collinear(s, j, ['shoulder', 'hip', 'knee', 'foot']);
}
for (const s of ['patada-al-equilibrio', 'toques-de-hombro-en-pared', 'encogimientos-de-frente-a-la-pared']) {
  const j = joints(s);
  eq(j.foot.x, j.shoulder.x, `${s}: libre o de frente a la pared, todo en una vertical`);
}

// ── 7. Lo que la 145 cierra de paso ────────────────────────────────────────
assert.match(sql, /revoke execute on function public\.apply_coaching_program\(uuid, uuid, date, date, date\) from anon/);
assert.match(sql, /revoke execute on function public\.ensure_coaching_week_from_template\(uuid, date\) from anon/);

console.log(`HABIT handstand: ${boards.length} rutinas, ${rows.length + prep.length * 12} ejercicios programados, todas en ≤ ${P.minutes} min`);
