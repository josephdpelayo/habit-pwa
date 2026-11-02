// Los stickers de habit-share.js sin navegador: cómo se parten los renglones, que la frase no
// pase de cinco ni se salga del sticker, y que todo quede dentro del lienzo. El dibujo y el
// portapapeles se prueban en el teléfono (Fase 0 de docs/HISTORIAS_INSTAGRAM.md).
const assert = require('node:assert/strict');
const S = require('../habit-share.js');

// Medida falsa pero proporcional: cada letra mide 0.5 del tamaño de la fuente.
const pxOf = (font) => Number(String(font).match(/(\d+)px/)[1]);
const measure = (text, font) => [...String(text)].length * pxOf(font || '100px') * 0.5;
const m100 = (t) => measure(t, '100px');

assert.deepEqual(S.wrapText('uno dos tres', 400, m100), ['uno dos', 'tres']);
assert.deepEqual(S.wrapText('', 400, m100), []);
assert.deepEqual(S.wrapText('palabrademasiadolarga', 100, m100), ['palabrademasiadolarga'], 'una palabra sola no se corta');

// Parejo: mismos renglones que el corte normal, pero sin una palabra colgando al final.
const greedy = S.wrapText('a bb ccc dddd eeeee ffffff', 700, m100);
const even = S.balancedWrap('a bb ccc dddd eeeee ffffff', 700, m100);
assert.equal(even.length, greedy.length);
const spread = (ls) => Math.max(...ls.map(m100)) - Math.min(...ls.map(m100));
assert.ok(spread(even) <= spread(greedy), 'los renglones parejos no quedan más disparejos');

const quotes = [
  'Una vida fuerte se edifica con días que no presumiste.',
  'Hazlo.',
  'La disciplina es elegir entre lo que quieres ahora y lo que más quieres, una y otra vez, todos los días, incluso cuando nadie te ve y nadie te aplaude.'
];
for (const q of quotes) {
  const L = S.quoteLayout(q, measure);
  assert.ok(L.lines.length >= 1 && L.lines.length <= 5, `«${q.slice(0, 20)}…» en 1–5 renglones`);
  assert.ok(L.size >= 40 && L.size <= 150, 'tamaño de letra en rango');
  assert.ok(L.size <= 76 || L.lines.length <= 3, 'una frase grande no pasa de tres renglones');
  assert.equal(L.font.includes(L.size + 'px'), true, 'los renglones son del tamaño que se dibuja');
  const inner = S.WIDTH - 72 * 2;
  L.lines.forEach((l) => assert.ok(measure(l.text, L.font) <= inner + 0.5, 'ningún renglón se sale'));
  assert.equal(L.lines.map((l) => l.text).join(' '), '“' + q + '”', 'no se pierde ni se agrega texto');
  const lk = L.lockup;
  assert.ok(lk.logo.y + lk.logo.size <= L.height, 'el logotipo cabe en el lienzo');
  assert.ok(lk.logo.x >= 0 && lk.word.x + measure('HABIT', lk.word.font) <= L.width, 'el logotipo no se sale');
  assert.equal(lk.crew.text, 'CREW', 'el logotipo es HABIT Crew');
  assert.ok(lk.crew.x > lk.word.x + measure('HABIT', lk.word.font), 'CREW va después de HABIT');
  assert.equal(lk.crew.y, lk.word.y, 'sobre la misma línea base');
  assert.ok(Math.abs(lk.logo.x + lk.width - (lk.crew.x + S.spacedWidth('CREW', lk.crew.spacing, (c) => measure(c, lk.crew.font)))) < 0.5, 'el ancho incluye CREW');
  assert.ok(Math.abs((lk.logo.x + lk.width / 2) - L.width / 2) < 1, 'el logotipo va centrado');
  assert.ok(L.font.includes('Inter') && lk.word.font.startsWith('800'), 'Inter, la fuente de HABIT');
  assert.equal(L.width, 1080);
}
const long = S.quoteLayout(quotes[2], measure);
const short = S.quoteLayout(quotes[1], measure);
assert.ok(long.size < short.size, 'la frase larga baja de tamaño');
assert.ok(short.size >= 2 * long.size, 'una frase de una palabra sube de tamaño, no se queda como la firma');

const sig = S.signatureLayout(measure);
assert.ok(sig.lockup.logo.x >= 0 && sig.lockup.logo.x + sig.lockup.width <= sig.width + 0.5, 'la firma cabe a lo ancho');
assert.ok(sig.sub.y <= sig.height, 'MAKE IT A HABIT cabe');
assert.equal(sig.lockup.word.text, 'HABIT');

