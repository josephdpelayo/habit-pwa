// HABIT Skills — escaleras de calistenia (migración 141). Lo que estas aserciones protegen:
//   1. que la curva sea CONTINUA: subir de escalón cae en el mismo número donde terminó el
//      anterior. Si se rompe, la gráfica del alumno se lee como un derrumbe cada vez que
//      avanza, que es justo el bug que el nivel derivado existe para evitar;
//   2. que el estándar pida N series en DOS sesiones SEGUIDAS, y que una sesión donde no
//      entrenó el ejercicio se salte en vez de romper la racha;
//   3. que la marca de un aguante salga de actual_seconds y también de un actual_reps viejo
//      tipo "0:30", porque las dos formas viven en la base;
//   4. que los cues se partan en puntos numerables sin numerar lo que es una sola frase;
//   5. que la migración y la app no se separen: los escalones que la migración marca tienen
//      que existir como ejercicios, y crew.html tiene que cargar el módulo;
//   6. que sin coach el alumno mueva SOLO lo que eligió él (144): lo que puso el coach no lo
//      toca, y entrenar un escalón desde la escalera deja series que la escalera sí encuentra.
const assert = require('node:assert/strict');
const fs = require('node:fs');

global.HabitTraining = require('../habit-training.js');
const Skills = require('../habit-skills.js');

const migration = fs.readFileSync('migrations/141_coach_skills.sql', 'utf8');
const crew = fs.readFileSync('crew.html', 'utf8');

// Una línea de prueba con la forma real del front lever: aguantes, objetivo decreciente y un
// último escalón sin objetivo propio.
const catalog = [
  {slug: 'a', progression_group: 'fl', progression_rank: 1, progression_target: 45, progression_target_sets: 1, default_tracking: 'time'},
  {slug: 'b', progression_group: 'fl', progression_rank: 2, progression_target: 15, progression_target_sets: 3, default_tracking: 'time'},
  {slug: 'c', progression_group: 'fl', progression_rank: 3, progression_target: 10, progression_target_sets: 2, default_tracking: 'time'},
  {slug: 'd', progression_group: 'fl', progression_rank: 4, progression_target: null, progression_target_sets: 1, default_tracking: 'time'},
  {slug: 'otro', progression_group: 'planche', progression_rank: 1, progression_target: 30, progression_target_sets: 2, default_tracking: 'time'},
  {slug: 'suelto', progression_group: null, progression_rank: null}
];
const fl = Skills.rungs(catalog, 'fl');

// ── 1. La escalera ─────────────────────────────────────────────────────────
assert.deepEqual(fl.map(r => r.slug), ['a', 'b', 'c', 'd'], 'ordenada por rank, solo su línea');
assert.equal(Skills.rungs(catalog, null).length, 0, 'sin línea no hay escalera');
assert.equal(Skills.topRank(fl), 4);
assert.equal(Skills.rungAt(fl, 2).slug, 'b');
assert.equal(Skills.nextRung(fl, 2).slug, 'c');
assert.equal(Skills.nextRung(fl, 4), null, 'el último no tiene siguiente');
assert.equal(Skills.isFinalRung(fl, 4), true);
assert.equal(Skills.isFinalRung(fl, 3), false);

// Un escalón sin rank no entra en la escalera: sin posición desordenaría la curva.
assert.equal(Skills.rungs([{progression_group: 'fl', progression_rank: 0}], 'fl').length, 0);

// ── 2. La curva es continua ────────────────────────────────────────────────
assert.equal(Skills.skillLevel(fl, 1, 0), 1, 'el piso de un escalón es su propio número');
assert.equal(Skills.skillLevel(fl, 1, 45), 2, 'clavar el objetivo del 1 vale exactamente 2');
assert.equal(Skills.skillLevel(fl, 2, 0), 2, 'y llegar al 2 arranca en 2: sin salto ni caída');
assert.equal(Skills.skillLevel(fl, 1, 90), 2, 'pasarse del objetivo no infla el nivel');
assert.equal(Skills.skillLevel(fl, 2, 15), 3);
assert.equal(Skills.skillLevel(fl, 2, 7.5), 2.5, 'a medio escalón, medio nivel');
// El último escalón se mide contra el objetivo del anterior, que es lo que hubo que hacer
// para llegar: si no, un nivel sin objetivo se quedaría clavado en su número para siempre.
assert.equal(Skills.skillLevel(fl, 4, 0), 4);
assert.equal(Skills.skillLevel(fl, 4, 10), 5);
assert.equal(Skills.skillLevel(fl, 9, 10), null, 'un escalón que no existe no tiene nivel');

