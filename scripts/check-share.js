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
  assert.ok(L.size >= 40 && L.size <= 76, 'tamaño de letra en rango');
  assert.equal(L.font.includes(L.size + 'px'), true, 'los renglones son del tamaño que se dibuja');
  const inner = S.WIDTH - 72 * 2;
  L.lines.forEach((l) => assert.ok(measure(l.text, L.font) <= inner + 0.5, 'ningún renglón se sale'));
  assert.equal(L.lines.map((l) => l.text).join(' '), '“' + q + '”', 'no se pierde ni se agrega texto');
  const lk = L.lockup;
  assert.ok(lk.logo.y + lk.logo.size <= L.height, 'el logotipo cabe en el lienzo');
  assert.ok(lk.logo.x >= 0 && lk.word.x + measure('HABIT', lk.word.font) <= L.width, 'el logotipo no se sale');
  assert.ok(Math.abs((lk.logo.x + lk.width / 2) - L.width / 2) < 1, 'el logotipo va centrado');
  assert.ok(L.font.includes('Inter') && lk.word.font.startsWith('800'), 'Inter, la fuente de HABIT');
  assert.equal(L.width, 1080);
}
const long = S.quoteLayout(quotes[2], measure);
const short = S.quoteLayout(quotes[1], measure);
assert.ok(long.size < short.size, 'la frase larga baja de tamaño');

const sig = S.signatureLayout(measure);
assert.ok(sig.lockup.logo.x >= 0 && sig.lockup.logo.x + sig.lockup.width <= sig.width + 0.5, 'la firma cabe a lo ancho');
assert.ok(sig.sub.y <= sig.height, 'MAKE IT A HABIT cabe');
assert.equal(sig.lockup.word.text, 'HABIT');

assert.deepEqual(Object.keys(S.COLORS), ['blanco', 'negro'], 'solo blanco y negro');

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
  assert.ok(L.logo.size < L.radius * 2 - L.size * 2, 'el logo no toca las letras');
}
assert.ok(S.sealLayout('MAKE IT A HABIT · ENTRENO Nº 47 · SEMANA 6 · LEG 2 · ', measure).size
  <= S.sealLayout('MAKE IT A HABIT · ', measure).size, 'el texto largo no crece');

assert.equal(S.shortDate('2026-10-31'), '31.10.26');
assert.equal(S.shortDate(''), '');

// La galería de la frase del día: tres estilos, y cada uno se dispone con los datos de la frase.
assert.deepEqual(S.KINDS.quote.styles.map((s) => s.id), ['frase', 'logotipo', 'sello']);
for (const st of S.KINDS.quote.styles) {
  const L = st.layout({ text: quotes[0], ds: '2026-10-31' }, measure);
  assert.ok(L.width > 0 && L.height > 0, st.id + ' tiene tamaño');
  assert.equal(L.kind, st.id);
}
const sello = S.KINDS.quote.styles[2].layout({ text: quotes[0], ds: '2026-10-31' }, measure);
assert.ok(sello.chars.map((c) => c.ch).join('').includes('31.10.26'), 'el sello lleva la fecha');
assert.ok(S.chipHtml().includes('Compartir'), 'el botón dice Compartir');

console.log('HABIT Stickers: ok');