// Colores: blanco y negro primero; cada uno con la tinta que se lee encima (el recibo, el
// carnet), y uno libre se resuelve igual. Lo que no es un color cae en blanco.
assert.deepEqual(S.PALETTE.slice(0, 2).map((c) => c.key), ['blanco', 'negro'], 'blanco y negro primero');
assert.ok(S.PALETTE.length >= 10, 'más de diez colores');
assert.equal(new Set(S.PALETTE.map((c) => c.hex)).size, S.PALETTE.length, 'sin colores repetidos');
for (const c of S.PALETTE) {
  const pal = S.resolveColor(c.key);
  assert.equal(pal.fg, c.hex);
  assert.ok(S.contrast(pal.fg, pal.ink) >= 3, c.key + ': su tinta se lee (3:1)');
}
assert.deepEqual(S.resolveColor('blanco'), { fg: '#ffffff', ink: '#0b0b0b' }, 'como antes');
assert.deepEqual(S.resolveColor('negro'), { fg: '#0b0b0b', ink: '#ffffff' }, 'como antes');
assert.equal(S.resolveColor('azul').ink, '#ffffff', 'sobre azul, blanco');
assert.equal(S.resolveColor('lima').ink, '#0b0b0b', 'sobre lima, negro');
assert.deepEqual(S.resolveColor('#FF00AA'), { fg: '#ff00aa', ink: '#ffffff' }, 'un color libre');
for (const bad of ['', 'morado', 'constructor', '#12345', 'red']) {
  assert.equal(S.resolveColor(bad).fg, '#ffffff', `«${bad}» no es un color: blanco`);
}
assert.ok(Math.abs(S.contrast('#ffffff', '#000000') - 21) < 0.01, 'contraste WCAG');

// Sello: la vuelta cierra exacta (el espacio se reparte), las letras van en orden alrededor
// del círculo y caben en el lienzo; un texto largo baja de tamaño.
for (const text of ['MAKE IT A HABIT · 31.10.26 · ', 'MAKE IT A HABIT · ENTRENO Nº 47 · SEMANA 6 · LEG 2 · ']) {
  const L = S.sealLayout(text, measure);
  assert.equal(L.chars.length, [...text].length, 'una posición por letra');
  assert.ok(L.spacing >= 0, 'las letras no se enciman');
  assert.ok(L.chars.every((c, i) => i === 0 || c.angle > L.chars[i - 1].angle), 'en orden, sin dar dos vueltas');
  assert.ok(L.chars[L.chars.length - 1].angle < Math.PI * 2, 'termina antes de cerrar la vuelta');
  assert.ok(L.radius + L.size * 0.55 <= L.width / 2, 'las letras caben en el lienzo');
  assert.ok(L.size >= 30 && L.size <= 120, 'tamaño de letra en rango');
  // El cuadro del logo es su tinta (drawLogo agranda el PNG por su margen).
  const ink = L.logo.size;
  assert.ok(ink < L.radius * 2 - L.size * 2, 'el logo no toca las letras');
  assert.ok(ink > L.radius * 0.9, 'el logo llena el centro del sello, no queda chiquito');
}
assert.ok(S.sealLayout('MAKE IT A HABIT · ENTRENO Nº 47 · SEMANA 6 · LEG 2 · ', measure).size
  <= S.sealLayout('MAKE IT A HABIT · ', measure).size, 'el texto largo no crece');

assert.equal(S.shortDate('2026-10-31'), '31.10.26');
assert.equal(S.shortDate(''), '');


// Todo trazo dentro del lienzo: texto (de su altura de mayúsculas a su descenso), logos,
// rectángulos, círculos, líneas y polígonos.
function inside(L, name) {
  const box = (o) => {
    if (o.op === 'text') return [o.x, o.y - o.px * 0.75, o.x + o.w, o.y + o.px * 0.25];
    if (o.op === 'logo' && o.clip) return [Math.max(o.x, o.clip.x), Math.max(o.y, o.clip.y), Math.min(o.x + o.size, o.clip.x + o.clip.w), Math.min(o.y + o.size, o.clip.y + o.clip.h)];
    if (o.op === 'logo') return [o.x, o.y, o.x + o.size, o.y + o.size];
    if (o.op === 'rect') return [o.x, o.y, o.x + o.w, o.y + o.h];
    if (o.op === 'circle') return [o.cx - o.r, o.cy - o.r, o.cx + o.r, o.cy + o.r];
    if (o.op === 'line') return [Math.min(o.x1, o.x2), Math.min(o.y1, o.y2), Math.max(o.x1, o.x2), Math.max(o.y1, o.y2)];
    if (o.op === 'poly') { const xs = o.pts.map((p) => p[0]), ys = o.pts.map((p) => p[1]); return [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)]; }
    if (o.op === 'arc') { const r = o.radius + o.px * 0.5; return [o.cx - r, o.cy - r, o.cx + r, o.cy + r]; }
    throw new Error('trazo desconocido ' + o.op);
  };
  L.ops.forEach((o) => {
    const [x0, y0, x1, y1] = box(o);
    assert.ok(x0 >= -0.5 && y0 >= -0.5 && x1 <= L.width + 0.5 && y1 <= L.height + 0.5,
      `${name}: «${o.text || o.op}» se sale (${[x0, y0, x1, y1].map(Math.round)} en ${L.width}×${L.height})`);
    if (o.op === 'text') assert.ok(/Inter/.test(o.font), name + ': todo en Inter');
    if (o.op === 'arc') assert.ok(o.spacing >= 0, name + ': las letras del anillo no se enciman');
  });
}