// La barra del escalón actual, 0 a 1.
assert.equal(Skills.rungProgress(fl, 2, 7.5), 0.5);
assert.equal(Skills.rungProgress(fl, 2, 99), 1);
assert.equal(Skills.rungProgress(fl, 2, 0), 0);

// ── 3. La marca ────────────────────────────────────────────────────────────
assert.equal(Skills.markUnit(fl[0]), 'time');
assert.equal(Skills.markUnit({default_tracking: 'reps'}), 'reps');
assert.equal(Skills.setMark(fl[0], {done: true, actual_seconds: 22}), 22);
assert.equal(Skills.setMark(fl[0], {done: true, actual_reps: '0:30'}), 30, 'tiempo escrito en actual_reps (series previas a la 117)');
assert.equal(Skills.setMark(fl[0], {done: true, actual_reps: '18s'}), 18);
assert.equal(Skills.setMark({default_tracking: 'reps'}, {done: true, actual_reps: '8'}), 8);
assert.equal(Skills.setMark({default_tracking: 'reps'}, {done: true, actual_reps: '8 reps'}), 8);
assert.equal(Skills.setMark(fl[0], null), 0);
// actual_seconds manda sobre actual_reps cuando están los dos.
assert.equal(Skills.setMark(fl[0], {done: true, actual_seconds: 25, actual_reps: '0:10'}), 25);

// Una serie sin palomear no es una marca.
assert.equal(Skills.bestMark(fl[1], [{done: false, actual_seconds: 60}, {done: true, actual_seconds: 12}]), 12);
assert.equal(Skills.bestMark(fl[1], []), 0);

// ── 4. El estándar: dos sesiones seguidas ──────────────────────────────────
const hit = n => ({sets: Array.from({length: n}, () => ({done: true, actual_seconds: 15}))});
const miss = n => ({sets: Array.from({length: n}, () => ({done: true, actual_seconds: 9}))});
const resto = {sets: [{done: false, actual_seconds: 15}]};   // no lo entrenó

// El escalón 2 pide 3 series de 15 s.
assert.equal(Skills.readiness(fl, 2, [hit(3), hit(3)]).ready, true);
assert.equal(Skills.readiness(fl, 2, [hit(3)]).ready, false, 'una sesión no alcanza');
assert.equal(Skills.readiness(fl, 2, [hit(2), hit(3)]).ready, false, 'dos series no son tres');
assert.equal(Skills.readiness(fl, 2, [hit(3), miss(3), hit(3)]).ready, false,
  'una sesión que lo entrenó y no llegó rompe la racha');
assert.equal(Skills.readiness(fl, 2, [hit(3), resto, hit(3)]).ready, true,
  'una sesión donde no lo entrenó se salta, no rompe');
assert.equal(Skills.readiness(fl, 2, []).ready, false);
assert.equal(Skills.readiness(fl, 4, [hit(3), hit(3)]).ready, false,
  'el último escalón no tiene a dónde subir');
assert.equal(Skills.readiness(fl, 4, [hit(3), hit(3)]).final, true);

// Lo que la app le enseña al coach además del sí/no.
const r = Skills.readiness(fl, 2, [hit(3)]);
assert.equal(r.needed, 3);
assert.equal(r.target, 15);
assert.equal(r.streak, 1);
assert.equal(r.lastQualified, true, 'ya cumplió la última vez: una más y sube');
assert.equal(Skills.readiness(fl, 2, [miss(3)]).lastQualified, false);

// ── 5. Cues ────────────────────────────────────────────────────────────────
assert.deepEqual(Skills.cueList('Codos bloqueados\nCadera a la altura del hombro\nCostillas hundidas'),
  ['Codos bloqueados', 'Cadera a la altura del hombro', 'Costillas hundidas']);
assert.deepEqual(Skills.cueList('Codos bloqueados; cadera arriba'), ['Codos bloqueados', 'cadera arriba']);
assert.deepEqual(Skills.cueList('- Codos bloqueados\n• Cadera arriba\n2) Costillas'),
  ['Codos bloqueados', 'Cadera arriba', 'Costillas'], 'las viñetas que ya venían escritas no se duplican');
