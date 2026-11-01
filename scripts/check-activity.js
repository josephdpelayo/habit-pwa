// La sección Actividad (habit-activity.js) sin navegador: que las dos apps le den lo que usa,
// que la pestaña de HABIT caiga en su vista, y cómo cada fuente se vuelve un renglón — los
// entrenos de la app, lo registrado a mano, Skandi y lo que llega del reloj por Intervals.icu.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
global.HabitShare = require('../habit-share.js');
const A = require('../habit-activity.js');

const root = path.join(__dirname, '..');
const read = (f) => fs.readFileSync(path.join(root, f), 'utf8');
const apps = { 'app.html': read('app.html'), 'crew.html': read('crew.html') };

// ── Las dos apps ─────────────────────────────────────────────────────────
const version = read('sw.js').match(/CACHE_VERSION = '([^']+)'/)[1];
for (const [file, html] of Object.entries(apps)) {
  for (const name of A.APP_GLOBALS) {
    const declared = new RegExp(`(function\\s+${name}\\s*\\(|(?:const|let|var)\\s+(?:[\\w$]+\\s*=[^;\\n]*,\\s*)*${name}\\s*[=,;])`).test(html);
    assert.ok(declared, `${file} no declara ${name}, que usa habit-activity.js`);
  }
  assert.ok(html.includes(`<script src="/habit-activity.js?v=${version}"></script>`), file + ' carga el módulo con la versión de sw.js');
  assert.ok(html.includes('<div id="actividad-content">'), file + ' tiene dónde pintarla');
  assert.ok(/ALL_VIEWS=\[[^\]]*'actividad'/.test(html), file + ': actividad es una vista');
  assert.ok(/if\(v==='actividad'&&window\.HabitActivity\)\{HabitActivity\.render\(/.test(html), file + ': sv() la pinta');
  // El orden de los botones de abajo es el de la lista que los marca: HABIT los empata por
  // posición, y una pestaña de más corría la marca de las siguientes.
  const nav = html.slice(html.indexOf('<div class="bnav">'));
  const order = [...nav.slice(0, nav.indexOf('</div>\n  </div>')).matchAll(/class="bnb[^"]*" onclick="sv\('(\w+)'\)/g)].map((m) => m[1]);
  const list = (html.match(/const name=\[([^\]]+)\]\[i\]/) || html.match(/const BNAV_VIEWS=\[([^\]]+)\]/))[1].split(',').map((s) => s.trim().replace(/'/g, ''));
  assert.deepEqual(order, list, file + ': los botones de abajo en el orden de su lista');
  assert.ok(order.includes('actividad'), file + ' tiene la pestaña Actividad');
}
assert.ok(read('sw.js').includes("url.pathname === '/habit-activity.js'"), 'el service worker la guarda como los demás módulos');
assert.ok(!/function (renderActividad|actOpenForm|loadActividadSb)\b/.test(apps['crew.html']), 'Crew ya no trae su propia copia');

// ── Del reloj y de Skandi ────────────────────────────────────────────────
assert.equal(A.typeFromSkandi('running'), 'run');
assert.equal(A.typeFromSkandi('cycling', 'VirtualRide'), 'bike');
assert.equal(A.typeFromSkandi('swimming'), 'swim');
assert.equal(A.typeFromSkandi('hyrox'), 'cardio');
assert.equal(A.typeFromSkandi('other', 'Yoga'), 'yoga', 'un «other» que era yoga');
assert.equal(A.typeFromSkandi('other', 'Hike'), 'walk');
assert.equal(A.typeFromSkandi('other', 'Soccer'), 'sport');
assert.equal(A.typeFromSkandi('other', 'Workout'), 'other');
assert.equal(A.typeFromSkandi('other', null), 'other');

const h = { dsOf: (iso) => (iso ? new Date(Date.parse(iso) - 7 * 3600e3).toISOString().slice(0, 10) : ''), routineName: (n) => n };
const run = A.itemFromSkandiActivity({
  id: 'r1', activity_type: 'running', external_source: 'intervals', external_type: 'Run', performed_at: '2026-10-31T02:30:00+00:00',
  duration_min: 52, distance_km: 10.02, elevation_gain_m: 41, avg_heart_rate: 151, calories: 640, intensity: 7, note: 'Malecón 10K'
}, h);
assert.equal(run.ds, '2026-10-30', 'una carrera de las 7:30 pm en Mazatlán es de ese día, no del siguiente en UTC');
assert.deepEqual([run.src, run.type, run.title, run.named], ['intervals', 'run', 'Malecón 10K', true], 'del reloj, con su nombre');
assert.deepEqual([run.durationSec, run.distanceM, run.elevationM, run.avgHr, run.kcal, run.effort], [3120, 10020, 41, 151, 640, 7]);
assert.equal(run.notes, '');
const swim = A.itemFromSkandiActivity({ id: 's1', activity_type: 'swimming', external_source: 'intervals', performed_at: '2026-09-03T15:00:00Z', duration_min: 38, distance_km: 1.5 }, h);
assert.deepEqual([swim.type, swim.title, swim.distanceM], ['swim', 'Nado', 1500], 'sin nombre, el nombre del tipo; nadar en metros');
const byHand = A.itemFromSkandiActivity({ id: 'm1', activity_type: 'cycling', external_source: null, performed_at: '2026-09-01T14:00:00Z', duration_min: 45, note: 'Bici fija en el gym del barco' }, h);
assert.deepEqual([byHand.src, byHand.title, byHand.named, byHand.notes], ['skandi', 'Rodada', false, 'Bici fija en el gym del barco'], 'en Skandi a mano, la nota es nota');
const odd = A.itemFromSkandiActivity({ id: 'o1', activity_type: 'running', performed_at: '2026-09-01T14:00:00Z', duration_min: 30, avg_heart_rate: 999, intensity: 42 }, h);
assert.deepEqual([odd.avgHr, odd.effort], [0, 0], 'lo que no cabe en su rango no se enseña');

const ses = A.itemFromSkandiSession({ id: 'k1', title: 'Upper A', started_at: '2026-08-31T13:00:00Z', completed_at: '2026-08-31T14:05:00Z', duration_sec: null, garmin_avg_heart_rate: 118 }, h);
assert.deepEqual([ses.key, ses.src, ses.type, ses.title, ses.durationSec, ses.avgHr], ['k:k1', 'skandi', 'strength', 'Upper A', 3900, 118], 'sin duración, la de inicio a fin');
assert.equal(A.itemFromSkandiSession({ id: 'k2', started_at: '2026-08-31T13:00:00Z', completed_at: '2026-09-02T13:00:00Z' }, h).durationSec, 0, 'una sesión olvidada abierta dos días no dura dos días');
assert.equal(A.itemFromSkandiSession({ id: 'k3', started_at: '2026-08-31T13:00:00Z', completed_at: '2026-08-31T14:00:00Z' }, h).title, 'Fuerza');

const app = A.itemFromAppSession({ id: 'c1', ds: '2026-10-30', board_name: 'Leg 2', board_color: '#ff0000', duration_sec: 3134, completed_at: '2026-10-30T20:00:00Z' }, h);
assert.deepEqual([app.key, app.src, app.title, app.color], ['s:c1', 'app', 'Leg 2', '#ff0000']);
const manual = A.itemFromManual({ id: 'a1', kind: 'walk', ds: '2026-10-29', duration_sec: 1800, created_at: '2026-10-29T18:00:00Z' });
assert.deepEqual([manual.key, manual.src, manual.title, manual.named], ['a:a1', 'manual', 'Caminata', false]);

// Lo más nuevo arriba (dentro de un día, por la hora), y el Nº cuenta lo de antes.
const items = A.numberItems([app, run, swim, ses, manual], 40);
assert.deepEqual(items.map((it) => it.key), ['x:r1', 's:c1', 'a:a1', 'x:s1', 'k:k1'], 'el 30: la carrera de la noche arriba del entreno de la 1 pm');
assert.deepEqual(items.map((it) => it.number), [45, 44, 43, 42, 41]);

// ── Sincronizar con el reloj ─────────────────────────────────────────────
const now = Date.parse('2026-11-01T18:00:00Z');
assert.equal(A.syncWindowDays(null, now), 120, 'la primera vez, lo que enseña la lista');
assert.equal(A.syncWindowDays('2026-09-07T11:41:25Z', now), 58, 'desde la última vez, con dos días de colchón');
assert.equal(A.syncWindowDays('2026-11-01T17:00:00Z', now), 3, 'nunca menos de tres días');
assert.equal(A.syncWindowDays('2025-01-01T00:00:00Z', now), 120, 'ni más de cuatro meses');
assert.equal(A.syncDue(null, now), true);
assert.equal(A.syncDue('2026-11-01T17:50:00Z', now), false, 'hace diez minutos: no');
assert.equal(A.syncDue('2026-11-01T17:30:00Z', now), true, 'hace media hora: sí');

// ── El sticker de un entreno de Skandi ───────────────────────────────────
assert.equal(A.skandiBestSet([{ weight_kg: 20, reps: 6 }, { weight_kg: 22.5, reps: 4 }, { weight_kg: 22.5, reps: 5 }]), '22.5 kg × 5', 'la más pesada, y con empate la de más reps');
assert.equal(A.skandiBestSet([{ seconds: 12 }, { seconds: 18 }]), '18 s', 'un estático, en segundos');
assert.equal(A.skandiBestSet([{ reps: 8 }, { reps: 11 }]), '11 reps');
const sticker = A.skandiStickerData([
  { exercise_id: 'pu', set_idx: 1, sort_order: 0, weight_kg: 10, reps: 6, done: true },
  { exercise_id: 'pu', set_idx: 0, sort_order: 0, weight_kg: 12.5, reps: 5, done: true },
  { exercise_id: 'fl', set_idx: 0, sort_order: 1, seconds: 15, done: true },
  { exercise_id: 'fl', set_idx: 1, sort_order: 1, seconds: 20, done: false }
], { pu: 'Dominada con lastre', fl: 'Front lever tuck' }, { title: 'Pull A', ds: '2026-08-31', durationSec: 3900, number: 12 });
assert.deepEqual([sticker.sets, sticker.volumeKg, sticker.exerciseCount], [3, 123, 2], 'solo las series hechas; el volumen es el lastre por las reps');
assert.deepEqual(sticker.exercises, [{ name: 'Dominada con lastre', best: '12.5 kg × 5' }, { name: 'Front lever tuck', best: '15 s' }]);
const facts = global.HabitShare.workoutFacts(sticker);
assert.equal(facts.title, 'Pull A');
assert.equal(facts.number, 12);

console.log('HABIT Actividad: ok');