// Todos firman como HABIT Crew: el logotipo (con CREW), la firma chica o el texto del sello.
function saysCrew(L) {
  if (L.lockup) return L.lockup.crew && L.lockup.crew.text === 'CREW';
  if (L.chars) return L.chars.map((c) => c.ch).join('').includes('HABIT CREW');
  return L.ops.some((o) => (o.op === 'text' && /\bCREW\b/.test(o.text)) || (o.op === 'arc' && o.chars.map((c) => c.ch).join('').includes('HABIT CREW')));
}

// La galería de la frase del día: nueve estilos, y cada uno se dispone con los datos de la frase.
assert.deepEqual(S.KINDS.quote.styles.map((s) => s.id),
  ['frase', 'crew', 'carnet', 'poster', 'italica', 'cinta', 'burbuja', 'comillas', 'minimo', 'logotipo', 'sello']);
for (const q of quotes) {
  for (const st of S.KINDS.quote.styles) {
    const L = st.layout({ text: q, ds: '2026-10-31' }, measure);
    assert.ok(L && L.width > 0 && L.height > 0, st.id + ' tiene tamaño');
    assert.equal(L.kind, st.id);
    if (L.ops) inside(L, 'frase/' + st.id);
    assert.ok(saysCrew(L), 'frase/' + st.id + ' firma como HABIT Crew');
  }
  const words = (L) => L.ops.filter((o) => o.op === 'text' && o.text !== 'HABIT' && o.text !== 'CREW').map((o) => o.text).join(' ');
  for (const id of ['poster', 'cinta']) {
    const L = S.KINDS.quote.styles.find((s) => s.id === id).layout({ text: q }, measure);
    assert.equal(words(L), q.toUpperCase(), id + ' no pierde texto');
  }
}
const sello = S.KINDS.quote.styles.find((s) => s.id === 'sello').layout({ text: quotes[0], ds: '2026-10-31' }, measure);
assert.ok(sello.chars.map((c) => c.ch).join('').includes('31.10.26'), 'el sello lleva la fecha');
assert.ok(S.chipHtml().includes('Compartir'), 'el botón dice Compartir');

// ── Entrenos ─────────────────────────────────────────────────────────────
assert.equal(S.clock(3134), '52:14');
assert.equal(S.clock(4325), '1:12:05');
assert.equal(S.minutesText(3134), '52 MIN');
assert.equal(S.minutesText(4320), '1 H 12 MIN');
assert.equal(S.thousands(4320), '4,320');
assert.equal(S.distanceText('run', 10020), '10.02');
assert.equal(S.distanceText('bike', 42300), '42.3');
assert.equal(S.distanceText('swim', 1500), '1,500', 'nadar va en metros');
assert.equal(S.paceText('run', 3134, 10020), '5:13 /KM');
assert.equal(S.paceText('swim', 2280, 1500), '2:32 /100 M');
assert.equal(S.paceText('bike', 5710, 42300), '26.7 KM/H');
assert.equal(S.paceText('strength', 3000, 0), '');
assert.equal(S.dayName('2026-10-31'), 'SÁBADO');

