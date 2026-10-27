// Las reglas de los avisos (web push) de app.html, sin navegador ni red: en qué estado está
// cada dispositivo y cuándo se le vuelve a preguntar.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const app = fs.readFileSync(path.join(__dirname, '../app.html'), 'utf8');
function between(start, end) {
  const first = app.indexOf(start);
  const last = app.indexOf(end, first);
  assert.ok(first >= 0 && last > first, `${start} found in app.html`);
  return app.slice(first, last);
}
const h = new Function(`
  ${between('function pushStateFor(', 'function pushEnv(')}
  ${between('const PUSH_ASK_KEY=', 'function readPushAskLog(')}
  return {pushStateFor, pushAskAllowed, PUSH_ASK_GAP_MS};
`)();

const env = (o) => ({ ios:false, standalone:false, native:false, supported:true, permission:'default', ...o });
assert.equal(h.pushStateFor(env({ ios:true })), 'install', 'iPhone en Safari: hay que agregarla a inicio');
assert.equal(h.pushStateFor(env({ ios:true, standalone:true })), 'default', 'iPhone con la app instalada puede pedir permiso');
assert.equal(h.pushStateFor(env({ ios:true, standalone:true, permission:'granted' })), 'granted', 'permiso ya dado');
assert.equal(h.pushStateFor(env({ ios:true, standalone:true, supported:false })), 'unsupported', 'iOS viejo instalado no tiene push');
assert.equal(h.pushStateFor(env({ permission:'denied' })), 'denied', 'Android bloqueado');
assert.equal(h.pushStateFor(env({ native:true, ios:true })), 'native', 'la app de la tienda no usa web push');
assert.equal(h.pushStateFor(env({ supported:false })), 'unsupported', 'navegador sin push');

const now = Date.UTC(2026, 9, 26);
assert.ok(h.pushAskAllowed({}, now), 'nunca preguntado');
assert.ok(!h.pushAskAllowed({ n:1, at:now - 864e5 }, now), 'no más de una vez por semana');
assert.ok(h.pushAskAllowed({ n:1, at:now - h.PUSH_ASK_GAP_MS }, now), 'pasada la semana, sí');
assert.ok(!h.pushAskAllowed({ n:3, at:now - 60 * 864e5 }, now), 'tres veces y se deja de preguntar');

console.log('HABIT Avisos: ok');
