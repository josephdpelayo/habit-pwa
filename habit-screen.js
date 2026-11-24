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
  const APP_GLOBALS = ['sb', 'sbUser', 'toast'];
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
      replaced: 'cambiado'
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
      replaced: 'swapped'
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

  const api = { APP_GLOBALS, SCREEN_ID, TEXT, T, lang, setsByKey, effectiveExercises, plannedSetCount, progress, targetLabel, mazDs, addDays };

  // ── En las apps: el ajuste de Perfil y la invitación ─────────────────────
  // Solo donde hay app: la tele no tiene Perfil ni sesión de socio.
  const appSb = () => (typeof sb !== 'undefined' && sb && sb.from ? sb : null); // eslint-disable-line no-undef
  const appUser = () => (typeof sbUser !== 'undefined' ? sbUser : null); // eslint-disable-line no-undef
  const say = (msg, kind) => { try { if (typeof toast === 'function') toast(msg, kind); } catch (_) {} }; // eslint-disable-line no-undef

  const state = { uid: null, loadedAt: 0, loading: null, ready: false, off: true, pref: null, isMember: false, upcoming: false, invited: false };
  const RELOAD_MS = 5 * 60e3;

  function reset(uid) {
    Object.assign(state, { uid, loadedAt: 0, loading: null, ready: false, off: true, pref: null, isMember: false, upcoming: false, invited: false });
  }

  async function load(force) {
    const client = appSb(), user = appUser();
    if (!client || !user) return false;
    if (state.uid !== user.id) reset(user.id);
    if (!force && state.ready && Date.now() - state.loadedAt < RELOAD_MS) return true;
    if (state.loading) return state.loading;
    state.loading = (async () => {
      try {
        const scr = await client.from('gym_screens').select('mode').eq('id', SCREEN_ID).maybeSingle();
        // Sin la 152 (o sin la fila), como apagada: no se enseña nada.
        if (scr.error || !scr.data) { state.off = true; state.ready = true; return true; }
        state.off = scr.data.mode !== 'on';
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
  function ensureSheet() {
    if (sheetEl) return sheetEl;
    if (!doc.getElementById('hscr-css')) {
      const st = doc.createElement('style');
      st.id = 'hscr-css';
      st.textContent = CSS;
      doc.head.appendChild(st);
    }
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
    doc.addEventListener('visibilitychange', () => { if (!doc.hidden) tick(false); });
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
@media (prefers-reduced-motion:reduce){.hscr-overlay.open,.hscr-sheet{animation:none}}`;

  if (doc && doc.addEventListener) {
    if (doc.readyState === 'loading') doc.addEventListener('DOMContentLoaded', boot);
    else boot();
  }

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.HabitScreen = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