const samples = {
  carrera: { type: 'run', title: 'Correr', ds: '2026-10-31', durationSec: 3134, distanceM: 10020, number: 47 },
  fuerza: {
    type: 'strength', title: 'Leg 2', ds: '2026-10-30', durationSec: 3134, sets: 18, volumeKg: 4320, number: 12,
    exercises: [{ name: 'Sentadilla trasera', best: '100 kg × 5' }, { name: 'Peso muerto rumano con mancuernas pesadas', best: '32 kg × 10' }, { name: 'Extensión de cuádriceps', best: '45 kg × 12' }]
  },
  nado: { type: 'swim', ds: '2026-10-29', durationSec: 2280, distanceM: 1500 },
  yoga: { type: 'yoga', ds: '2026-10-28', durationSec: 2700 },
  rodada: { type: 'bike', title: 'Rodada larguísima por el malecón hasta Cerritos y de regreso', ds: '2026-10-27', durationSec: 5710, distanceM: 42300, elevationM: 210, avgHr: 148, effort: 7 },
  libre: { type: 'strength', title: 'Entreno libre', ds: '2026-10-26', durationSec: 1800 }
};
const F = Object.fromEntries(Object.entries(samples).map(([k, d]) => [k, S.workoutFacts(d)]));
assert.deepEqual([F.carrera.hero.value, F.carrera.hero.unit], ['10.02', 'KM'], 'una carrera presume sus kilómetros');
assert.deepEqual([F.fuerza.hero.value, F.fuerza.hero.label], ['4,320', 'KG MOVIDOS'], 'la fuerza, sus kilos');
assert.deepEqual([F.nado.hero.value, F.nado.hero.unit], ['1,500', 'M']);
assert.deepEqual([F.yoga.hero.value, F.yoga.hero.label], ['45', 'MINUTOS'], 'sin distancia ni series, los minutos');
assert.equal(F.nado.title, 'Nado', 'sin nombre, el nombre del tipo');
assert.equal(F.fuerza.bubble.replace(/\u00a0/g, ' '), 'Leg 2, listo. 52 min y 18 series.');
assert.ok(F.fuerza.bubble.includes('52\u00a0min'), 'la cifra va pegada a su unidad');
assert.equal(F.carrera.bubble.replace(/\u00a0/g, ' '), '10.02 km corridos. 52:14.');
assert.deepEqual(F.yoga.light, { value: '45', sub: 'minutos de yoga' }, 'lo registrado a mano no inventa segundos');
assert.deepEqual(F.carrera.light, { value: '52:14', sub: 'corriendo' });
const aMano = S.workoutFacts({ type: 'run', durationSec: 3120, distanceM: 10020 });
assert.equal(aMano.summary[1].replace(/\u00a0/g, ' '), '52 min', 'en minutos cerrados no inventa «52:00»');
assert.equal(aMano.bubble.replace(/\u00a0/g, ' '), '10.02 km corridos. 52 min.');
assert.equal(aMano.stats.find((x) => x.label === 'TIEMPO').value, '52 MIN');
assert.equal(F.carrera.stats.find((x) => x.label === 'TIEMPO').value, '52:14', 'con segundos, como reloj');
assert.deepEqual(F.carrera.trio.map((t) => t.label), ['KM', 'TIEMPO', 'MIN/KM']);
assert.ok(F.fuerza.summary.length <= 3);
assert.equal(S.workoutFacts({ type: 'strength', distanceM: 5000, durationSec: 600 }).dist, 0, 'la fuerza no lleva distancia');

const ids = S.KINDS.workout.styles.map((s) => s.id);
assert.equal(new Set(ids).size, ids.length, 'cada estilo con su id');
for (const [name, d] of Object.entries(samples)) {
  const usable = S.stylesFor('workout', d, measure).map((s) => s.id);
  assert.ok(usable.length >= 10, name + ': al menos diez estilos');
  for (const st of S.KINDS.workout.styles) {
    const L = st.layout(d, measure);
    if (!L) continue;
    assert.equal(L.kind, st.id, name + '/' + st.id);
    if (L.ops) inside(L, name + '/' + st.id);
    assert.ok(saysCrew(L), name + '/' + st.id + ' firma como HABIT Crew');
  }
}
// Los tres de la marca salen con cualquier entreno, aunque solo traiga minutos.
for (const [name, d] of Object.entries(samples)) {
  const usable = S.stylesFor('workout', d, measure).map((s) => s.id);
  ['crew', 'carnet', 'insignia'].forEach((id) => assert.ok(usable.includes(id), name + ' tiene ' + id));
}
const carnet = S.KINDS.workout.styles.find((s) => s.id === 'carnet').layout(samples.carrera, measure);
const carnetText = carnet.ops.filter((o) => o.op === 'text').map((o) => o.text);
assert.ok(carnetText.includes('habittraininghub.app/crew'), 'el carnet dice dónde se baja Crew');
assert.ok(carnetText.includes('10.02') && carnetText.includes('KM'), 'y lleva la cifra');
assert.ok(carnetText.includes('CORRER · 52:14 · 5:13 /KM'), 'abajo, lo que la cifra no dijo');
assert.ok(carnet.height - 80 >= Math.round((S.WIDTH - 80) / 1.586), 'con proporción de tarjeta');
const insignia = S.KINDS.workout.styles.find((s) => s.id === 'insignia').layout(samples.rodada, measure);
const ring = insignia.ops.find((o) => o.op === 'arc').chars.map((c) => c.ch).join('');
assert.ok(ring.startsWith('HABIT CREW · RODADA') && ring.includes('…'), 'la insignia recorta un nombre larguísimo');
const crewOps = S.KINDS.workout.styles.find((s) => s.id === 'crew').layout(samples.fuerza, measure).ops.filter((o) => o.op === 'text');
const [habitOp, crewOp] = crewOps;
assert.deepEqual([habitOp.text, crewOp.text], ['HABIT', 'CREW']);
assert.ok(Math.abs(habitOp.w - crewOp.w) < 1, 'HABIT se espacia al ancho exacto de CREW');
const recibo = S.KINDS.workout.styles.find((s) => s.id === 'recibo').layout(samples.fuerza, measure);
assert.ok(recibo.ops.some((o) => o.text === 'ENTRENO Nº 12'), 'el recibo lleva el número de entreno');
assert.ok(recibo.ops.some((o) => o.text && o.text.startsWith('SENTADILLA')), 'y los ejercicios');
const rb1 = JSON.stringify(S.KINDS.workout.styles.find((s) => s.id === 'recibo').layout(samples.fuerza, measure));
assert.equal(rb1, JSON.stringify(recibo), 'el código de barras es siempre el mismo para el mismo entreno');

