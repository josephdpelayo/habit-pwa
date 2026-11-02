// Flujo real del endpoint con servicios en memoria: sin reloj, red ni credenciales reales.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const I = require('../skandi-intervals.js');

const strength = { id: 'g-strength', source: 'GARMIN_CONNECT', type: 'WeightTraining', name: 'Upper A',
  start_date: '2026-10-27T14:00:00Z', elapsed_time: 3600, moving_time: 1200,
  average_heartrate: 128, max_heartrate: 166, calories: 370, device_name: 'Venu 4' };
const row = I.toActivityRow(strength, { userId: 'u1' });
assert.equal(row.duration_min, 60, 'fuerza incluye los descansos');
assert.equal(row.external_type, 'WeightTraining');
assert.equal(row.distance_km, null);
assert.ok(!('sets' in row), 'no inventa series ni repeticiones');
assert.equal(I.toActivityRow({ ...strength, source: 'STRAVA' }, { userId: 'u1' }), null);
assert.equal(I.toActivityRow({ ...strength, elapsed_time: -1 }, { userId: 'u1' }), null);
assert.equal(I.toActivityRow({ ...strength, start_date: 'inválida' }, { userId: 'u1' }), null);
for (const type of ['StrengthTraining', 'Functional Strength Training', 'Crossfit']) {
  assert.ok(I.toActivityRow({ ...strength, type }, { userId: 'u1' }), type + ' también se importa');
}
const running = { ...strength, id: 'g-run', type: 'Run', distance: 5000, moving_time: 1800, elapsed_time: 2400 };
assert.equal(I.toActivityRow(running, { userId: 'u1' }).duration_min, 30, 'carrera conserva moving_time');

const tables = { skandi_sessions: [], skandi_settings: [], skandi_external_activities: [],
  skandi_intervals_credentials: [], skandi_daily_wellness: [], skandi_bodyweight_logs: [] };
let nextId = 0, failSessionUpdate = false;
class Query {
  constructor(table) { this.table = table; this.filters = []; this.operation = 'select'; }
  select() { return this; }
  eq(k, v) { this.filters.push(r => r[k] === v); return this; }
  in(k, vs) { this.filters.push(r => vs.includes(r[k])); return this; }
  gte(k, v) { this.filters.push(r => r[k] >= v); return this; }
  lte(k, v) { this.filters.push(r => r[k] <= v); return this; }
  not(k, op, v) { assert.equal(op, 'is'); this.filters.push(r => r[k] != v); return this; }
  insert(rows) { this.operation = 'insert'; this.value = rows; return this; }
  update(value) { this.operation = 'update'; this.value = value; return this; }
  delete() { this.operation = 'delete'; return this; }
  maybeSingle() { this.single = true; return this; }
  then(resolve, reject) {
    try {
      const all = tables[this.table]; assert.ok(all, 'tabla conocida: ' + this.table);
      const matches = all.filter(r => this.filters.every(f => f(r)));
      let error = null;
      if (this.operation === 'insert') {
        for (const r of this.value) {
          assert.ok(!all.some(x => x.user_id === r.user_id && x.external_source === r.external_source && x.external_id === r.external_id), 'no duplica id de origen');
          all.push({ ...r, id: 'row-' + ++nextId });
        }
      } else if (this.operation === 'update') {
        if (this.table === 'skandi_sessions' && failSessionUpdate) error = { message: 'fallo simulado' };
        else matches.forEach(r => Object.assign(r, this.value));
      } else if (this.operation === 'delete') tables[this.table] = all.filter(r => !matches.includes(r));
      return Promise.resolve({ data: this.single ? matches[0] || null : matches.map(r => ({ ...r })), error }).then(resolve, reject);
    } catch (e) { return Promise.reject(e).then(resolve, reject); }
  }
}
const db = { from: t => new Query(t), auth: { getUser: async () => ({ data: { user: { id: 'u1' } } }) } };
const apiFile = path.join(__dirname, '../api/skandi.js');
const apiRequire = createRequire(apiFile);
const sandbox = { module: { exports: {} }, process: { env: { SUPABASE_URL: 'https://example.test', SUPABASE_SERVICE_ROLE_KEY: 'test-only' } },
  Buffer, URL, console: { ...console, error: () => {} },
  require: name => name === '@supabase/supabase-js' ? { createClient: () => db } : name === '@anthropic-ai/sdk' ? class {} : apiRequire(name),
  fetch: async url => ({ ok: true, status: 200, json: async () => String(url).includes('/wellness') ? [] : [strength, running] }) };
