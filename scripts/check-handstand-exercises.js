// Los ejercicios de parada de manos (migración 145, docs/PROGRAMA_HANDSTAND.md). Lo que estas
// aserciones protegen, ahora que la 145 es contenido y no un programa:
//   1. que los diez ejercicios nuevos existan con su figura y sus dos idiomas;
//   2. que cada figura dibuje de verdad la alineación que define el ejercicio, leyendo sus
//      puntos de referencia (igual que check-skills.js §9 con los 35 escalones);
//   3. que el revoke a anon vaya guardado, porque una firma que no exista tumba la migración.
const assert = require('node:assert/strict');
const fs = require('node:fs');

const sql = fs.readFileSync('migrations/145_handstand_exercises.sql', 'utf8');

// ── 1. Los diez ejercicios nuevos ──────────────────────────────────────────
const NUEVOS = ['preparacion-de-munecas', 'apertura-de-hombros-en-pared', 'encogimientos-en-pica',
  'patadas-de-conejo', 'salida-en-rueda', 'caminata-en-pared',
  'encogimientos-de-frente-a-la-pared', 'patada-a-la-pared',
  'toques-de-hombro-en-pared', 'patada-al-equilibrio'];
// Dos que ya estaban en el catálogo y solo reciben figura.
const CON_FIGURA = ['hollow-hold', 'parada-de-rana'];

const slugs = [...sql.matchAll(/^\s*\('[^']+','([a-z0-9-]+)','(?:Movilidad|Calistenia)'/gm)].map(m => m[1]);
assert.deepEqual(slugs.sort(), [...NUEVOS].sort(), 'los diez ejercicios nuevos, ni uno más');

// Cada uno trae instructions y instructions_en: el renglón del inglés va justo antes del SVG.
const enInstr = (sql.match(/^\s*'[A-Z][^']*(?:''[^']*)*',\n\s*'\/skill-anim\//gm) || []).length;
assert.equal(enInstr, 10, 'cada ejercicio nuevo trae sus instrucciones en inglés');
assert.match(sql, /add column if not exists instructions_en/);

// Lo que la 145 ya no hace: era un programa y dejó de serlo.
for (const fuera of ['_hs_boards', 'coaching_program_days', 'coaching_program_weeks',
                     'template_key', 'habit-handstand:program']) {
  assert.ok(!sql.includes(fuera), `la 145 es solo contenido: ya no debe escribir ${fuera}`);
}

// ── 2. Las figuras existen y la migración apunta a las que existen ─────────
for (const slug of [...NUEVOS, ...CON_FIGURA]) {
  assert.ok(fs.existsSync(`skill-anim/${slug}.svg`), `${slug} no tiene figura (skill-anim/${slug}.svg)`);
  assert.ok(sql.includes(`/skill-anim/${slug}.svg`), `la 145 no enlaza la figura de ${slug}`);
}
for (const m of sql.matchAll(/'\/skill-anim\/([a-z0-9-]+)\.svg'/g)) {
  assert.ok(fs.existsSync(`skill-anim/${m[1]}.svg`), `la 145 enlaza ${m[1]}.svg y no existe`);
}

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


// ── Lo que la 145 cierra de paso ───────────────────────────────────────────
// Las funciones que reescriben la semana de alguien se le quitan a anon, y cada una solo
// donde esté: un revoke sobre una función que no existe tumba toda la migración (la 124).
for (const f of ['public.apply_coaching_program(uuid, uuid, date, date, date)',
                 'public.apply_coaching_program(uuid, uuid, date, date)',
                 'public.ensure_coaching_week_from_template(uuid, date)',
                 'public.coaching_week_slots(uuid, uuid, integer)']) {
  assert.ok(sql.includes(`'${f}'`), `la 145 tiene que quitarle a anon ${f}`);
}
assert.match(sql, /to_regprocedure\(f\) is not null/, 'el revoke va guardado: la firma puede no existir');
assert.match(sql, /execute 'revoke execute on function ' \|\| f \|\| ' from anon'/);

console.log(`HABIT parada de manos: ${NUEVOS.length} ejercicios nuevos y ${NUEVOS.length + CON_FIGURA.length} figuras probadas`);