// ── La semana ────────────────────────────────────────────────────────────
const wk = { count: 4, durationSec: 12000, distanceM: 21400, days: [1, 0, 1, 0, 1, 1, 0], weekStart: '2026-10-26', streak: 6 };
const wf = S.weekFacts(wk);
assert.equal(wf.range, '26.10 – 01.11');
assert.equal(wf.meta, '3 H 20 MIN · 21.4 KM');
for (const st of S.KINDS.week.styles) {
  const L = st.layout(wk, measure);
  assert.ok(L, st.id + ' sale con racha');
  assert.equal(L.kind, st.id);
  inside(L, 'semana/' + st.id);
  assert.ok(saysCrew(L), 'semana/' + st.id + ' firma como HABIT Crew');
}
const dots = S.KINDS.week.styles[0].layout(wk, measure).ops.filter((o) => o.op === 'circle');
assert.equal(dots.length, 7);
assert.equal(dots.filter((o) => !o.stroke).length, 4, 'un punto lleno por día entrenado');
assert.equal(S.KINDS.week.styles.find((s) => s.id === 'racha').layout({ count: 1, streak: 1 }, measure), null, 'una semana no es racha');



// La selección es el contrato del PNG: ni títulos ni métricas ocultas se recuperan.
for (const [kind, data] of [['workout', { ...samples.rodada, number: 47, kcal: 560 }], ['week', wk]]) {
  const fields = S.stickerFields(kind, data);
  const selections = [[], fields.map((r) => r.id), ...fields.map((r) => [r.id])];
  for (const selected of selections) {
    const d = { ...data, fields: selected };
    assert.deepEqual(S.selectedFields(kind, d).map((r) => r.id), selected.length === fields.length ? fields.map((r) => r.id) : selected);
    const styles = S.stylesFor(kind, d, measure);
    assert.equal(styles.length, 3, 'solo estilos que respetan la selección');
    for (const style of styles) {
      const L = style.layout(d, measure);
      inside(L, kind + '/personalizado/' + style.id);
      assert.ok(saysCrew(L), 'siempre firma como Crew');
      const logo = L.ops.find((o) => o.op === 'logo');
      assert.ok(logo.size >= 40 && logo.size <= 90, 'logo con tamaño estable');
      const text = L.ops.filter((o) => o.op === 'text').map((o) => o.text).join('|');
      if (!selected.includes('number')) assert.ok(!text.includes('Nº DE ENTRENO'));
      if (!selected.includes('avgHr')) assert.ok(!text.includes('FC MEDIA'));
      if (!selected.includes('title')) assert.ok(!text.includes(data.title?.toUpperCase() || 'TÍTULO AUSENTE'));
      if (!selected.length) assert.equal(L.ops.filter((o) => o.op === 'text').length, 3, 'sin selección: solo encabezado y marca');
    }
  }
}
assert.ok(!S.stickerFields('workout', samples.yoga).some((r) => r.id === 'avgHr'), 'no ofrece FC inexistente');
assert.equal(S.weekFacts({ count: 0 }).count, 0, 'cero no se inventa como un entreno');

console.log('HABIT Stickers: ok');