vm.runInNewContext(fs.readFileSync(apiFile, 'utf8') + '\nmodule.exports.encryptTestKey = encryptIntervalsKey;', sandbox);
const handler = sandbox.module.exports;
tables.skandi_intervals_credentials.push({ user_id: 'u1', athlete_id: 'athlete', api_key_ciphertext: handler.encryptTestKey('test-key') });
async function sync() {
  const res = { setHeader() {}, status(code) { this.code = code; return this; }, json(body) { this.body = body; return this; } };
  await handler({ method: 'POST', headers: { authorization: 'Bearer test-token' }, body: { action: 'intervals-sync', days: 120 } }, res);
  return res;
}
const ours = () => tables.skandi_external_activities.filter(r => r.user_id === 'u1');
(async () => {
  let res = await sync();
  assert.equal(res.code, 200);
  assert.equal(res.body.imported, 2, 'importa fuerza sin haber iniciado HABIT o Skandi');
  assert.equal(res.body.unmatched_strength, 1);
  assert.equal(ours().length, 2);
  const independent = ours().find(r => r.external_id === strength.id);
  independent.intensity = 9; independent.intensity_source = 'manual';
  res = await sync();
  assert.equal(res.body.imported, 0);
  assert.equal(res.body.updated, 2);
  assert.equal(ours().length, 2, 'repetir sync no duplica');
  assert.equal(ours().find(r => r.external_id === strength.id).intensity, 9, 'respeta esfuerzo corregido');
  tables.skandi_external_activities.push({ ...independent, id: 'other-user', user_id: 'u2' });
  tables.skandi_external_activities.push({ id: 'manual-other', user_id: 'u1', activity_type: 'other', performed_at: strength.start_date, duration_min: 60, external_source: null, external_type: null, note: 'Otra actividad manual' });
  res = await sync();
  assert.ok(ours().some(r => r.id === 'manual-other' && r.external_source === null), 'no absorbe fuerza en un other manual');
  tables.skandi_sessions.push({ id: 'session', user_id: 'u1', title: 'Upper A', started_at: strength.start_date,
    completed_at: '2026-10-27T15:00:00Z', duration_sec: 3100, duration_source: 'manual', garmin_external_id: null });
  failSessionUpdate = true;
  res = await sync();
  assert.equal(res.code, 502);
  assert.ok(ours().some(r => r.external_id === strength.id), 'no borra la copia si falla guardar la sesión');
  failSessionUpdate = false;
  res = await sync();
  assert.equal(res.code, 200);
  assert.equal(res.body.matched_strength, 1);
  assert.equal(ours().filter(r => r.external_id === strength.id).length, 0, 'al enlazar queda una sola representación');
  assert.equal(tables.skandi_sessions[0].garmin_external_id, strength.id);
  assert.equal(tables.skandi_sessions[0].duration_sec, 3100, 'no pisa duración manual');
  assert.equal(tables.skandi_sessions[0].garmin_avg_heart_rate, 128);
  assert.ok(tables.skandi_external_activities.some(r => r.user_id === 'u2'), 'no toca actividades de otra persona');
  res = await sync();
  assert.equal(res.body.imported, 0, 'la sesión enlazada no reaparece como externa');
  tables.skandi_sessions[0].started_at = '2026-09-01T14:00:00Z';
  res = await sync();
  assert.equal(res.body.imported, 0, 'respeta enlaces existentes aunque la sesión quede fuera de la ventana');
  console.log('HABIT Intervals: importación independiente, repetición y enlace de fuerza OK');
})().catch(e => { console.error(e); process.exitCode = 1; });
