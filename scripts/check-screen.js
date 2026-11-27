// La pantalla del gym (habit-screen.js, pantalla.html, migración 152) sin navegador: que las
// dos apps y la tele carguen el módulo, que el service worker sepa de la página, que los
// textos estén en los dos idiomas, que la migración no le abra a anon más que la función de
// la tele, y —lo que más importa— que la tele arme la misma lista de ejercicios que la hoja
// de entreno: se corre sessionExerciseList de crew.html sobre los mismos datos.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const H = require('../habit-screen.js');

const root = path.join(__dirname, '..');
const read = (f) => fs.readFileSync(path.join(root, f), 'utf8');
const apps = { 'app.html': read('app.html'), 'crew.html': read('crew.html') };
const sw = read('sw.js');
const tvPage = read('pantalla.html');
const sql = read('migrations/152_gym_screen.sql');
const version = sw.match(/CACHE_VERSION = '([^']+)'/)[1];

// ── Quién lo carga ───────────────────────────────────────────────────────
for (const [file, html] of Object.entries(apps)) {
  for (const name of H.APP_GLOBALS) {
    const declared = new RegExp(`(function\\s+${name}\\s*\\(|(?:const|let|var)\\s+(?:[\\w$]+\\s*=[^;\\n]*,\\s*)*${name}\\s*[=,;])`).test(html);
    assert.ok(declared, `${file} no declara ${name}, que usa habit-screen.js`);
  }
  assert.ok(html.includes(`<script src="/habit-screen.js?v=${version}"></script>`), file + ' carga el módulo con la versión de sw.js');
  // Dónde se pone la sección y cuándo se invita: si cambian, el módulo deja de verse sin error.
  for (const id of ['s-main', 'v-inicio', 'v-perfil', 'perfil-blocks-section']) {
    assert.ok(html.includes(`id="${id}"`), `${file} tiene #${id}, que usa habit-screen.js`);
  }
  assert.ok(html.includes('workout-sheet-open'), file + ': la clase que dice que hay un entreno abierto');
}
assert.ok(tvPage.includes(`<script src="/habit-screen.js?v=${version}"></script>`), 'la tele carga el módulo con la versión de sw.js');
assert.ok(tvPage.includes(`const PANTALLA_VERSION='${version}'`), 'PANTALLA_VERSION es la versión del proyecto: así la tele se recarga sola con cada despliegue');
assert.ok(!/persistSession:true[^}]*\}\}\s*:\s*\{auth:\{persistSession:true/.test(tvPage) && /:\{auth:\{persistSession:false/.test(tvPage), 'la tele nunca guarda una sesión');
assert.ok(!/\bconst sb\s*=/.test(tvPage), 'la tele no llama «sb» a su cliente: el módulo creería que es una app');
assert.ok(!/innerHTML\s*=[^;]*\bp\.name\b(?![^;]*esc\()/.test(tvPage), 'el nombre se escapa');

// ── Service worker ───────────────────────────────────────────────────────
assert.ok(sw.includes("if (pathname === '/pantalla' || pathname.startsWith('/pantalla.html')) return '/pantalla.html';"), 'la tele tiene su propio shell: no pisa la copia offline de la app');
assert.ok(sw.includes("url.pathname === '/habit-screen.js'"), 'el módulo se sirve como los demás');
assert.ok(sw.includes('`/habit-screen.js?v=${CACHE_VERSION}`'), 'el módulo está en el shell (las apps no arrancan completas sin él)');
assert.ok(!/SHELL = \[[^\]]*pantalla/.test(sw), 'la tele no va en SHELL: sin red no hay nada que mostrar');
assert.ok(sw.includes('(skandi|competencia|pantalla)'), 'un aviso nunca enfoca la ventana de la tele');

// ── Textos en español e inglés (requisito permanente) ────────────────────
function shape(o) {
  if (typeof o === 'function') return 'fn';
  if (o && typeof o === 'object') return Object.fromEntries(Object.keys(o).sort().map((k) => [k, shape(o[k])]));
  return typeof o;
}
assert.deepEqual(shape(H.TEXT.en), shape(H.TEXT.es), 'cada texto existe en los dos idiomas');
for (const l of ['es', 'en']) {
  assert.equal(H.T(l).hiddenNow(1).length > 0 && H.T(l).hiddenNow(3).includes('3'), true);
  for (const v of ['hidden', 'name', 'routine']) assert.ok(H.T(l).vis[v] && H.T(l).visShort[v], l + ': ' + v);
}
assert.equal(H.lang('en-US'), 'en');
assert.equal(H.lang('es'), 'es');

// ── La misma lista de ejercicios que la hoja de entreno ──────────────────
const crew = apps['crew.html'];
const start = crew.indexOf('function sessionExerciseList(');
const end = crew.indexOf('\nfunction buildTrainingExerciseSnapshot(', start);
assert.ok(start > 0 && end > start, 'crew.html tiene sessionExerciseList');
// eslint-disable-next-line no-new-func
const makeCrewList = new Function('coachBoardsById', 'activeCoachingSession', 'coachSessionSets',
  crew.slice(start, end) + '\nreturn sessionExerciseList;');

const BOARD = 'b1';
const boardExercises = [
  { id: 'a', name: 'Sentadilla', sets: '3', reps: '8-10' },
  { name: 'Remo', sets: '3', reps: '12' },                    // sin id: su llave es b1_idx_1
  { id: 'c', name: 'Press', sets: '4', reps: '10-9-8-7', repsType: 'pyramid' },
  { id: 'd', name: 'Plancha', sets: '3', reps: '30s', repsType: 'time' }
];
const cases = {
  'la rutina sin cambios': { exercise_snapshot: [], session_exercises: [] },
  'con su copia de inicio': { exercise_snapshot: boardExercises.slice(0, 2).map((e, i) => ({ ...e, _exKey: e.id || BOARD + '_idx_' + i })), session_exercises: [] },
  'un cambio, un agregado y uno quitado': {
    exercise_snapshot: [],
    session_exercises: [
      { replaces: 'a', ex_key: 'x1', name: 'Prensa', sets: '3', reps: '10' },
      { ex_key: 'x2', name: 'Curl', sets: '2', reps: '12' },
      { replaces: 'd', removed: true }
    ],
    sets: { a: [{ set_idx: 0, done: true }, { set_idx: 1, done: false }], x1: [{ set_idx: 0, done: false }] }
  },
  'un cambio encadenado sobre uno agregado': {
    exercise_snapshot: [],
    session_exercises: [
      { ex_key: 'x2', name: 'Curl', sets: '2', reps: '12' },
      { replaces: 'x2', ex_key: 'x3', name: 'Curl martillo', sets: '2', reps: '12' },
      { replaces: 'x3', ex_key: 'x4', name: 'Curl cable', sets: '2', reps: '12' }
    ],
    sets: { x2: [{ set_idx: 0, done: true }], x3: [] }
  }
};
const strip = (list) => list.map((e) => ({ key: e._exKey, name: e.name, replaced: !!e._replaced, from: e._swappedFrom || null }));
for (const [label, c] of Object.entries(cases)) {
  const row = { id: 's1', board_id: BOARD, exercise_snapshot: c.exercise_snapshot, session_exercises: c.session_exercises };
  const crewSets = c.sets || {};
  const crewList = makeCrewList({ [BOARD]: { exercises: boardExercises } }, row, crewSets)(row, crewSets);
  // Lo que manda el servidor: la copia de la sesión o, si está vacía, la rutina.
  const routine = {
    board_id: BOARD,
    exercises: c.exercise_snapshot.length ? c.exercise_snapshot : boardExercises,
    overlay: c.session_exercises,
    sets: Object.entries(crewSets).flatMap(([k, rows]) => rows.map((s) => ({ k, i: s.set_idx, d: s.done })))
  };
  assert.deepEqual(strip(H.effectiveExercises(routine)), strip(crewList), 'la tele y la hoja coinciden: ' + label);
}

// ── Avance ───────────────────────────────────────────────────────────────
assert.equal(H.plannedSetCount({ sets: '4', reps: '10-9-8-7-6', repsType: 'pyramid' }), 5, 'una pirámide tiene una serie por escalón');
assert.equal(H.plannedSetCount({ sets: '' }), 1);
assert.equal(H.plannedSetCount({ sets: '3', reps: '8-10' }), 3, 'un rango no es pirámide');

const planned = H.progress({ board_id: BOARD, exercises: boardExercises, overlay: [], sets: [] });
assert.deepEqual([planned.done, planned.total, planned.current], [0, 3 + 3 + 4 + 3, 0], 'sin empezar cuenta lo planeado');

const live = H.progress({
  board_id: BOARD, exercises: boardExercises.slice(0, 2), overlay: [],
  sets: [
    { k: 'a', i: 0, d: true, w: 60 }, { k: 'a', i: 1, d: true, w: 62.5 }, { k: 'a', i: 2, d: true, w: 0 },
    { k: BOARD + '_idx_1', i: 0, d: true }, { k: BOARD + '_idx_1', i: 1, d: false }, { k: BOARD + '_idx_1', i: 2, d: false },
    { k: BOARD + '_idx_1', i: 3, d: false }
  ]
});
assert.deepEqual([live.done, live.total, live.current], [4, 7, 1], 'con series sembradas cuentan las de verdad (una agregada de más incluida)');
assert.equal(live.items[0].lastWeight, 62.5, 'el último peso hecho, sin contar una serie sin peso');
assert.equal(H.targetLabel(live.items[1]), '4 × 12');
assert.equal(H.targetLabel({ total: 4, reps: '10-9-8-7', repsType: 'pyramid' }), '10-9-8-7');

const swapped = H.progress({ board_id: BOARD, exercises: [boardExercises[0]], overlay: [{ replaces: 'a', ex_key: 'x1', name: 'Prensa', sets: '3', reps: '10' }],
  sets: [{ k: 'a', i: 0, d: true }, { k: 'x1', i: 0, d: false }, { k: 'x1', i: 1, d: false }] });
assert.deepEqual(swapped.items.map((i) => [i.name, i.replaced, i.done, i.total]), [['Sentadilla', true, 1, 1], ['Prensa', false, 0, 2]], 'lo hecho antes de cambiar se queda, sin series pendientes');
assert.equal(swapped.current, 1);

assert.equal(H.mazDs(Date.parse('2026-11-25T06:30:00Z')), '2026-11-24', 'a las 11:30 pm de Mazatlán todavía es el mismo día');
assert.equal(H.addDays('2026-11-30', 1), '2026-12-01');

// ── La migración ─────────────────────────────────────────────────────────
// Lo que effectiveExercises lee de cada ejercicio tiene que sobrevivir al recorte del servidor.
for (const k of ['id', '_exKey', 'ex_key', 'replaces', 'removed', 'name', 'sets', 'reps', 'repsType']) {
  assert.ok(sql.includes(`'${k}', e->'${k}'`), 'gym_screen_trim conserva ' + k);
}
for (const k of ['k', 'i', 'd', 't', 'r', 'w', 's']) assert.ok(new RegExp(`'${k}', c\\.`).test(sql), 'cada serie lleva ' + k);
assert.ok(/grant select \(id, name, mode, lang, updated_at\) on public\.gym_screens to anon, authenticated;/.test(sql), 'la llave de la tele no se puede leer');
assert.ok(/revoke all on public\.gym_screens from public, anon, authenticated;/.test(sql), 'se quita el permiso de tabla completa que Supabase da por defecto');
const anonGrants = [...sql.matchAll(/grant execute on function ([\w.]+)\([^)]*\) to ([^;]+);/g)].filter((m) => /\banon\b/.test(m[2])).map((m) => m[1]);
assert.deepEqual(anonGrants, ['public.gym_screen_state'], 'anon solo ejecuta la función de la tele');
for (const fn of ['gym_screen_bump', 'gym_screen_trim', 'gym_screen_short_name', 'gym_screen_routine', 'gym_screen_state', 'gym_screen_admin', 'gym_screen_configure', 'gym_screen_prefs_touch']) {
  assert.ok(new RegExp(`revoke all on function public\\.${fn}\\([^)]*\\) from public, anon, authenticated;`).test(sql), fn + ' empieza sin permisos');
}
assert.ok(/visibility\s+text not null default 'hidden'/.test(sql), 'nadie sale hasta activarlo');
assert.ok(/coalesce\(p\.visibility, 'hidden'\)/.test(sql), 'sin fila cuenta como no aparecer');
assert.ok(/filter \(where v\.visibility <> 'hidden'\)/.test(sql), 'lo de quien no lo activó no sale de la base');
assert.ok(/mode\s+text not null default 'off'/.test(sql), 'la pantalla nace apagada: nadie recibe la invitación antes de que exista');
assert.ok(/exception when others then\s+null;/.test(sql), 'un error al avisar a la tele nunca tumba una serie');

// ── Fase 2: transmitir (migración 153) ───────────────────────────────────
const sql153 = read('migrations/153_gym_screen_casts.sql');
for (const [file, html] of Object.entries(apps)) {
  // El botón se pone en la barra de la hoja de entreno, antes de minimizar.
  assert.ok(/<div id="workout-sheet" class="workout-sheet">\s*<div class="ws-bar">/.test(html), file + ': la hoja de entreno tiene su barra');
  assert.ok(html.includes('class="ws-min"'), file + ': el botón de minimizar, antes del cual va «Pantalla»');
}
assert.deepEqual(H.CAST_IN, { crew: true, habit: false }, 'fase 2: se transmite desde Crew; HABIT es la fase 3');
const anon153 = [...sql153.matchAll(/grant execute on function ([\w.]+)\([^)]*\) to ([^;]+);/g)].filter((m) => /\banon\b/.test(m[2])).map((m) => m[1]);
assert.deepEqual(anon153, ['public.gym_screen_state'], 'anon sigue sin ejecutar más que la función de la tele');
for (const fn of ['start_gym_cast', 'update_gym_cast', 'stop_gym_cast']) {
  assert.ok(new RegExp(`grant execute on function public\\.${fn}\\([^)]*\\) to authenticated;`).test(sql153), fn + ' es de quien tiene sesión');
  assert.ok(new RegExp(`revoke all on function public\\.${fn}\\([^)]*\\) from public, anon, authenticated;`).test(sql153), fn + ' empieza sin permisos');
}
assert.ok(/revoke all on public\.gym_screen_casts from public, anon, authenticated;/.test(sql153) && !/grant (insert|update|delete)[^;]*gym_screen_casts/.test(sql153), 'la transmisión solo se escribe por RPC');
assert.ok(/gym_screen_booking_end\(v_uid\)/.test(sql153) && /'NO_BOOKING'/.test(sql153), 'sin reserva corriendo no se transmite');
assert.ok(/v_others >= 4/.test(sql153), 'máximo 4 por pantalla, el cupo');
assert.ok(/after update of status on public\.coaching_schedule/.test(sql153), 'cerrar el entreno quita la transmisión');
assert.ok(/cron\.schedule\('habit-gym-screen-casts'/.test(sql153), 'lo vencido se limpia solo');
assert.ok(/case when cs\.user_id is not null then 'routine'/.test(sql153), 'quien transmite sale aunque su preferencia de Perfil sea no aparecer');
assert.ok(/drop function if exists public\.gym_screen_configure\(text, text, text, boolean, boolean\);/.test(sql153), 'la firma vieja del control se retira: dos candidatas confunden a PostgREST');
// Los códigos que devuelve el servidor tienen texto en los dos idiomas.
for (const code of new Set([...sql153.matchAll(/'error', '([A-Z_]+)'/g)].map((m) => m[1]).filter((c) => c !== 'KEY'))) {
  for (const l of ['es', 'en']) assert.ok(H.TEXT[l].castErr[code], `${l}: castErr.${code}`);
}
assert.equal(H.T('es').setOf(2, 4), 'Serie 2 de 4');
assert.equal(H.T('en').setOf(2, 4), 'Set 2 of 4');
// La tele lee del teléfono solo lo que la 153 manda.
for (const k of ['focus_key', 'focus_idx', 'rest_end_at', 'rest_frozen_s', 'rest_total_s', 'updated_at']) {
  assert.ok(sql153.includes(`'${k}'`), 'gym_screen_state manda ' + k);
  assert.ok(tvPage.includes(k), 'la tele usa ' + k);
}

// ── La rutina del día (migración 156) ────────────────────────────────────
const sql156 = read('migrations/156_gym_screen_daily.sql');
assert.deepEqual(H.pickMedia(['https://youtube.com/shorts/AUSCLBlE9tg?si=fQTkFNohFDpfo9Jn']), { kind: 'youtube', id: 'AUSCLBlE9tg' }, 'un Short del gym');
assert.deepEqual(H.pickMedia(['https://www.youtube.com/watch?v=dZJETBH7mK4&t=3']), { kind: 'youtube', id: 'dZJETBH7mK4' });
assert.deepEqual(H.pickMedia(['https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQr/view?usp=drive_link']), { kind: 'drive', id: '1AbCdEfGhIjKlMnOpQr' });
assert.deepEqual(H.pickMedia(['texto suelto', '/skill-anim/hollow-hold.svg', 'https://youtu.be/xyzxyz12']), { kind: 'image', url: '/skill-anim/hollow-hold.svg', anim: true }, 'lo que no es medio se salta; manda el orden del servidor');
assert.equal(H.pickMedia(['https://fitnessprogramer.com/x/Barbell-Squat.gif']).kind, 'image');
assert.equal(H.pickMedia(['https://x.com/a.mp4?v=2']).kind, 'video');
assert.equal(H.pickMedia([]), null);
assert.equal(H.pickMedia(['javascript:alert(1)']), null, 'solo http(s) o rutas del sitio');
for (const l of ['es', 'en']) assert.ok(H.TEXT[l].daily && H.TEXT[l].dailyCount(3).includes('3'), l + ': textos de la rutina del día');
const anon156 = [...sql156.matchAll(/grant execute on function ([\w.]+)\([^)]*\) to ([^;]+);/g)].filter((m) => /\banon\b/.test(m[2])).map((m) => m[1]);
assert.deepEqual(anon156, ['public.gym_screen_daily'], 'anon solo pide la rutina del día, con la llave de la tele');
assert.ok(/v_screen\.access_key <> p_key/.test(sql156), 'la rutina del día pide la llave de la pantalla');
for (const fn of ['gym_screen_norm', 'gym_screen_daily_board', 'gym_screen_daily', 'gym_screen_set_daily', 'gym_screen_daily_options']) {
  assert.ok(new RegExp(`revoke all on function public\\.${fn}\\([^)]*\\) from public, anon, authenticated;`).test(sql156), fn + ' empieza sin permisos');
}
assert.ok(/b\.is_starter and b\.owner_id is null and b\.archived_at is null/.test(sql156), 'rota entre las básicas del gym');
assert.ok(!/'note'|e->'note'|e->>'note'/.test(sql156), 'no manda las notas del coach');
assert.ok(/reload_nonce = reload_nonce \+ 1/.test(sql156), 'cambiar la rutina recarga la tele al momento');
assert.ok(tvPage.includes("tv.rpc('gym_screen_daily'"), 'la tele pide la rutina del día');
assert.ok(/pointer-events:none/.test(tvPage), 'los videos no reaccionan a un cursor');
assert.ok(tvPage.includes('youtube-nocookie.com/embed/'), 'YouTube sin cookies');

console.log('check-screen: ok');