assert.deepEqual(Skills.cueList('Una sola indicación'), ['Una sola indicación'],
  'una frase sigue siendo una: la app no la numera');
assert.deepEqual(Skills.cueList(''), []);
assert.deepEqual(Skills.cueList(null), []);
assert.deepEqual(Skills.cueList('   \n  \n '), [], 'solo espacios no son cues');
assert.equal(Skills.cueList(Array.from({length: 20}, (_, i) => 'cue ' + i).join('\n')).length, Skills.CUE_MAX,
  'se corta en CUE_MAX: una lista de 20 cues nadie la lee');
assert.ok(Skills.cueList('x'.repeat(400))[0].length <= Skills.CUE_LEN, 'un cue larguísimo se recorta');

// ── 6. La animación ────────────────────────────────────────────────────────
assert.equal(Skills.animationKind('https://x/y/front-lever.gif'), 'image');
assert.equal(Skills.animationKind('https://x/y/front-lever.mp4'), 'video');
assert.equal(Skills.animationKind('https://x/y/a.webm?v=2'), 'video');
assert.equal(Skills.animationKind('/skill-anim/front-lever-tuck.svg'), 'image',
  'un SVG animado corre solo dentro de un <img>, sin JS');
assert.equal(Skills.animationKind('https://youtube.com/watch?v=abc'), null,
  'un embed no es una animación: una que hay que tocar no enseña la posición');
assert.equal(Skills.animationKind(''), null);
assert.equal(Skills.animationKind(null), null);

// ── 6b. Sin coach (migración 144) ──────────────────────────────────────────
// Quién manda en una fila lo dice set_by, la misma regla que la RLS.
assert.equal(Skills.rungOwner(null), 'none', 'sin fila, la línea está libre');
assert.equal(Skills.rungOwner({user_id: 'u1', set_by: 'u1', rank: 2}), 'self');
assert.equal(Skills.rungOwner({user_id: 'u1', set_by: 'coach', rank: 2}), 'coach');
assert.equal(Skills.rungOwner({user_id: 'u1', set_by: null, rank: 2}), 'coach',
  'un coach borrado deja set_by en null: la fila sigue siendo de solo lectura');

// Entrenar un escalón: su estándar como objetivo, con al menos RUNG_MIN_SETS series.
assert.deepEqual(Skills.rungWorkout(fl, 2), {sets: '3', reps: '15s', rest: '120s', repsType: 'time'});
assert.equal(Skills.rungWorkout(fl, 1).sets, String(Skills.RUNG_MIN_SETS),
  'un estándar de una sola serie no hace un entreno de una serie');
assert.equal(Skills.rungWorkout(fl, 1).reps, '45s');
assert.equal(Skills.rungWorkout(fl, 4).reps, '10s', 'el último escalón entrena con el objetivo del anterior');
assert.equal(Skills.rungWorkout(fl, 9), null);
const repsLine = Skills.rungs([
  {slug: 'r1', progression_group: 'mu', progression_rank: 1, progression_target: 8, progression_target_sets: 2, default_tracking: 'reps'},
  {slug: 'r2', progression_group: 'mu', progression_rank: 2, progression_target: null, progression_target_sets: 1, default_tracking: 'reps'}
], 'mu');
assert.deepEqual(Skills.rungWorkout(repsLine, 1), {sets: '3', reps: '8', rest: '120s'},
  'uno de repeticiones no lleva repsType de tiempo');
assert.equal(Skills.rungWorkout(repsLine, 2).reps, '8');
// Lo que cumple en la hoja es lo que cuenta readiness(): el objetivo de la serie se lee
// igual que el estándar.
assert.equal(global.HabitTraining.parseSeconds(Skills.rungWorkout(fl, 2).reps), fl[1].progression_target);

// La llave de un ejercicio agregado en vivo lleva de vuelta a su escalón.
assert.equal(Skills.catalogSlugFromExKey('cat-front-lever-tuck'), 'front-lever-tuck');
assert.equal(Skills.catalogSlugFromExKey('cat-front-lever-tuck#2'), 'front-lever-tuck',
  'el mismo ejercicio dos veces en una sesión sigue siendo el mismo escalón');
assert.equal(Skills.catalogSlugFromExKey('ex_123'), null, 'una llave de rutina no es del catálogo');
assert.equal(Skills.catalogSlugFromExKey(null), null);

