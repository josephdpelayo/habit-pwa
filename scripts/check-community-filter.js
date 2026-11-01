// El filtro de palabras de la comunidad vive dos veces: en app.html para avisar al instante y en
// el trigger de la migración 138 para decidir. Esto falla si las dos listas se separan, y prueba
// la normalización de la app con los mismos casos con que se probó la 138 en Postgres.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const app = fs.readFileSync(path.join(__dirname, '../app.html'), 'utf8');
const sql = fs.readFileSync(path.join(__dirname, '../migrations/138_community_word_filter.sql'), 'utf8');
function between(src, start, end) {
  const first = src.indexOf(start);
  const last = src.indexOf(end, first);
  assert.ok(first >= 0 && last > first, `${start} found`);
  return src.slice(first, last);
}
const h = new Function(`
  ${between(app, 'const COMMUNITY_BLOCKED_TERMS=', 'function isCommunityTextError(')}
  return {COMMUNITY_BLOCKED_TERMS, communityTextBlocked, communityTextNormalize};
`)();

const sqlArray = between(sql, 'select array[', ']\n$$');
const sqlTerms = [...sqlArray.replace(/--.*$/gm, '').matchAll(/'([^']*)'/g)].map(m => m[1]);
assert.deepEqual([...h.COMMUNITY_BLOCKED_TERMS].sort(), [...sqlTerms].sort(), 'misma lista en app.html y en la 138');
for (const w of h.COMMUNITY_BLOCKED_TERMS)
  assert.equal(h.communityTextNormalize(w), w, `«${w}» está escrito ya normalizado (juntado)`);

const cases = [
  ['Buen entreno hoy', false], ['eres un PENDEJOOOO', true], ['p3nd3j0', true],
  ['qué pinche calor', false], ['la computadora', false], ['disputa', false],
  ['Chinga tu madre', true], ['kill yourself', true], ['te voy a matar en el WOD', true],
  ['Zorra', true], ['está bien verga', false], ['niño', false], ['mátate', true],
  ['Hijo de puta', true], ['putamadre', false], ['sin pendejadas', false], ['', false], [null, false],
];
for (const [t, exp] of cases) assert.equal(h.communityTextBlocked(t), exp, JSON.stringify(t));

console.log('HABIT Comunidad (filtro): ok');
