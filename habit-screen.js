// HABIT Screen — la pantalla del gym (docs/PANTALLA_GYM.md, migración 152).
//
// Lo cargan tres páginas y cada una usa su parte:
//   pantalla.html — la tele. Usa lo puro: armar la lista de ejercicios de una rutina con lo
//                   que manda gym_screen_state(), el avance de cada quien y los textos ES/EN.
//   app.html (HABIT, congelada: Joseph aceptó esta línea el 24 nov 2026) y crew.html — el
//                   ajuste «Pantalla del gym» en Perfil y la invitación, una sola vez, a quien
//                   tiene reserva. Nadie sale en la tele hasta que lo activa: la fila nace
//                   'hidden' y una persona sin fila cuenta como 'hidden' (lo decide el servidor).
// Se pinta solo, sin llamadas desde la app: pone su sección antes de «Usuarios bloqueados»
// (#perfil-blocks-section, que tienen las dos) y mira qué vista está abierta. Con la pantalla
// apagada (gym_screens.mode = 'off') o sin la 152 corrida no enseña nada.
//
// effectiveExercises es la misma regla que sessionExerciseList de crew.html, sin globales:
// scripts/check-screen.js corre las dos sobre los mismos datos y falla si se separan.
(function (global) {
  'use strict';

  // Lo que se usa de la app, por su nombre global. scripts/check-screen.js falla si a alguna
  // de las dos le falta uno.
  // Transmitir lee la sesión en curso, la serie que toca y el descanso tal como los lleva la
  // hoja de entreno (variables de nivel superior de las apps; se leen por nombre, no por window).
  const APP_GLOBALS = ['sb', 'sbUser', 'toast', 'IS_CREW', 'activeCoachingSession', 'wsFocusSet',
    'wsPausedAt', 'wsRestEndAt', 'wsRestFrozen', 'wsRestTotal', 'wsRestSec'];
  // Dónde se puede transmitir. Fase 2 empieza en Crew; HABIT se enciende aquí (fase 3) sin
  // tocar app.html, que ya carga este módulo.
  const CAST_IN = { crew: true, habit: false };
  const SCREEN_ID = 'main';
  const MAZ_OFFSET_MS = 7 * 3600e3; // Mazatlán es UTC−7 todo el año (CLAUDE.md)

  // ── Textos ────────────────────────────────────────────────────────────────
  const TEXT = {
    es: {
      section: 'Pantalla del gym',
      row: 'Salir en la pantalla',
      vis: { hidden: 'No aparecer', name: 'Solo mi nombre y mi hora', routine: 'Mi nombre y mi rutina' },
      visShort: { hidden: 'No sales', name: 'Nombre y hora', routine: 'Nombre y rutina' },
      sheetTitle: 'Pantalla del gym',
      inviteTitle: '¿Sales en la pantalla del gym?',
      body: 'Cuando tengas reserva, la tele del gym puede enseñar tu nombre (así: «Ana P.») y la rutina que te toca, con las series que llevas. Nadie sale si no lo activa, y lo cambias cuando quieras aquí en Perfil.',
      notNow: 'Ahora no',
      saved: 'Listo',
      savedHidden: 'No vas a salir en la pantalla',
      failed: 'No se pudo guardar. Intenta de nuevo.',
      close: 'Cerrar',
      // La tele
      member: 'Socio',
      inGym: 'En el gym',
      next: 'Más tarde',
      noOne: 'Nadie en pantalla',
      noOneSub: 'Quien quiera salir aquí lo activa en la app: Perfil → Pantalla del gym.',
      hiddenNow: (n) => n === 1 ? '1 persona más entrenando' : n + ' personas más entrenando',
      freeTraining: 'Entreno libre',
      noRoutine: 'Sin rutina para hoy',
      st: { planned: 'Por empezar', scheduled: 'Por empezar', in_progress: 'Entrenando', done: 'Terminó', paused: 'En pausa' },
      sets: (d, t) => d + ' de ' + t + ' series',
      exercises: (n) => n === 1 ? '1 ejercicio' : n + ' ejercicios',
      until: (t) => 'hasta las ' + t,
      at: (t) => 'a las ' + t,
      live: 'En vivo',
      reconnecting: 'Reconectando',
      off: 'Pantalla apagada',
      offSub: 'Enciéndela desde el control: /pantalla?control',
      badKey: 'Falta la llave de esta pantalla',
      badKeySub: 'Abre la dirección completa que da el control (/pantalla?control), con su ?k=…',
      missing: 'Falta preparar la base de datos',
      missingSub: 'Corre la migración 152 en Supabase.',
      loading: 'Cargando…',
      fullscreen: 'Pantalla completa',
      exitFullscreen: 'Salir de pantalla completa',
      more: (n) => '+' + n + ' más',
      replaced: 'cambiado',
      // Transmitir (fase 2)
      cast: 'Pantalla',
      casting: 'En pantalla',
      castTitle: 'Pasar tu entreno a la pantalla',
      castBody: 'Mientras dure este entreno, la tele del gym enseña tu nombre (así: «Ana P.»), tu rutina, la serie que estás haciendo y tu descanso. Se quita sola al terminar, o cuando la quites aquí.',
      castGo: 'Pasar a la pantalla',
      castCancel: 'Ahora no',
      castStarted: 'Tu entreno ya sale en la pantalla del gym',
      castStopped: 'Ya no sales en la pantalla',
      castErr: {
        NO_BOOKING: 'Solo se puede durante tu reserva en el gym.',
        SCREEN_OFF: 'La pantalla del gym no está recibiendo entrenos ahora.',
        SCREEN_FULL: 'Ya hay 4 personas en la pantalla.',
        NO_SESSION: 'Empieza tu entreno de hoy para pasarlo a la pantalla.',
        NO_AUTH: 'Vuelve a entrar a tu cuenta.',
        generic: 'No se pudo pasar a la pantalla. Intenta de nuevo.'
      },
      liveNow: 'En vivo',
      noSignal: 'Sin señal',
      rest: 'Descanso',
      restPaused: 'En pausa',
      goSet: '¡A la serie!',
      setOf: (i, n) => 'Serie ' + i + ' de ' + n
    },
    en: {
      section: 'Gym screen',
      row: 'Show me on the screen',
      vis: { hidden: 'Don’t show me', name: 'Only my name and time', routine: 'My name and my workout' },
      visShort: { hidden: 'Hidden', name: 'Name and time', routine: 'Name and workout' },
      sheetTitle: 'Gym screen',
      inviteTitle: 'Want to be on the gym screen?',
      body: 'When you have a booking, the gym TV can show your name (like “Ana P.”) and today’s workout, with the sets you’ve done. Nobody shows up unless they turn it on, and you can change it any time here in Profile.',
      notNow: 'Not now',
      saved: 'Saved',
      savedHidden: 'You won’t show up on the screen',
      failed: 'Couldn’t save. Try again.',
      close: 'Close',
      member: 'Member',
      inGym: 'At the gym',
      next: 'Later today',
      noOne: 'Nobody on screen',
      noOneSub: 'To show up here, turn it on in the app: Profile → Gym screen.',
      hiddenNow: (n) => n === 1 ? '1 more person training' : n + ' more people training',
      freeTraining: 'Free workout',
      noRoutine: 'No workout today',
      st: { planned: 'Not started', scheduled: 'Not started', in_progress: 'Training', done: 'Finished', paused: 'Paused' },
      sets: (d, t) => d + ' of ' + t + ' sets',
      exercises: (n) => n === 1 ? '1 exercise' : n + ' exercises',
      until: (t) => 'until ' + t,
      at: (t) => 'at ' + t,
      live: 'Live',
      reconnecting: 'Reconnecting',
      off: 'Screen is off',
      offSub: 'Turn it on from the control page: /pantalla?control',
      badKey: 'This screen’s key is missing',
      badKeySub: 'Open the full address from the control page (/pantalla?control), with its ?k=…',
      missing: 'The database isn’t ready',
      missingSub: 'Run migration 152 in Supabase.',
      loading: 'Loading…',
      fullscreen: 'Full screen',
      exitFullscreen: 'Exit full screen',
      more: (n) => '+' + n + ' more',
      replaced: 'swapped',
      cast: 'Screen',
      casting: 'On screen',
      castTitle: 'Put your workout on the screen',
      castBody: 'For this workout, the gym TV shows your name (like “Ana P.”), your routine, the set you’re on and your rest. It comes off by itself when you finish, or when you take it off here.',
      castGo: 'Put it on the screen',
      castCancel: 'Not now',
      castStarted: 'Your workout is on the gym screen',
      castStopped: 'You’re off the screen',
      castErr: {
        NO_BOOKING: 'Only during your booking at the gym.',
        SCREEN_OFF: 'The gym screen isn’t taking workouts right now.',
        SCREEN_FULL: 'There are already 4 people on the screen.',
        NO_SESSION: 'Start today’s workout to put it on the screen.',
        NO_AUTH: 'Sign in again.',
        generic: 'Couldn’t put it on the screen. Try again.'
      },
      liveNow: 'Live',
      noSignal: 'No signal',
      rest: 'Rest',
      restPaused: 'Paused',
      goSet: 'Next set!',
      setOf: (i, n) => 'Set ' + i + ' of ' + n
    }
  };
  const doc = global.document;
  function lang(force) {
    const l = force || (doc && doc.documentElement && doc.documentElement.lang) || 'es';
    return /^en\b/i.test(l) ? 'en' : 'es';
  }
  function T(force) { return TEXT[lang(force)]; }

  // ── Puro ──────────────────────────────────────────────────────────────────

  // De las series que manda el servidor ({k, i, d, t, r, w, s}) a un mapa por ex_key, con los
  // mismos nombres de columna que coachSessionSets en la app.
  function setsByKey(rows) {
    const out = {};
    (Array.isArray(rows) ? rows : []).forEach((s) => {
      if (!s || !s.k) return;
      (out[s.k] = out[s.k] || []).push({
        ex_key: s.k, set_idx: s.i | 0, done: !!s.d, reps_target: s.t == null ? null : s.t,
        actual_reps: s.r == null ? null : s.r, weight: s.w == null ? null : Number(s.w),
        actual_seconds: s.s == null ? null : s.s
      });
    });
    Object.keys(out).forEach((k) => out[k].sort((a, b) => a.set_idx - b.set_idx));
    return out;
  }

  // La lista de ejercicios de una rutina: la de la sesión con lo cambiado hoy encima. Misma
  // regla que sessionExerciseList (crew.html): la copia de la sesión manda sobre la rutina, un
  // cambio encadena (C reemplaza a B que reemplazó a A), lo ya hecho con un ejercicio cambiado
  // se queda en la lista marcado, y uno quitado cierra el hueco.
  function effectiveExercises(routine, setsMap) {
    if (!routine) return [];
    const sets = setsMap || setsByKey(routine.sets);
    const base = Array.isArray(routine.exercises) ? routine.exercises : [];
    const overlay = Array.isArray(routine.overlay) ? routine.overlay : [];
    const replacedBy = {};
    overlay.forEach((o) => { if (o && o.replaces) replacedBy[o.replaces] = o; });
    const out = [];
    const follow = (ex, exKey) => {
      let currentKey = exKey, current = { ...ex, _exKey: exKey }, guard = 0;
      while (guard++ < 20) {
        const sub = replacedBy[currentKey];
        if (!sub) break;
        if ((sets[currentKey] || []).some((s) => s.done)) out.push({ ...current, _replaced: true });
        if (sub.removed || !sub.ex_key) { current = null; break; }
        currentKey = sub.ex_key;
        current = { ...sub, _exKey: currentKey, _swappedFrom: exKey };
      }
      if (current) out.push(current);
    };
    base.forEach((ex, i) => follow(ex, ex.id || (routine.board_id + '_idx_' + i)));
    overlay.filter((o) => o && !o.replaces && !o.removed && o.ex_key).forEach((o) => follow(o, o.ex_key));
    return out;
  }

  // «10-9-8-7» con repsType pirámide: una serie por escalón (exerciseSetCount en la app).
  function plannedSetCount(ex) {
    if (!ex) return 1;
    if (ex.repsType === 'pyramid') {
      const steps = String(ex.reps || '').split(/[-–,\s]+/).filter((s) => /^\d+$/.test(s));
      if (steps.length) return steps.length;
    }
    return Math.max(1, parseInt(ex.sets, 10) || 1);
  }

  // Qué tanto lleva: series hechas de cuántas, y en qué ejercicio va (el primero con algo
  // pendiente, el mismo que la hoja enfoca al abrirse). Con series sembradas cuentan las
  // series de verdad; sin ellas, lo planeado.
  function progress(routine) {
    const sets = setsByKey(routine && routine.sets);
    const list = effectiveExercises(routine, sets);
    let done = 0, total = 0, current = -1;
    const items = list.map((ex, idx) => {
      const rows = sets[ex._exKey] || [];
      const planned = rows.length || (ex._replaced ? 0 : plannedSetCount(ex));
      const d = rows.filter((s) => s.done).length;
      const n = ex._replaced ? d : Math.max(planned, d);
      done += d; total += n;
      if (current < 0 && !ex._replaced && d < n) current = idx;
      return { name: String(ex.name || '').trim(), key: ex._exKey, done: d, total: n, reps: ex.reps || '',
        repsType: ex.repsType || '', metricType: ex.metricType || '', replaced: !!ex._replaced,
        lastWeight: lastDoneWeight(rows) };
    });
    return { items, done, total, current };
  }
  function lastDoneWeight(rows) {
    for (let i = rows.length - 1; i >= 0; i--) if (rows[i].done && rows[i].weight > 0) return rows[i].weight;
    return null;
  }

  // Lo que dice una fila de la tele bajo el nombre del ejercicio: «3 × 12», «4 × 30s», «10-9-8».
  function targetLabel(item) {
    const reps = String(item.reps || '').trim();
    if (item.repsType === 'pyramid') return reps;
    if (!reps) return item.total ? item.total + ' ×' : '';
    return item.total + ' × ' + reps;
  }

  function mazDs(date) { return new Date((date ? +date : Date.now()) - MAZ_OFFSET_MS).toISOString().slice(0, 10); }
  function addDays(ds, n) { const d = new Date(ds + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); }

  const api = { APP_GLOBALS, CAST_IN, SCREEN_ID, TEXT, T, lang, setsByKey, effectiveExercises, plannedSetCount, progress, targetLabel, mazDs, addDays };

  // ── En las apps: el ajuste de Perfil y la invitación ─────────────────────
  // Solo donde hay app: la tele no tiene Perfil ni sesión de socio.
  const appSb = () => (typeof sb !== 'undefined' && sb && sb.from ? sb : null); // eslint-disable-line no-undef
  const appUser = () => (typeof sbUser !== 'undefined' ? sbUser : null); // eslint-disable-line no-undef
  const say = (msg, kind) => { try { if (typeof toast === 'function') toast(msg, kind); } catch (_) {} }; // eslint-disable-line no-undef

  const state = { uid: null, loadedAt: 0, loading: null, ready: false, off: true, pref: null, isMember: false, upcoming: false, invited: false,
    castOpen: true, casting: false, castSchedule: null };
  const RELOAD_MS = 5 * 60e3;

  function reset(uid) {
    Object.assign(state, { uid, loadedAt: 0, loading: null, ready: false, off: true, pref: null, isMember: false, upcoming: false, invited: false,
      castOpen: true, casting: false, castSchedule: null });
  }

  async function load(force) {
    const client = appSb(), user = appUser();
    if (!client || !user) return false;
    if (state.uid !== user.id) reset(user.id);
    if (!force && state.ready && Date.now() - state.loadedAt < RELOAD_MS) return true;
    if (state.loading) return state.loading;
    state.loading = (async () => {
      try {
        let scr = await client.from('gym_screens').select('mode,casting').eq('id', SCREEN_ID).maybeSingle();
        // Sin la 153 no existe «casting»: se lee lo de la 152 y no se ofrece transmitir.
        if (scr.error) scr = await client.from('gym_screens').select('mode').eq('id', SCREEN_ID).maybeSingle();
        // Sin la 152 (o sin la fila), como apagada: no se enseña nada.
        if (scr.error || !scr.data) { state.off = true; state.ready = true; return true; }
        state.off = scr.data.mode !== 'on';
        state.castOpen = scr.data.casting === true;
        if (!state.off && castHere()) await loadOwnCast(client);
        if (state.off) { state.ready = true; return true; }
        const today = mazDs();
        const [pref, bk] = await Promise.all([
          client.from('gym_screen_prefs').select('visibility,asked_at').eq('user_id', user.id).maybeSingle(),
          client.from('bookings').select('ds').eq('user_id', user.id).neq('status', 'cancelled')
            .gte('ds', addDays(today, -120)).order('ds', { ascending: false }).limit(1)
        ]);
        state.pref = pref.error ? null : (pref.data || null);
        const last = !bk.error && bk.data && bk.data[0] ? bk.data[0].ds : null;
        // Solo a quien entrena en el gym: una cuenta de Crew sin reservas nunca sale en la tele.
        state.isMember = !!last || !!state.pref;
        state.upcoming = !!last && last >= today;
        state.ready = true;
        state.loadedAt = Date.now();
        return true;
      } catch (e) {
        console.warn('habit-screen:', e);
        return false;
      } finally {
        state.loading = null;
      }
    })();
    return state.loading;
  }

  function visibility() { return (state.pref && state.pref.visibility) || 'hidden'; }

  function paintSection() {
    if (!doc) return;
    const anchor = doc.getElementById('perfil-blocks-section');
    if (!anchor) return;
    let sec = doc.getElementById('perfil-screen-section');
    if (!sec) {
      sec = doc.createElement('div');
      sec.id = 'perfil-screen-section';
      sec.hidden = true;
      anchor.parentNode.insertBefore(sec, anchor);
    }
    const show = state.ready && !state.off && state.isMember;
    sec.hidden = !show;
    if (!show) return;
    const t = T();
    sec.innerHTML = '<div class="divider" style="margin:.75rem 0"></div>'
      + '<p class="slbl">' + esc(t.section) + '</p>'
      + '<button class="btn-ghost perfil-row-btn" type="button" data-scr="open"><span>' + esc(t.row) + '</span>'
      + '<span class="perfil-row-sum">' + esc(t.visShort[visibility()]) + '</span></button>';
  }

  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  // ── La hoja (Perfil y la invitación son la misma, cambia el título y el último botón) ──
  let sheetEl = null;
  function ensureCss() {
    if (doc.getElementById('hscr-css')) return;
    const st = doc.createElement('style');
    st.id = 'hscr-css';
    st.textContent = CSS;
    doc.head.appendChild(st);
  }
  function ensureSheet() {
    ensureCss();
    if (sheetEl) return sheetEl;
    sheetEl = doc.createElement('div');
    sheetEl.className = 'hscr-overlay';
    sheetEl.setAttribute('role', 'dialog');
    sheetEl.setAttribute('aria-modal', 'true');
    doc.body.appendChild(sheetEl);
    sheetEl.addEventListener('click', (e) => { if (e.target === sheetEl) closeSheet(); });
    return sheetEl;
  }
  function openSheet(invite) {
    const t = T();
    const el = ensureSheet();
    const cur = visibility();
    const opts = ['routine', 'name', 'hidden'].map((v) => {
      const label = invite && v === 'hidden' ? t.notNow : t.vis[v];
      const on = !invite && v === cur;
      return '<button type="button" class="hscr-opt' + (on ? ' on' : '') + '" data-scr="set" data-v="' + v + '">'
        + '<span>' + esc(label) + '</span>' + (on ? '<i aria-hidden="true">✓</i>' : '') + '</button>';
    }).join('');
    el.innerHTML = '<div class="hscr-sheet">'
      + '<div class="hscr-head"><h2>' + esc(invite ? t.inviteTitle : t.sheetTitle) + '</h2>'
      + '<button type="button" class="hscr-close" data-scr="close" aria-label="' + esc(t.close) + '">×</button></div>'
      + '<div class="hscr-body"><p>' + esc(t.body) + '</p>' + opts + '</div></div>';
    el.dataset.invite = invite ? '1' : '';
    el.classList.add('open');
  }
  function closeSheet() {
    if (!sheetEl || !sheetEl.classList.contains('open')) return;
    // Cerrar la invitación sin elegir no cuenta como respuesta: se puede volver a hacer
    // otro día. Solo «Ahora no» (o cualquier opción) la da por contestada.
    sheetEl.classList.remove('open');
  }

  async function choose(v) {
    const client = appSb(), user = appUser();
    if (!client || !user || !['hidden', 'name', 'routine'].includes(v)) return;
    const row = { user_id: user.id, visibility: v, asked_at: new Date().toISOString() };
    const { error } = await client.from('gym_screen_prefs').upsert(row, { onConflict: 'user_id' });
    const t = T();
    if (error) { console.warn('habit-screen:', error); say(t.failed, 'err'); return; }
    state.pref = { visibility: v, asked_at: row.asked_at };
    state.isMember = true;
    closeSheet();
    paintSection();
    say(v === 'hidden' ? t.savedHidden : t.saved);
  }

  // La invitación: una sola vez, a quien tiene una reserva de hoy en adelante, con la
  // pantalla encendida, y nunca encima de otra cosa (un entreno abierto, otra hoja).
  function busy() {
    if (!doc) return true;
    if (doc.body.classList.contains('workout-sheet-open')) return true;
    if (doc.querySelector('.confirm-overlay.show, .act-overlay.open, .hs-overlay.open, .hscr-overlay.open')) return true;
    const main = doc.getElementById('s-main');
    if (!main || !main.classList.contains('active')) return true;
    const inicio = doc.getElementById('v-inicio');
    return !(inicio && inicio.classList.contains('active'));
  }
  function maybeInvite() {
    if (state.invited || !state.ready || state.off || !state.upcoming) return;
    if (state.pref && state.pref.asked_at) return;
    if (busy()) return;
    state.invited = true;
    openSheet(true);
  }

  // ── Transmitir el entreno (fase 2, migración 153) ──────────────────────
  // El teléfono manda lo que la base no tiene: la serie que toca y el descanso. Lo lee de las
  // variables de la hoja de entreno cada segundo y escribe solo cuando cambia (el descanso se
  // manda una vez al empezar, como segundos que faltan; la tele cuenta sola). El servidor
  // decide si se puede y la termina solo cuando el entreno se cierra.
  /* global IS_CREW, activeCoachingSession, wsFocusSet, wsPausedAt, wsRestEndAt, wsRestFrozen, wsRestTotal, wsRestSec */
  const CAST_OK_KEY = 'habit_cast_ok';
  const CAST_MIN_GAP_MS = 2000;
  const CAST_HEARTBEAT_MS = 60e3;
  const cast = { lastSig: '', lastSent: 0, pending: false, busy: false };

  function castHere() {
    const crew = typeof IS_CREW !== 'undefined' && !!IS_CREW;
    return crew ? CAST_IN.crew : CAST_IN.habit;
  }
  function activeSession() {
    return typeof activeCoachingSession !== 'undefined' && activeCoachingSession && activeCoachingSession.id
      ? activeCoachingSession : null;
  }
  async function loadOwnCast(client) {
    const { data, error } = await client.from('gym_screen_casts').select('schedule_id').maybeSingle();
    if (error) { state.casting = false; return; }
    state.casting = !!data;
    state.castSchedule = data ? data.schedule_id : null;
  }
  // Lo que se manda. focus puede ser null (la hoja aún no enfoca nada): la tele cae a la
  // primera serie pendiente, igual que la hoja al abrirse.
  function liveNow() {
    const f = typeof wsFocusSet !== 'undefined' && wsFocusSet ? wsFocusSet : null;
    const paused = typeof wsPausedAt !== 'undefined' && !!wsPausedAt;
    const rest = typeof wsRestSec === 'function' ? (wsRestSec() | 0) : 0;
    const total = typeof wsRestTotal !== 'undefined' ? (wsRestTotal | 0) : 0;
    // La firma cambia cuando empieza o se ajusta un descanso, no cada segundo que corre.
    const restMark = paused ? (typeof wsRestFrozen !== 'undefined' ? wsRestFrozen : 0)
      : (typeof wsRestEndAt !== 'undefined' ? Math.round(wsRestEndAt / 1000) : 0);
    return { k: f ? f.exKey : null, i: f && f.setIdx != null ? f.setIdx : null, rest, total, paused,
      sig: JSON.stringify([f && f.exKey, f && f.setIdx, total, paused, rest > 0 ? restMark : 0]) };
  }
  async function pushLive(force) {
    const client = appSb();
    if (!client || !state.casting || cast.busy) return;
    const s = activeSession();
    // Sin sesión cargada todavía (la app la restaura unos segundos después de abrir) no se
    // hace nada: cuando el entreno de verdad se cierra, el servidor quita la transmisión.
    if (!s) return;
    // Otro entreno: la transmisión era del anterior.
    if (s.id !== state.castSchedule) { stopCast(true); return; }
    const live = liveNow();
    const now = Date.now();
    const changed = live.sig !== cast.lastSig;
    if (!force && !changed && now - cast.lastSent < CAST_HEARTBEAT_MS) return;
    if (!force && now - cast.lastSent < CAST_MIN_GAP_MS) { cast.pending = true; return; }
    if (typeof navigator !== 'undefined' && navigator.onLine === false) return;
    cast.busy = true; cast.pending = false;
    try {
      const { data, error } = await client.rpc('update_gym_cast', {
        p_focus_key: live.k, p_focus_idx: live.i, p_rest_remaining_s: live.rest, p_rest_total_s: live.total, p_paused: live.paused
      });
      if (!error) {
        cast.lastSig = live.sig; cast.lastSent = Date.now();
        // false: ya no hay transmisión (venció, el staff la apagó o se cerró el entreno).
        if (data === false) { state.casting = false; state.castSchedule = null; paintCastButton(); }
      }
    } catch (e) { console.warn('habit-screen cast:', e); }
    finally { cast.busy = false; }
  }
  async function startCast() {
    const client = appSb(), s = activeSession(), t = T();
    if (!client || !s) { say(t.castErr.NO_SESSION, 'warn'); return; }
    const { data, error } = await client.rpc('start_gym_cast', { p_schedule: s.id, p_screen: SCREEN_ID });
    if (error || !data || !data.ok) {
      const code = data && data.error;
      say((code && t.castErr[code]) || t.castErr.generic, 'warn');
      if (code === 'SCREEN_OFF') { state.castOpen = false; paintCastButton(); }
      return;
    }
    state.casting = true; state.castSchedule = s.id;
    cast.lastSig = ''; cast.lastSent = 0;
    paintCastButton();
    say(t.castStarted);
    pushLive(true);
  }
  async function stopCast(silent) {
    const client = appSb();
    const was = state.casting;
    state.casting = false; state.castSchedule = null;
    paintCastButton();
    if (client && was) { try { await client.rpc('stop_gym_cast'); } catch (_) {} }
    if (!silent && was) say(T().castStopped);
  }
  function openCastSheet() {
    const t = T(), el = ensureSheet();
    el.innerHTML = '<div class="hscr-sheet">'
      + '<div class="hscr-head"><h2>' + esc(t.castTitle) + '</h2>'
      + '<button type="button" class="hscr-close" data-scr="close" aria-label="' + esc(t.close) + '">×</button></div>'
      + '<div class="hscr-body"><p>' + esc(t.castBody) + '</p>'
      + '<button type="button" class="hscr-opt on" data-scr="cast-go"><span>' + esc(t.castGo) + '</span></button>'
      + '<button type="button" class="hscr-opt" data-scr="close"><span>' + esc(t.castCancel) + '</span></button></div></div>';
    el.classList.add('open');
  }
  function castTapped() {
    if (state.casting) { stopCast(false); return; }
    let ok = false;
    try { ok = global.localStorage && global.localStorage.getItem(CAST_OK_KEY) === '1'; } catch (_) {}
    // La primera vez en este teléfono se explica qué se verá; después es un toque.
    if (ok) startCast(); else openCastSheet();
  }
  const CAST_ICON = '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M8.5 20h7M12 16.5V20"/></svg>';
  function paintCastButton() {
    const bar = doc && doc.querySelector('#workout-sheet .ws-bar');
    if (!bar) return;
    let btn = bar.querySelector('.hscr-cast');
    const show = castHere() && state.ready && !state.off && (state.castOpen || state.casting) && !!activeSession();
    if (!show) { if (btn) btn.hidden = true; return; }
    if (!btn) {
      ensureCss();
      btn = doc.createElement('button');
      btn.type = 'button';
      btn.className = 'hscr-cast';
      btn.setAttribute('data-scr', 'cast');
      const min = bar.querySelector('.ws-min');
      bar.insertBefore(btn, min || null);
    }
    btn.hidden = false;
    const t = T(), mark = (state.casting ? 'on:' : 'off:') + lang();
    if (btn.dataset.mark === mark) return;
    btn.dataset.mark = mark;
    btn.classList.toggle('on', state.casting);
    btn.setAttribute('aria-pressed', state.casting ? 'true' : 'false');
    btn.innerHTML = CAST_ICON + '<span>' + esc(state.casting ? t.casting : t.cast) + '</span>';
  }

  let tickT = null, wasOnPerfil = false;
  function tick(force) {
    clearTimeout(tickT);
    tickT = setTimeout(async () => {
      if (!appUser()) return;
      const perfil = doc.getElementById('v-perfil');
      const onPerfil = !!(perfil && perfil.classList.contains('active'));
      // Al entrar a Perfil se vuelve a leer (otro teléfono pudo cambiarlo); quedarse ahí no.
      const enteringPerfil = onPerfil && !wasOnPerfil;
      wasOnPerfil = onPerfil;
      if (await load(force || enteringPerfil)) {
        paintSection();
        paintCastButton();
        // Un respiro después de entrar: que la app termine de pintar Inicio antes de la hoja.
        setTimeout(maybeInvite, 1800);
      }
    }, force ? 0 : 400);
  }

  function onClick(e) {
    const b = e.target.closest && e.target.closest('[data-scr]');
    if (!b) return;
    const what = b.getAttribute('data-scr');
    if (what === 'open') { e.preventDefault(); openSheet(false); }
    else if (what === 'close') { e.preventDefault(); closeSheet(); }
    else if (what === 'set') { e.preventDefault(); choose(b.getAttribute('data-v')); }
    else if (what === 'cast') { e.preventDefault(); castTapped(); }
    else if (what === 'cast-go') {
      e.preventDefault();
      try { global.localStorage && global.localStorage.setItem(CAST_OK_KEY, '1'); } catch (_) {}
      closeSheet();
      startCast();
    }
  }

  function boot() {
    // Solo en las apps: la tele no tiene #s-main.
    const main = doc.getElementById('s-main');
    if (!main) return;
    doc.addEventListener('click', onClick);
    doc.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeSheet(); });
    // Cambiar de vista o de pantalla (entrar, abrir Perfil) es lo único que mueve esto.
    const mo = new MutationObserver(() => tick(false));
    mo.observe(main, { subtree: true, attributes: true, attributeFilter: ['class'] });
    const auth = doc.getElementById('s-auth');
    if (auth) mo.observe(auth, { attributes: true, attributeFilter: ['class'] });
    doc.addEventListener('visibilitychange', () => { if (!doc.hidden) { tick(false); if (state.casting) pushLive(true); } });
    // La hoja de entreno vive fuera de #s-main: abrirla es cuando aparece el botón.
    const sheet = doc.getElementById('workout-sheet');
    if (sheet) new MutationObserver(() => { paintCastButton(); tick(false); }).observe(sheet, { attributes: true, attributeFilter: ['class'] });
    // Cada segundo: mandar lo que cambió mientras transmite, y que el botón siga a la sesión
    // (aparece al empezar un entreno, se va al cerrarlo).
    setInterval(() => {
      if (!castHere()) return;
      paintCastButton();
      if (state.casting) pushLive(cast.pending);
    }, 1000);
    tick(false);
  }

  const CSS = `
.hscr-overlay{position:fixed;inset:0;z-index:10000;background:rgba(6,7,9,.66);display:none;align-items:flex-end;justify-content:center}
.hscr-overlay.open{display:flex;animation:hscrFade .18s ease both}
.hscr-sheet{width:100%;max-width:520px;max-height:92vh;background:var(--black,#141518);color:var(--white,#fff);border-radius:22px 22px 0 0;display:flex;flex-direction:column;overflow:hidden;animation:hscrUp .3s cubic-bezier(.2,.8,.2,1) both;padding-bottom:env(safe-area-inset-bottom,0px);font-family:'Inter',sans-serif}
.hscr-head{display:flex;align-items:center;gap:12px;padding:16px 16px 4px}
.hscr-head h2{flex:1;min-width:0;margin:0;font-size:17px;font-weight:700;letter-spacing:0;text-transform:none;color:var(--white,#fff)}
.hscr-close{background:none;border:0;color:#9aa0aa;font-size:26px;line-height:1;cursor:pointer;padding:4px 6px}
.hscr-body{overflow-y:auto;overscroll-behavior:contain;padding:8px 16px 22px;line-height:1.45}
.hscr-body p{margin:0 0 16px;color:#b9bec8;font-size:14px}
.hscr-opt{width:100%;display:flex;align-items:center;justify-content:space-between;gap:12px;margin:0 0 8px;padding:15px 16px;border-radius:14px;border:0;background:var(--card,#1d1f24);color:var(--white,#fff);font:600 15px 'Inter',sans-serif;text-align:left;cursor:pointer}
.hscr-opt.on{background:var(--blue,#2563eb)}
.hscr-opt i{font-style:normal;font-weight:800}
@keyframes hscrFade{from{opacity:0}to{opacity:1}}
@keyframes hscrUp{from{transform:translateY(40px);opacity:.6}to{transform:none;opacity:1}}
.hscr-cast{flex:none;display:inline-flex;align-items:center;gap:6px;margin-right:8px;height:34px;padding:0 11px;border-radius:11px;border:1px solid var(--border,rgba(255,255,255,.12));background:var(--surface,rgba(255,255,255,.045));color:var(--gl,#c9ced7);font:700 12px 'Inter',sans-serif;cursor:pointer}
.hscr-cast svg{width:17px;height:17px;fill:none;stroke:currentColor;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}
.hscr-cast.on{background:rgba(32,212,146,.14);border-color:rgba(32,212,146,.4);color:#20d492}
.hscr-cast.on span:before{content:'';display:inline-block;width:7px;height:7px;border-radius:50%;background:currentColor;margin-right:6px;vertical-align:1px;animation:hscrPulse 1.6s ease-in-out infinite}
.hscr-cast[hidden]{display:none}
@keyframes hscrPulse{50%{opacity:.3}}
@media (prefers-reduced-motion:reduce){.hscr-overlay.open,.hscr-sheet,.hscr-cast.on span:before{animation:none}}`;

  if (doc && doc.addEventListener) {
    if (doc.readyState === 'loading') doc.addEventListener('DOMContentLoaded', boot);
    else boot();
  }

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.HabitScreen = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