// ── 7. La migración y la app no se separan ─────────────────────────────────
// Cada escalón que la migración marca tiene que existir como ejercicio: o lo trajo la 071, o
// lo inserta la propia 141. Un escalón sin ejercicio deja un hueco invisible en la escalera.
const inserted = new Set();
const insertBlock = migration.slice(migration.indexOf('insert into public.exercise_catalog'));
for (const m of insertBlock.matchAll(/^\s*\('[^']+','([a-z0-9-]+)','Calistenia'/gm)) inserted.add(m[1]);
const from071 = new Set(
  [...fs.readFileSync('migrations/071_import_skandi_exercise_catalog.sql', 'utf8')
    .matchAll(/\('[a-z0-9-]+','[^']+','([a-z0-9-]+)'\)/g)].map(m => m[1])
);
const rungRows = [...migration.matchAll(/^\s*\('([a-z-]+)',(\d+),'([a-z0-9-]+)','(time|reps)',(null|\d+),(\d+),$/gm)]
  .map(m => ({grp: m[1], rank: Number(m[2]), slug: m[3], unit: m[4], target: m[5], sets: Number(m[6])}));
assert.ok(rungRows.length >= 35, 'se leyeron los escalones de la migración, salieron ' + rungRows.length);
for (const row of rungRows) {
  assert.ok(inserted.has(row.slug) || from071.has(row.slug),
    `el escalón ${row.slug} (${row.grp} ${row.rank}) no existe como ejercicio`);
}

// Cada línea empieza en 1 y no se salta números: un hueco en los ranks parte la curva.
const byGroup = new Map();
for (const row of rungRows) {
  if (!byGroup.has(row.grp)) byGroup.set(row.grp, []);
  byGroup.get(row.grp).push(row);
}
assert.equal(byGroup.size, 7, 'siete líneas sembradas');
for (const [grp, list] of byGroup) {
  list.sort((a, b) => a.rank - b.rank);
  assert.deepEqual(list.map(x => x.rank), list.map((_, i) => i + 1), `${grp}: ranks seguidos desde 1`);
  // Solo el último escalón va sin objetivo: los de en medio son el estándar para subir.
  assert.equal(list[list.length - 1].target, 'null', `${grp}: el último escalón no lleva objetivo`);
  for (const row of list.slice(0, -1)) {
    assert.notEqual(row.target, 'null', `${grp} ${row.rank}: un escalón intermedio necesita objetivo`);
  }
  // Una línea PUEDE mezclar unidades —en handstand, los heel pulls son repeticiones entre
  // puros aguantes, y así es en Skandi— porque cada escalón se mide contra su propio
  // objetivo y el cociente marca/objetivo no tiene unidad. La única excepción es el último
  // escalón, que no tiene objetivo propio y se mide contra el del anterior: ahí sí hay que
  // compartir unidad, o el nivel final compararía segundos con repeticiones.
  if (list.length >= 2) {
    assert.equal(list[list.length - 1].unit, list[list.length - 2].unit,
      `${grp}: el último escalón hereda el objetivo del anterior, así que comparten unidad`);
  }
}

// Cada línea sembrada tiene su fila en coach_skills, con nombre en los dos idiomas.
for (const grp of byGroup.keys()) {
  assert.ok(migration.includes(`('${grp}','`), `coach_skills no tiene la línea ${grp}`);
}

// En la 141 el escalón lo mueve el coach: la tabla del alumno no le da permiso de escritura.
assert.match(migration, /create policy "Students read own skills"[\s\S]{0,200}for select/,
  'el alumno solo LEE su escalón');
assert.doesNotMatch(migration, /create policy "Students manage own skills"/);

// La 144 le abre al alumno SOLO las filas que puso él. Cada política de escritura pide
// set_by = auth.uid(), y la de update lo pide también en USING —la fila como estaba—, que es
// lo que impide pisar con un upsert un escalón que puso el coach.
const selfMig = fs.readFileSync('migrations/144_self_coached_skills.sql', 'utf8');
const policies = [...selfMig.matchAll(/create policy "([^"]+)"\s+on public\.coach_student_skills for (\w+)([\s\S]*?);/g)]
  .map(m => ({name: m[1], cmd: m[2], body: m[3]}));
assert.deepEqual(policies.map(p => p.cmd).sort(), ['delete', 'insert', 'update'], 'la 144 abre insert, update y delete');
for (const p of policies) {
  assert.match(p.body, /auth\.uid\(\) = user_id and set_by = auth\.uid\(\)/, `${p.name}: solo lo suyo y puesto por él`);
}
const upd = policies.find(p => p.cmd === 'update');
assert.match(upd.body, /using \(auth\.uid\(\) = user_id and set_by = auth\.uid\(\)\)/,
  'update: USING mira quién puso la fila, o el alumno pisaría al coach');
for (const p of policies.filter(x => x.cmd !== 'delete')) {
  assert.match(p.body, /coach_note is null/, `${p.name}: «De tu coach» no lo escribe el alumno`);
}
assert.doesNotMatch(selfMig, /for all/, 'nada de un permiso amplio en la tabla del alumno');

// crew.html carga el módulo y el service worker lo cachea: si falta en SHELL, el teléfono se
// queda con la versión vieja o sin el archivo.
assert.match(crew, /habit-skills\.js/, 'crew.html carga habit-skills.js');
assert.match(fs.readFileSync('sw.js', 'utf8'), /habit-skills\.js/, 'sw.js cachea habit-skills.js');

// ── 8. Las animaciones: migración 142 y archivos, en sincronía ─────────────
// El dibujo de un escalón vive en dos lados —el SVG en el repo y su URL en la migración— y
// si se separan, la escalera enseña un hueco o un 404. El generador los produce a la vez;
// esto falla si alguien borra uno sin el otro.
const anim = fs.readFileSync('migrations/142_skill_animations.sql', 'utf8')
  + fs.readFileSync('migrations/143_skill_animations_resto.sql', 'utf8');
const animSlugs = [...anim.matchAll(/^\s*\('([a-z0-9-]+)'\)[,;]?$/gm)].map(m => m[1]);
assert.equal(new Set(animSlugs).size, animSlugs.length, 'ningún escalón enlazado dos veces');
assert.equal(animSlugs.length, 35, 'las siete escaleras dibujadas');
const animFiles = fs.readdirSync('skill-anim').filter(f => f.endsWith('.svg')).map(f => f.replace(/\.svg$/, ''));
for (const slug of animSlugs) {
  assert.ok(animFiles.includes(slug), `la 142 enlaza ${slug}.svg pero el archivo no existe`);
  const svg = fs.readFileSync(`skill-anim/${slug}.svg`, 'utf8');
  assert.match(svg, /<animateTransform/, `${slug}.svg no anima: sería una imagen fija`);
  // Cuadrado, porque la miniatura es 1:1 con object-fit cover y recortaría las piernas.
  const vb = svg.match(/viewBox="(-?\d+) (-?\d+) (\d+) (\d+)"/);
  assert.ok(vb, `${slug}.svg sin viewBox`);
  assert.equal(vb[3], vb[4], `${slug}.svg no es cuadrado: la miniatura lo recortaría`);
}
for (const f of animFiles) {
  assert.ok(animSlugs.includes(f), `skill-anim/${f}.svg no lo enlaza ninguna migración`);
}
// Y cada uno tiene que ser un escalón de verdad de una de las dos líneas.
const ladderSlugs = new Set(rungRows.map(r => r.slug));
for (const slug of animSlugs) {
  assert.ok(ladderSlugs.has(slug), `${slug} tiene animación pero no es escalón de ninguna línea`);
}
assert.equal(ladderSlugs.size, 35, 'todos los escalones de las siete líneas tienen dibujo');
// La 142 nunca pisa una animación que el coach ya subió.
// La invariante no es cuántas escrituras hay, sino que TODAS vayan protegidas: el video
// que suba el coach no se puede perder porque alguien vuelva a correr la migración.
const writes = (anim.match(/set animation_url/g) || []).length;
const guards = (anim.match(/animation_url is null/g) || []).length;
assert.ok(writes > 0 && writes === guards,
  `cada escritura de animation_url debe ir con "is null": ${writes} escrituras, ${guards} guardas`);

// ── 9. Cada figura es lo que pide su escalón ───────────────────────────────
// Los SVG llevan un punto de referencia en mano, hombro, cadera, rodilla y pie (data-j), en
// la posición dibujada —la animación es solo lo de encima—. Lo que define un escalón es una
// alineación, así que se prueba la alineación: si el generador dibuja mal una pose, falla
// aquí y no en la escalera de alguien.
const joints = slug => {
  const j = {};
  const svg = fs.readFileSync(`skill-anim/${slug}.svg`, 'utf8');
  for (const m of svg.matchAll(/<circle cx="(-?[\d.]+)" cy="(-?[\d.]+)" r="([\d.]+)" fill="#a78bfa" data-j="(\w+)"\/>/g)) {
    j[m[4]] = {x: Number(m[1]), y: Number(m[2]), r: Number(m[3])};
  }
  return j;
};
const TOL = 0.6;
const sameY = (slug, names) => {
  const j = joints(slug);
  for (const n of names.slice(1)) {
    assert.ok(Math.abs(j[n].y - j[names[0]].y) <= TOL, `${slug}: ${n} fuera de la línea de ${names[0]} (${j[n].y} vs ${j[names[0]].y})`);
  }
};
// Distancia de cada punto a la recta de los dos primeros: una recta es una recta.
const collinear = (slug, names) => {
  const j = joints(slug), a = j[names[0]], b = j[names[1]];
  const len = Math.hypot(b.x - a.x, b.y - a.y);
  for (const n of names.slice(2)) {
    const c = j[n];
    const off = Math.abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) / len;
    assert.ok(off <= 0.8, `${slug}: ${n} se sale de la recta ${names.join('-')} por ${off.toFixed(1)}`);
  }
};

for (const slug of animSlugs) {
  const j = joints(slug);
  const need = slug.startsWith('curl-nordico') ? ['shoulder', 'hip', 'knee', 'foot']
    : ['hand', 'shoulder', 'hip', 'knee', 'foot'];
  for (const n of need) assert.ok(j[n], `${slug}: falta el punto de referencia ${n}`);
  for (const n of Object.keys(j)) assert.ok(j[n].r <= 4, `${slug}: el punto ${n} no es sutil (r=${j[n].r})`);
}

// Lever, planche y straddle completos: hombro, cadera, rodilla y pie en una sola línea. El
// straddle también: las piernas se abren a los lados, así que de perfil siguen en la línea
// (antes se dibujaba como tijera, un pie arriba y otro abajo).
for (const slug of ['front-lever-completo', 'front-lever-a-un-brazo', 'front-lever-a-una-pierna',
  'front-lever-straddle', 'back-lever-straddle', 'back-lever-completo', 'plancha-straddle',
  'plancha-completa', 'elevacion-a-front-lever-straddle', 'elevaciones-a-front-lever']) {
  sameY(slug, ['shoulder', 'hip', 'knee', 'foot']);
}
// Tuck avanzado: hombro, cadera y pie a la misma altura, con la rodilla fuera de la línea.
for (const slug of ['front-lever-tuck-avanzado', 'plancha-tuck-avanzada', 'elevacion-a-front-lever-tuck-avanzado']) {
  sameY(slug, ['shoulder', 'hip', 'foot']);
  const j = joints(slug);
  assert.ok(Math.abs(j.knee.y - j.hip.y) > 10, `${slug}: la rodilla tiene que salir de la línea`);
}
// Half lay: cadera abierta en la línea y la espinilla vertical bajo la rodilla.
sameY('front-lever-half-lay', ['shoulder', 'hip', 'knee']);
{
  const j = joints('front-lever-half-lay');
  assert.ok(Math.abs(j.foot.x - j.knee.x) <= TOL && j.foot.y > j.knee.y, 'half lay: rodilla a 90°');
}
// Las rodillas del tuck van del lado del PECHO: arriba en front lever (de cara al techo),
// abajo en planche y back lever (de cara al piso). Planche y back lever las tenían al revés.
for (const slug of ['front-lever-tuck', 'front-lever-tuck-avanzado', 'elevacion-a-front-lever-tuck']) {
  const j = joints(slug);
  assert.ok(j.knee.y < j.hip.y, `${slug}: de cara al techo, la rodilla va arriba de la cadera`);
}
for (const slug of ['plancha-tuck', 'plancha-tuck-avanzada', 'back-lever-tuck']) {
  const j = joints(slug);
  assert.ok(j.knee.y > j.hip.y, `${slug}: de cara al piso, la rodilla va abajo de la cadera`);
}
// En una palanca el brazo va en diagonal, porque la palanca la sostiene la espalda: la mano
// se adelanta hacia la cadera y la barra queda sobre el pecho, entre hombro y cadera.
for (const slug of animSlugs.filter(s => /^(front-lever|back-lever|elevacion|elevaciones)/.test(s))) {
  const j = joints(slug);
  const towardHip = Math.sign(j.hip.x - j.shoulder.x);
  assert.ok((j.hand.x - j.shoulder.x) * towardHip > 15, `${slug}: el brazo tiene que ir en diagonal hacia la cadera`);
}
{
  const j = joints('colgado-invertido');      // el colgado invertido no es palanca: vertical
  for (const n of ['shoulder', 'hip', 'knee', 'foot']) {
    assert.ok(Math.abs(j[n].x - j.hand.x) <= TOL, `colgado invertido: ${n} fuera de la vertical`);
  }
}
// Parada de manos: la muñeca bajo el hombro y el cuerpo recto. Las libres, todo en una
// vertical; las de pared y la plancha a 45° van inclinadas, pero siguen siendo una recta.
for (const slug of animSlugs.filter(s => /parada-de-manos|heel-pulls|plancha-en-pared/.test(s))) {
  const j = joints(slug);
  assert.ok(Math.abs(j.hand.x - j.shoulder.x) <= TOL, `${slug}: el hombro tiene que estar apilado sobre la muñeca`);
  collinear(slug, ['shoulder', 'hip', 'knee', 'foot']);
}
for (const slug of ['parada-de-manos-libre', 'parada-de-manos-a-un-brazo', 'traspaso-de-peso-en-parada-de-manos',
  'parada-de-manos-de-frente-a-la-pared', 'heel-pulls-toe-pulls']) {
  collinear(slug, ['hand', 'shoulder', 'hip', 'foot']);
}
{
  const j = joints('plancha-en-pared-45-grados');
  const deg = Math.atan2(j.hip.y - j.foot.y, j.foot.x - j.hip.x) * 180 / Math.PI;
  assert.ok(Math.abs(Math.abs(deg) - 45) <= 1, `plancha en pared: el cuerpo va a 45°, sale a ${deg.toFixed(1)}°`);
}
// Planche lean: una recta de hombro a pie, y el pie en el piso.
collinear('planche-lean', ['shoulder', 'hip', 'knee', 'foot']);
{
  const j = joints('planche-lean');
  assert.ok(Math.abs(j.foot.y - j.hand.y) <= 2, 'planche lean: los pies siguen en el piso');
}
// Muscle-up: en la dominada la barra toca el pecho (hombros arriba de ella, cadera abajo); en
// la transición el hombro ya pasó la barra; arriba es un apoyo, no una parada de manos.
{
  const pull = joints('dominada-al-pecho'), trans = joints('muscle-up-negativo'), top = joints('muscle-up-en-barra');
  assert.ok(pull.shoulder.y < pull.hand.y && pull.hip.y > pull.hand.y, 'dominada al pecho: la barra cruza el pecho');
  assert.ok(trans.shoulder.y < trans.hand.y && trans.hip.y > trans.hand.y, 'negativo: hombro arriba de la barra, cadera abajo');
  assert.ok(top.shoulder.y < top.hip.y && top.hip.y <= top.hand.y && top.foot.y > top.hand.y,
    'muscle-up arriba: apoyo con la cadera en la barra y las piernas abajo, no de cabeza');
}
// Nórdico: la cadera abierta es el estándar, así que rodilla, cadera y hombro van en recta;
// rodilla y tobillo en el piso.
for (const slug of animSlugs.filter(s => s.startsWith('curl-nordico'))) {
  collinear(slug, ['knee', 'hip', 'shoulder']);
  const j = joints(slug);
  assert.ok(Math.abs(j.knee.y - j.foot.y) <= TOL, `${slug}: rodilla y tobillo en el piso`);
}


// Compila el script principal de crew.html sin ejecutarlo. Ninguna prueba lo hacía —cada una
// extrae el trozo que le toca— y crew.html es justo el archivo donde entra todo lo nuevo: un
// paréntesis roto se caía en el teléfono y no aquí. Mismo truco que check-training.js, que
// hace esto con app.html; el <script id="brand-boot"> del <head> lleva atributo a propósito,
// así que el primer <script> sin atributos es el de la app.
const crewStart = crew.indexOf('<script>');
const crewEnd = crew.lastIndexOf('</script>');
assert.ok(crewStart >= 0 && crewEnd > crewStart, 'script principal de crew.html encontrado');
new Function(crew.slice(crewStart + '<script>'.length, crewEnd));


console.log('HABIT skills: ' + (100 + rungRows.length) + ' aserciones OK (' + rungRows.length + ' escalones, ' + byGroup.size + ' líneas)');
