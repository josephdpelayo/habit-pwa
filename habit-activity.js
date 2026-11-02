// HABIT Activity — la sección Actividad: todo lo que entrenaste, cada cosa con su sticker
// (docs/HABIT_PARA_TODOS.md, bitácora del 1 nov 2026; los stickers son habit-share.js).
//
// La cargan las dos apps, HABIT (app.html, congelada: Joseph la pidió también ahí) y HABIT Crew
// (crew.html), con un <script>, un contenedor (#actividad-content) y su pestaña:
//   sv('actividad') → HabitActivity.render(document.getElementById('actividad-content'))
// Junta en una lista lo que hay de cada quien, venga de donde venga:
//   app       — los entrenos de la app (coaching_schedule, status 'done')
//   manual    — lo registrado aquí a mano (training_activities, migración 139)
//   skandi    — Skandi Fit: sus entrenos de fuerza (skandi_sessions terminadas) y el cardio
//               registrado ahí (skandi_external_activities sin fuente externa)
//   intervals / strava — correr, bici, nadar… del reloj, importados por Skandi
//               (skandi_external_activities con external_source)
// Con Intervals.icu conectado (se conecta en Skandi), al abrir la sección se trae lo nuevo del
// reloj por /api/skandi (intervals-status → intervals-sync) sin que nadie toque nada: el reloj
// solo llegaba cuando alguien abría Skandi y pedía sincronizar.
//
// A diferencia de habit-share.js no es independiente: lee con el cliente y la sesión de la app
// y usa sus funciones (fechas de Mazatlán, la lista de ejercicios de una sesión, el peso de una
// serie). Las dos apps las tienen porque vienen del mismo archivo; `APP_GLOBALS` las nombra y
// scripts/check-activity.js falla si a alguna le falta una. Lo puro (de una fila a un renglón
// de la lista, cuántos días pedir al reloj) se exporta y se prueba en Node.
(function (global) {
  'use strict';

  // Lo que se usa de la app, por su nombre global (las dos lo declaran en su <script>).
  const APP_GLOBALS = [
    'sb', 'sbUser', 'mazToday', 'addDaysDS', 'mazWeekStart', 'dateObjFromDS', 'dsFromIsoMaz', 'fmtDS',
    'esc', 'withScrollKept', 'toast', 'confirmSheet', 'sv', 'progresoStreak', 'sessionExerciseList',
    'exerciseKeyForSession', 'setVolumeKg', 'fmtScoreWeight', 'scoreWeightUnit', 'coachBoardsById'
  ];

  const TYPES = ['strength', 'run', 'bike', 'swim', 'walk', 'cardio', 'yoga', 'sport', 'other'];
  const DIST_TYPES = ['run', 'bike', 'swim', 'walk'];
  // Cada tipo con su color: la lista se lee de un vistazo. Lo de la app lleva el color de su
  // rutina, como en Entrenar.
  const COLORS = { strength: '#2563eb', run: '#f97316', bike: '#22c55e', swim: '#06b6d4', walk: '#84cc16', cardio: '#ef4444', yoga: '#a855f7', sport: '#f59e0b', other: '#94a3b8' };
  const ICONS = {
    strength: '<svg viewBox="0 0 24 24"><path d="M6.5 6.5v11M17.5 6.5v11M3.5 9.5v5M20.5 9.5v5M6.5 12h11"/></svg>',
    run: '<svg viewBox="0 0 24 24"><circle cx="15" cy="4.5" r="1.8"/><path d="M7.5 20.5l3.2-5 3 2.2 1.8 3.8M10.7 15.5l1.6-6.2 3.4 1.9 2.8 1.3M12.3 9.3L8.6 10l-2.1 3"/></svg>',
    bike: '<svg viewBox="0 0 24 24"><circle cx="6" cy="16" r="3.5"/><circle cx="18" cy="16" r="3.5"/><path d="M6 16l3.8-7h5.4L18 16M9.8 9l2.6 7H6M13.5 6h2.5"/></svg>',
    swim: '<svg viewBox="0 0 24 24"><circle cx="16.5" cy="6" r="1.8"/><path d="M3 15.5c2 0 2-1.5 4.5-1.5s2.5 1.5 4.5 1.5 2.5-1.5 4.5-1.5 2.5 1.5 4.5 1.5M3 19.5c2 0 2-1.5 4.5-1.5s2.5 1.5 4.5 1.5 2.5-1.5 4.5-1.5 2.5 1.5 4.5 1.5M6.5 11.5l4.5-3.2 3.2 2.7"/></svg>',
    walk: '<svg viewBox="0 0 24 24"><circle cx="12.5" cy="4.5" r="1.8"/><path d="M12 8.5l-.8 6-2.7 6M11.2 14.5l2.8 2.2.8 3.8M12 8.5l-3.2 2.8-.8 3M12 8.5l2.6 3.4 2.4.6"/></svg>',
    cardio: '<svg viewBox="0 0 24 24"><path d="M3 12.5h4l2.2-4.5 3.8 9 2.4-4.5H21"/></svg>',
    yoga: '<svg viewBox="0 0 24 24"><circle cx="12" cy="4.8" r="1.8"/><path d="M12 8v5.5M5 19c2.2-3.2 4.6-4.4 7-5.5 2.4 1.1 4.8 2.3 7 5.5M5.5 12.5l6.5 1 6.5-1"/></svg>',
    sport: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5"/><path d="M12 3.5v17M3.5 12h17M6.3 5.8c3 3.4 3 9 0 12.4M17.7 5.8c-3 3.4-3 9 0 12.4"/></svg>',
    other: '<svg viewBox="0 0 24 24"><path d="M12 3.5v4M12 16.5v4M3.5 12h4M16.5 12h4M6 6l2.8 2.8M15.2 15.2L18 18M6 18l2.8-2.8M15.2 8.8L18 6"/></svg>'
  };
  const PLUS = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
  const SYNC_ICON = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 11a8 8 0 0 0-14.3-4.9L4 8"/><path d="M4 3.5V8h4.5"/><path d="M4 13a8 8 0 0 0 14.3 4.9L20 16"/><path d="M20 20.5V16h-4.5"/></svg>';
  const MONTHS = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
  // Esfuerzo en palabras: nadie piensa «fue un 7»; sí «fue duro». Se guarda el número (1–10).
  const EFFORTS = [[3, 'Suave'], [5, 'Normal'], [8, 'Duro'], [10, 'Al máximo']];
  // Mazatlán no cambia de horario: su medianoche es siempre a las 07:00 UTC (CLAUDE.md).
  const MAZ_OFFSET = '-07:00';

  // ── Puro: de cada fuente, un renglón de la lista ─────────────────────────

  const share = () => global.HabitShare || null;
  function typeLabel(t) { const S = share(); return (S && S.ACTIVITY_TYPES[t] || {}).label || 'Entreno'; }
  // Una actividad sin nombre se llama por su tipo: «Carrera», «Rodada», «Nado».
  function typeNoun(t) { const S = share(); return (S && S.ACTIVITY_TYPES[t] || {}).noun || 'Entreno'; }
  function hasDistance(t) { return DIST_TYPES.includes(t); }

  // Skandi guarda seis tipos (más hiit y hyrox, 104). Del reloj llega además el tipo crudo
  // (external_type: «Yoga», «Hike», «Soccer»…), que dice qué era un «other».
  const SKANDI_TYPES = { running: 'run', cycling: 'bike', swimming: 'swim', walking: 'walk', rowing: 'cardio', hiit: 'cardio', hyrox: 'cardio' };
  function typeFromSkandi(activityType, externalType) {
    if (SKANDI_TYPES[activityType]) return SKANDI_TYPES[activityType];
    const raw = String(externalType || '').toLowerCase();
    if (/^(weighttraining|strengthtraining|functionalstrengthtraining|crossfit)$/.test(raw.replace(/[^a-z]/g, ''))) return 'strength';
    if (/yoga|pilates|stretch|mobility/.test(raw)) return 'yoga';
    if (/hike|walk/.test(raw)) return 'walk';
    if (/soccer|football|tennis|padel|basket|volley|golf|squash|badminton|pickleball|surf|climb|ski|snowboard|skate/.test(raw)) return 'sport';
    if (/run/.test(raw)) return 'run';
    if (/ride|cycl|bike/.test(raw)) return 'bike';
    if (/swim/.test(raw)) return 'swim';
    if (/row|elliptical|stair|hiit|cardio/.test(raw)) return 'cardio';
    return 'other';
  }
  const posInt = (v, lo, hi) => { const n = Math.round(Number(v) || 0); return n >= lo && n <= hi ? n : 0; };

  // `h` trae lo que depende de la app: dsOf (un instante → su día en Mazatlán) y routineName.
  function itemFromAppSession(r, h) {
    return {
      key: 's:' + r.id, src: 'app', type: 'strength', title: h.routineName(r.board_name) || 'Entreno libre', named: false,
      ds: r.ds || h.dsOf(r.completed_at), at: r.completed_at || '', startedAt: r.started_at || '', durationSec: r.duration_sec || 0, distanceM: 0,
      color: r.board_color || COLORS.strength, row: r
    };
  }
  function itemFromManual(a) {
    return {
      key: 'a:' + a.id, src: 'manual', type: TYPES.includes(a.kind) ? a.kind : 'other', title: a.title || typeNoun(a.kind), named: !!a.title,
      ds: a.ds, at: a.created_at || '', durationSec: a.duration_sec || 0, distanceM: a.distance_m || 0, elevationM: a.elevation_m || 0,
      avgHr: a.avg_hr || 0, kcal: a.kcal || 0, effort: a.effort || 0, notes: a.notes || '', color: COLORS[a.kind] || COLORS.other, row: a
    };
  }
  // Del reloj, `note` es el nombre de la actividad («Morning Run»); registrada a mano en
  // Skandi, es una nota. Por eso el nombre solo vale si vino de fuera.
  function itemFromSkandiActivity(x, h) {
    const type = typeFromSkandi(x.activity_type, x.external_type);
    const src = x.external_source === 'intervals' || x.external_source === 'strava' ? x.external_source : 'skandi';
    const note = String(x.note || '').trim();
    const named = src !== 'skandi' && !!note;
    return {
      key: 'x:' + x.id, src, type, title: named ? note : typeNoun(type), named,
      ds: h.dsOf(x.performed_at), at: x.performed_at || '', startedAt: x.performed_at || '',
      durationSec: Math.round((Number(x.duration_min) || 0) * 60), distanceM: Math.round((Number(x.distance_km) || 0) * 1000),
      elevationM: Math.round(Number(x.elevation_gain_m) || Number(x.elevation_m) || 0), avgHr: posInt(x.avg_heart_rate, 30, 250),
      kcal: posInt(x.calories, 1, 20000), effort: posInt(x.intensity, 1, 10), notes: named ? '' : note,
      color: COLORS[type] || COLORS.other, row: x
    };
  }
  function itemFromSkandiSession(k, h) {
    const span = k.completed_at && k.started_at ? Math.round((Date.parse(k.completed_at) - Date.parse(k.started_at)) / 1000) : 0;
    const dur = k.duration_sec || span;
    return {
      key: 'k:' + k.id, src: 'skandi', type: 'strength', title: String(k.title || '').trim() || 'Fuerza', named: false,
      ds: h.dsOf(k.started_at || k.completed_at), at: k.completed_at || '', startedAt: k.started_at || '', durationSec: dur > 0 && dur <= 86400 ? dur : 0, distanceM: 0,
      avgHr: posInt(k.garmin_avg_heart_rate, 30, 250), kcal: posInt(k.garmin_calories, 1, 20000), color: COLORS.strength, row: k
    };
  }
  // Lo más nuevo arriba, y el Nº de cada uno: también cuenta lo que quedó antes de la ventana.
  function numberItems(items, before) {
    items.sort((x, y) => y.ds.localeCompare(x.ds) || (Date.parse(y.at) || 0) - (Date.parse(x.at) || 0));
    items.forEach((it, i) => { it.number = before + items.length - i; });
    return items;
  }

  // Una sesión, varias fuentes. No cambia ni borra los registros originales: reúne la
  // presentación y sus métricas antes de contar, sumar minutos o preparar un sticker.
  function reconcileActivities(items) {
    const watch = (it) => it.src === 'intervals' || it.src === 'strava';
    const pairs = new Map(items.map((it) => [it.key, []]));
    const exactPairs = new Map(items.map((it) => [it.key, []]));
    for (let i = 0; i < items.length; i++) {
      const a = items[i];
      for (let j = i + 1; j < items.length; j++) {
        const b = items[j];
        if (a.type !== b.type || (!watch(a) && !watch(b))) continue;
        // Un id solo es comparable dentro de su procedencia, nunca Garmin vs. Strava.
        const linked = (a.src === 'intervals' && String(b.row.garmin_external_id || '') === String(a.row.external_id || '') && !!a.row.external_id)
          || (b.src === 'intervals' && String(a.row.garmin_external_id || '') === String(b.row.external_id || '') && !!b.row.external_id);
        const sameId = watch(a) && a.src === b.src && !!a.row.external_id && a.row.external_id === b.row.external_id;
        if (linked || sameId) {
          exactPairs.get(a.key).push(b); exactPairs.get(b.key).push(a); continue;
        }
        if (a.src === b.src || a.src === 'manual' || b.src === 'manual' || a.ds !== b.ds) continue;
        // created_at/completed_at no son la hora real de inicio. Sin ella no se adivina.
        const startA = Date.parse(a.startedAt || ''), startB = Date.parse(b.startedAt || '');
        if (!Number.isFinite(startA) || !Number.isFinite(startB) || !(a.durationSec > 0 && b.durationSec > 0)) continue;
        if (Math.abs(startA - startB) > (watch(a) && watch(b) ? 120000 : 300000)) continue;
        if (Math.abs(a.durationSec - b.durationSec) > Math.max(300, Math.max(a.durationSec, b.durationSec) * .15)) continue;
        if (a.distanceM > 0 && b.distanceM > 0 && Math.abs(a.distanceM - b.distanceM) > Math.max(200, Math.max(a.distanceM, b.distanceM) * .03)) continue;
        pairs.get(a.key).push(b); pairs.get(b.key).push(a);
      }
    }
    const used = new Set(), result = [];
    const priority = (it) => it.src === 'app' ? 0 : it.key.startsWith('k:') ? 1 : it.src === 'manual' ? 2 : it.src === 'intervals' ? 3 : 4;
    const neighbors = (it) => exactPairs.get(it.key).length ? exactPairs.get(it.key) : pairs.get(it.key);
    for (const a of items) {
      if (used.has(a.key)) continue;
      const group = [a, ...neighbors(a)];
      const keys = new Set(group.map((it) => it.key));
      // Todos deben coincidir entre sí y no tener otra pareja posible. Una cadena de
      // horarios próximos o dos sesiones locales candidatas no autoriza una fusión.
      const certain = group.length > 1 && group.every((it) => !used.has(it.key)
        && neighbors(it).length === group.length - 1 && neighbors(it).every((other) => keys.has(other.key)));
      if (!certain) { result.push({ ...a }); used.add(a.key); continue; }
      group.sort((x, z) => priority(x) - priority(z));
      const primary = group[0];
      const merged = { ...primary, mergedFrom: group.map((it) => it.key), watchSource: group.find(watch).src };
      for (const secondary of group.slice(1)) {
        for (const field of ['durationSec', 'distanceM', 'elevationM', 'avgHr', 'kcal', 'effort']) {
          if (!(merged[field] > 0) && secondary[field] > 0) merged[field] = secondary[field];
        }
      }
      result.push(merged); group.forEach((it) => used.add(it.key));
    }
    return result;
  }

  // Cuántos días pedirle a Intervals: desde la última vez, con dos de colchón (el reloj sube la
  // actividad horas después); sin una vez anterior, los cuatro meses que enseña la lista.
  function syncWindowDays(lastSyncIso, now, visibleDays) {
    // Una sincronización explícita repara también actividades antiguas que antes se
    // descartaban, aunque el último sync haya sido hace apenas unos minutos.
    if (visibleDays > 0) return Math.max(120, Math.min(730, Math.round(visibleDays)));
    const t = Date.parse(lastSyncIso || '');
    if (!isFinite(t)) return 120;
    return Math.max(3, Math.min(120, Math.ceil((now - t) / 864e5) + 2));
  }
  const SYNC_EVERY_MS = 20 * 60000;
  function syncDue(lastSyncIso, now) {
    const t = Date.parse(lastSyncIso || '');
    return !isFinite(t) || now - t > SYNC_EVERY_MS;
  }

  // Skandi guarda kilos (el lastre, en las dominadas con peso). La mejor serie de un ejercicio:
  // la más pesada; sin peso, la más larga o la de más reps.
  function kgText(n) { const r = Math.round(n * 10) / 10; return (r % 1 ? r.toFixed(1) : String(r)) + ' kg'; }
  function skandiBestSet(sets) {
    const w = sets.filter((s) => Number(s.weight_kg) > 0).sort((a, b) => Number(b.weight_kg) - Number(a.weight_kg) || (b.reps || 0) - (a.reps || 0))[0];
    if (w) return kgText(Number(w.weight_kg)) + (w.reps ? ' × ' + w.reps : '');
    const t = sets.filter((s) => Number(s.seconds) > 0).sort((a, b) => b.seconds - a.seconds)[0];
    if (t) return t.seconds + ' s';
    const r = sets.filter((s) => Number(s.reps) > 0).sort((a, b) => b.reps - a.reps)[0];
    return r ? r.reps + ' reps' : '';
  }
  // Un entreno de Skandi, con sus series hechas, en los datos que pinta habit-share.js.
  function skandiStickerData(sets, namesById, base) {
    const done = (sets || []).filter((s) => s.done)
      .sort((a, b) => (a.sort_order || 0) - (b.sort_order || 0) || (a.set_idx || 0) - (b.set_idx || 0));
    const byEx = new Map();
    let vol = 0;
    done.forEach((s) => {
      if (!byEx.has(s.exercise_id)) byEx.set(s.exercise_id, []);
      byEx.get(s.exercise_id).push(s);
      vol += (Number(s.weight_kg) || 0) * (Number(s.reps) || 0);
    });
    const exercises = [...byEx.entries()].map(([id, list]) => ({ name: (namesById || {})[id] || 'Ejercicio', best: skandiBestSet(list) }));
    return { ...base, type: 'strength', sets: done.length, volumeKg: Math.round(vol), exercises, exerciseCount: exercises.length };
  }

  // ── Navegador ────────────────────────────────────────────────────────────

  const doc = global.document;
  const state = { data: null, windowDays: 120, filter: 'all', loading: null, form: null, detailKey: null, root: null };
  const sync = { uid: null, checked: false, connected: false, last: null, busy: false, error: '' };
  let sheet = null;

  /* global sb, sbUser, mazToday, addDaysDS, mazWeekStart, dateObjFromDS, dsFromIsoMaz, fmtDS, esc,
     withScrollKept, toast, confirmSheet, sv, progresoStreak, sessionExerciseList,
     exerciseKeyForSession, setVolumeKg, fmtScoreWeight, scoreWeightUnit, coachBoardsById,
     routineName, exDisplayName */
  function userId() { return typeof sbUser !== 'undefined' && sbUser ? sbUser.id : null; }
  // routineName y exDisplayName solo existen en Crew (los nombres en MAYÚSCULAS, legibles).
  const helpers = () => ({
    dsOf: (iso) => (iso ? dsFromIsoMaz(iso) : ''),
    routineName: (n) => (typeof routineName === 'function' ? routineName(n) : n)
  });
  const exName = (n) => (typeof exDisplayName === 'function' ? exDisplayName(n) : n);
  const say = (msg, type) => { if (typeof toast === 'function') toast(msg, type); };
  function isMissingTable(error) {
    return !!error && (error.code === '42P01' || error.code === 'PGRST205' || /schema cache|does not exist/i.test(error.message || ''));
  }
  const durText = (sec) => {
    const min = Math.round((Number(sec) || 0) / 60);
    if (!min) return '';
    if (min < 60) return min + ' min';
    return Math.floor(min / 60) + ' h' + (min % 60 ? ' ' + (min % 60) + ' min' : '');
  };
  const distText = (type, m) => {
    const S = share();
    if (!(m > 0) || !S) return '';
    return type === 'swim' ? S.thousands(m) + ' m' : S.distanceText(type, m) + ' km';
  };
  const sinceIso = (ds) => ds + 'T00:00:00' + MAZ_OFFSET;

  // Lo de los últimos `windowDays` días; «Ver antes» agranda la ventana. Las series no vienen
  // en la lista (pesan): se piden al abrir un entreno o su sticker. Una fuente que falla (Skandi
  // sin sus tablas) se queda fuera sin tumbar la lista; los entrenos de la app no.
  function loadData(force) {
    const uid = userId();
    if (!uid) return Promise.resolve(null);
    const d = state.data;
    if (!force && d && d.uid === uid && d.days === state.windowDays && Date.now() - d.at < 60000) return Promise.resolve(d);
    if (state.loading) return state.loading;
    state.loading = (async () => {
      const since = addDaysDS(mazToday(), -state.windowDays), from = sinceIso(since);
      const head = { count: 'exact', head: true };
      const [s, sB, a, aB, x, xB, k, kB] = await Promise.all([
        sb.from('coaching_schedule').select('id,ds,board_id,board_name,board_color,duration_sec,started_at,completed_at')
          .eq('user_id', uid).eq('status', 'done').gte('ds', since).order('ds', { ascending: false }).limit(1000),
        sb.from('coaching_schedule').select('id', head).eq('user_id', uid).eq('status', 'done').lt('ds', since),
        sb.from('training_activities').select('*').eq('user_id', uid).gte('ds', since).order('ds', { ascending: false }).limit(1000),
        sb.from('training_activities').select('id', head).eq('user_id', uid).lt('ds', since),
        sb.from('skandi_external_activities')
          .select('id,activity_type,external_type,external_source,external_id,performed_at,duration_min,distance_km,elevation_gain_m,elevation_m,avg_heart_rate,calories,intensity,note')
          .eq('user_id', uid).gte('performed_at', from).order('performed_at', { ascending: false }).limit(1000),
        sb.from('skandi_external_activities').select('id', head).eq('user_id', uid).lt('performed_at', from),
        sb.from('skandi_sessions').select('id,title,started_at,completed_at,duration_sec,garmin_external_id,garmin_avg_heart_rate,garmin_calories')
          .eq('user_id', uid).not('completed_at', 'is', null).gte('started_at', from).order('started_at', { ascending: false }).limit(1000),
        sb.from('skandi_sessions').select('id', head).eq('user_id', uid).not('completed_at', 'is', null).lt('started_at', from)
      ]);
      if (s.error) throw s.error;
      const missing = isMissingTable(a.error);
      if (a.error && !missing) throw a.error;
      if (x.error) console.warn('Actividad: sin el cardio de Skandi:', x.error.message);
      if (k.error) console.warn('Actividad: sin las sesiones de Skandi:', k.error.message);
      const h = helpers();
      const rawItems = [
        ...(s.data || []).map((r) => itemFromAppSession(r, h)),
        ...(missing ? [] : (a.data || []).map(itemFromManual)),
        ...(x.error ? [] : (x.data || []).map((r) => itemFromSkandiActivity(r, h))),
        ...(k.error ? [] : (k.data || []).map((r) => itemFromSkandiSession(r, h)))
      ].filter((it) => it.ds);
      const items = reconcileActivities(rawItems);
      const before = (sB.count || 0) + (missing ? 0 : (aB.count || 0)) + (x.error ? 0 : (xB.count || 0)) + (k.error ? 0 : (kB.count || 0));
      numberItems(items, before);
      state.data = { uid, at: Date.now(), days: state.windowDays, since, items, before, duplicates: rawItems.length - items.length, tableMissing: missing };
      return state.data;
    })();
    state.loading.catch(() => {}).finally(() => { state.loading = null; });
    return state.loading;
  }

  function weekSummary(items) {
    const ws = mazWeekStart(mazToday());
    const week = items.filter((it) => it.ds >= ws);
    const days = [0, 0, 0, 0, 0, 0, 0];
    week.forEach((it) => { const i = Math.round((dateObjFromDS(it.ds) - dateObjFromDS(ws)) / 864e5); if (i >= 0 && i < 7) days[i] = 1; });
    return {
      weekStart: ws, count: week.length, days, streak: typeof progresoStreak === 'function' ? progresoStreak(items) : 0,
      durationSec: week.reduce((n, it) => n + (it.durationSec || 0), 0), distanceM: week.reduce((n, it) => n + (it.distanceM || 0), 0)
    };
  }

  async function render(el) {
    el = el || state.root || (doc && doc.getElementById('actividad-content'));
    if (!el) return;
    state.root = el;
    if (!userId()) { el.innerHTML = '<div class="empty">Inicia sesión para ver tu actividad.</div>'; return; }
    if (!state.data || state.data.uid !== userId() || state.data.days !== state.windowDays) el.innerHTML = '<div class="empty">Cargando tu actividad…</div>';
    let d;
    try { d = await loadData(false); }
    catch (e) { el.innerHTML = '<div class="empty">No se pudo cargar tu actividad: ' + esc(e.message || e) + '</div>'; return; }
    if (!d) return;
    paint();
    autoSync(false);
  }
  function paint() {
    const el = state.root, d = state.data;
    if (!el || !d || d.uid !== userId()) return;
    const html = pageHtml(d);
    if (typeof withScrollKept === 'function') withScrollKept(el, () => { el.innerHTML = html; });
    else el.innerHTML = html;
  }
  function invalidate() { state.data = null; }

  function pageHtml(d) {
    const S = share();
    let html = '<div class="act-top"><div class="act-kicker">Tu actividad</div>'
      + (d.tableMissing ? '' : '<button class="act-add" data-act="add">' + PLUS + 'Registrar</button>') + '</div>'
      + syncHtml();
    if (!d.items.length) {
      return html + '<section class="act-empty"><div class="act-empty-ic">' + ICONS.run + ICONS.bike + ICONS.swim + ICONS.strength + '</div>'
        + '<div class="act-empty-t">Aquí sale todo lo que entrenas</div>'
        + '<p>Lo que haces con la app y lo de fuera: correr, bici, nadar, fuerza en otro gym. Cada uno con su sticker para tu historia.</p>'
        + (d.tableMissing ? '' : '<button class="btn" data-act="add">Registrar una actividad</button>')
        + '<button class="btn-sm" data-act="train">Entrenar con la app</button></section>';
    }
    html += weekHtml(weekSummary(d.items));
    const types = TYPES.filter((t) => d.items.some((it) => it.type === t));
    if (state.filter !== 'all' && !types.includes(state.filter)) state.filter = 'all';
    if (types.length > 1) {
      html += '<div class="act-filters" role="tablist">' + ['all', ...types].map((t) => '<button class="act-filter' + (state.filter === t ? ' on' : '') + '" data-act="filter" data-v="' + t + '">' + (t === 'all' ? 'Todo' : esc(typeLabel(t))) + '</button>').join('') + '</div>';
    }
    const shown = state.filter === 'all' ? d.items : d.items.filter((it) => it.type === state.filter);
    let month = '';
    shown.forEach((it) => {
      const m = it.ds.slice(0, 7);
      if (m !== month) {
        month = m;
        const n = shown.filter((x) => x.ds.slice(0, 7) === m).length;
        html += '<div class="act-month"><span>' + MONTHS[Number(m.slice(5, 7)) - 1] + ' ' + m.slice(0, 4) + '</span><span>' + n + '</span></div>';
      }
      html += rowHtml(it, S);
    });
    if (!shown.length) html += '<div class="empty">Nada de esto en los últimos meses.</div>';
    html += '<button class="act-more" data-act="more">Ver antes del ' + esc(fmtDS(d.since)) + '</button>';
    if (d.tableMissing) html += '<p class="act-note">Pronto podrás registrar aquí lo que entrenas fuera de la app.</p>';
    return html;
  }
  function weekHtml(w) {
    const S = share();
    const meta = [durText(w.durationSec), w.distanceM ? (w.distanceM / 1000).toFixed(1) + ' km' : '', w.streak > 1 ? w.streak + ' semanas seguidas' : ''].filter(Boolean).join(' · ');
    return '<section class="act-week">'
      + '<div class="act-week-n">' + w.count + '<span>' + (w.count === 1 ? 'entreno' : 'entrenos') + '<br>esta semana</span></div>'
      + (meta ? '<div class="act-week-meta">' + esc(meta) + '</div>' : '')
      + '<div class="act-week-days">' + 'LMMJVSD'.split('').map((l, i) => '<span class="' + (w.days[i] ? 'on' : '') + '"><i></i>' + l + '</span>').join('') + '</div>'
      + (w.count && S ? '<button class="act-week-share" data-act="share-week">' + S.SHARE_ICON + 'Compartir mi semana</button>' : '')
      + '</section>';
  }
  function rowHtml(it, S) {
    const meta = [fmtDS(it.ds), durText(it.durationSec), distText(it.type, it.distanceM)].filter(Boolean).join(' · ');
    const tag = it.named ? typeLabel(it.type) : (it.key.startsWith('k:') ? 'Skandi' : '');
    return '<div class="act-row" role="button" tabindex="0" data-act="detail" data-k="' + esc(it.key) + '">'
      + '<span class="act-ic" style="--c:' + esc(it.color) + '">' + (ICONS[it.type] || ICONS.other) + '</span>'
      + '<span class="act-row-main"><span class="act-row-t">' + esc(it.title) + '</span><span class="act-row-m">' + esc(meta) + (tag ? ' · ' + esc(tag) : '') + '</span></span>'
      + (S ? '<button class="act-row-share" aria-label="Compartir sticker" data-act="share" data-k="' + esc(it.key) + '">' + S.SHARE_ICON + '</button>' : '') + '</div>';
  }
  function find(key) { return state.data && state.data.items.find((it) => it.key === key) || null; }

  // ── El reloj (Intervals.icu, conectado en Skandi) ───────────────────────

  async function skandiApi(action, body) {
    const { data: { session } } = await sb.auth.getSession();
    if (!session) throw new Error('Tu sesión expiró');
    const res = await fetch('/api/skandi', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + session.access_token },
      body: JSON.stringify({ action, ...(body || {}) })
    });
    const out = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(out.message || 'Intervals.icu no respondió');
    return out;
  }
  function agoText(iso) {
    const t = Date.parse(iso || '');
    if (!isFinite(t)) return 'sin sincronizar';
    const m = Math.round((Date.now() - t) / 60000);
    if (m < 1) return 'sincronizado ahora';
    if (m < 60) return 'sincronizado hace ' + m + ' min';
    const h = Math.round(m / 60);
    return h < 24 ? 'sincronizado hace ' + h + ' h' : 'sincronizado hace ' + Math.round(h / 24) + ' días';
  }
  function syncHtml() {
    if (!sync.connected || sync.uid !== userId()) return '';
    const txt = sync.busy ? 'Trayendo lo nuevo de tu reloj…'
      : sync.error ? 'No se pudo sincronizar: ' + sync.error : 'Tu reloj (Intervals.icu) · ' + agoText(sync.last);
    return '<div class="act-sync' + (sync.busy ? ' busy' : '') + (sync.error ? ' err' : '') + '">' + SYNC_ICON + '<span>' + esc(txt) + '</span>'
      + (sync.busy ? '' : '<button data-act="sync">' + (sync.error ? 'Reintentar' : 'Sincronizar') + '</button>') + '</div>';
  }
  // Al abrir: si hay reloj conectado y pasaron más de 20 min, se trae lo nuevo. Sin conexión o
  // sin red no se dice nada; la lista ya está.
  async function autoSync(force) {
    const uid = userId();
    if (!uid || sync.busy) return;
    try {
      if (!sync.checked || sync.uid !== uid) {
        const st = await skandiApi('intervals-status');
        Object.assign(sync, { uid, checked: true, connected: !!st.connected, last: st.last_sync_at || null, error: '' });
        if (!sync.connected) return;
        paint();
      }
      if (!sync.connected || (!force && !syncDue(sync.last, Date.now()))) return;
      sync.busy = true; sync.error = ''; paint();
      const r = await skandiApi('intervals-sync', { days: syncWindowDays(sync.last, Date.now(), force ? state.windowDays : 0) });
      sync.busy = false; sync.last = new Date().toISOString();
      await loadData(true);
      paint();
      const n = r.imported || 0;
      if (n) say(n === 1 ? '1 actividad nueva de tu reloj' : n + ' actividades nuevas de tu reloj', 'ok');
      else if (force) say('Ya tenías todo lo de tu reloj', 'ok');
    } catch (e) {
      sync.busy = false;
      if (sync.connected && sync.uid === uid) { sync.error = String(e.message || e).slice(0, 120); paint(); }
    }
  }

  // ── Stickers ───────────────────────────────────────────────────────────

  // La mejor serie de un ejercicio de la app, en palabras, con la unidad de la persona.
  function appBestSet(done) {
    const w = done.filter((s) => Number(s.weight) > 0).sort((a, b) => Number(b.weight) - Number(a.weight) || (parseInt(b.actual_reps, 10) || 0) - (parseInt(a.actual_reps, 10) || 0))[0];
    if (w) return fmtScoreWeight(Number(w.weight), scoreWeightUnit) + (parseInt(w.actual_reps, 10) ? ' × ' + parseInt(w.actual_reps, 10) : '');
    const t = done.filter((s) => Number(s.actual_seconds) > 0).sort((a, b) => b.actual_seconds - a.actual_seconds)[0];
    if (t) return t.actual_seconds + ' s';
    const r = done.filter((s) => parseInt(s.actual_reps, 10) > 0).sort((a, b) => parseInt(b.actual_reps, 10) - parseInt(a.actual_reps, 10))[0];
    return r ? parseInt(r.actual_reps, 10) + ' reps' : '';
  }
  // Un entreno de la app, con sus series, en los datos que pinta habit-share.js.
  function sessionStickerData(row, setsMap) {
    const list = sessionExerciseList(row, setsMap || {});
    const exercises = [];
    let sets = 0, vol = 0;
    list.forEach((ex, i) => {
      const done = ((setsMap || {})[exerciseKeyForSession(row.board_id, ex, i)] || []).filter((s) => s.done);
      if (!done.length) return;
      sets += done.length;
      done.forEach((s) => { vol += setVolumeKg(s); });
      exercises.push({ name: exName(ex.name || 'Ejercicio'), best: appBestSet(done) });
    });
    return {
      type: 'strength', title: helpers().routineName(row.board_name) || 'Entreno libre', ds: row.ds || dsFromIsoMaz(row.completed_at),
      durationSec: row.duration_sec || 0, sets, volumeKg: vol, exercises, exerciseCount: exercises.length
    };
  }
  async function appSessionData(it) {
    const [{ data: row, error }, { data: sets, error: setsError }] = await Promise.all([
      sb.from('coaching_schedule').select('*').eq('id', it.row.id).single(),
      sb.from('coaching_session_sets').select('*').eq('schedule_id', it.row.id)
    ]);
    if (error) throw error;
    if (setsError) throw setsError;
    if (row.board_id && !(Array.isArray(row.exercise_snapshot) && row.exercise_snapshot.length) && !coachBoardsById[row.board_id]) {
      const { data: b } = await sb.from('boards').select('id,name,color,exercises').eq('id', row.board_id).maybeSingle();
      if (b) coachBoardsById[b.id] = b;
    }
    const map = {};
    (sets || []).forEach((s) => { (map[s.ex_key] = map[s.ex_key] || []).push(s); });
    return { ...sessionStickerData(row, map), durationSec: row.duration_sec || it.durationSec,
      avgHr: it.avgHr || 0, kcal: it.kcal || 0, number: it.number };
  }
  async function skandiSessionData(it) {
    const { data: sets, error } = await sb.from('skandi_sets')
      .select('exercise_id,set_idx,sort_order,weight_kg,reps,seconds,done').eq('session_id', it.row.id).eq('done', true);
    if (error) throw error;
    const ids = [...new Set((sets || []).map((s) => s.exercise_id).filter(Boolean))];
    const names = {};
    if (ids.length) {
      const { data: ex } = await sb.from('skandi_exercises').select('id,name').in('id', ids);
      (ex || []).forEach((e) => { names[e.id] = e.name; });
    }
    return skandiStickerData(sets, names, {
      title: it.title, ds: it.ds, durationSec: it.durationSec, avgHr: it.avgHr, kcal: it.kcal, number: it.number
    });
  }
  function itemStickerData(it) {
    return {
      type: it.type, title: it.named ? it.title : '', ds: it.ds, durationSec: it.durationSec, distanceM: it.distanceM,
      elevationM: it.elevationM, avgHr: it.avgHr, kcal: it.kcal, effort: it.effort, number: it.number
    };
  }
  const needsSets = (it) => it.src === 'app' || it.key.startsWith('k:');
  function stickerData(it) {
    if (it.src === 'app') return appSessionData(it);
    if (it.key.startsWith('k:')) return skandiSessionData(it);
    return Promise.resolve(itemStickerData(it));
  }
  function subtitle(data) {
    const f = share().workoutFacts(data);
    return [f.title, ...f.summary].join(' · ');
  }
  async function shareItem(key) {
    const it = find(key), S = share();
    if (!it || !S) return;
    try {
      const data = await stickerData(it);
      S.open({ kind: 'workout', data, title: 'Tu entreno', subtitle: subtitle(data) });
    } catch (e) { say('No se pudo preparar el sticker: ' + (e.message || e), 'err'); }
  }
  function shareWeek() {
    const S = share();
    if (!state.data || !S) return;
    const w = weekSummary(state.data.items);
    S.open({ kind: 'week', data: w, title: 'Tu semana', subtitle: w.count + (w.count === 1 ? ' entreno' : ' entrenos') + (w.streak > 1 ? ' · ' + w.streak + ' semanas seguidas' : '') });
  }
  // Cuántos entrenos llevas en total (de todas las fuentes), para el «Nº» del sticker de uno
  // que acabas de cerrar.
  async function totalCount() {
    const uid = userId();
    if (!uid) return 0;
    const visible = await loadData();
    const head = { count: 'exact', head: true };
    const rs = await Promise.all([
      sb.from('coaching_schedule').select('id', head).eq('user_id', uid).eq('status', 'done'),
      sb.from('training_activities').select('id', head).eq('user_id', uid),
      sb.from('skandi_external_activities').select('id', head).eq('user_id', uid),
      sb.from('skandi_sessions').select('id', head).eq('user_id', uid).not('completed_at', 'is', null)
    ]);
    return Math.max(0, rs.reduce((n, r) => n + (r.error ? 0 : (r.count || 0)), 0) - (visible && visible.duplicates || 0));
  }
  // Al cerrar un entreno en la app, el premio: sus stickers (Crew lo llama desde
  // wsAfterSessionClosed). `row` es la fila cerrada de coaching_schedule; `setsMap`, sus series.
  async function offerSessionStickers(row, setsMap) {
    const S = share();
    if (!S || !row) return;
    try {
      const data = sessionStickerData(row, setsMap);
      data.number = await totalCount().catch(() => 0);
      S.open({ kind: 'workout', data, title: 'Entreno terminado', subtitle: subtitle(data) });
    } catch (e) { console.warn('offerSessionStickers:', e); }
  }

  // ── La hoja: detalle y registrar ───────────────────────────────────────

  function buildSheet() {
    if (sheet) return sheet;
    const el = doc.createElement('div');
    el.className = 'act-overlay';
    el.innerHTML = '<div class="act-sheet" role="dialog" aria-modal="true" aria-labelledby="act-sheet-title">'
      + '<div class="act-sheet-head"><h2 id="act-sheet-title"></h2><button type="button" class="act-sheet-close" data-act="close" aria-label="Cerrar">×</button></div>'
      + '<div class="act-sheet-body"></div></div>';
    doc.body.appendChild(el);
    el.addEventListener('click', (e) => { if (e.target === el) closeSheet(); });
    sheet = el;
    return el;
  }
  function openSheet(title, body) {
    buildSheet();
    sheet.querySelector('#act-sheet-title').textContent = title;
    sheet.querySelector('.act-sheet-body').innerHTML = body;
    sheet.querySelector('.act-sheet-body').scrollTop = 0;
    sheet.classList.add('open');
  }
  function setSheetBody(html, keepScroll) {
    if (!sheet) return;
    const body = sheet.querySelector('.act-sheet-body');
    if (keepScroll && typeof withScrollKept === 'function') withScrollKept(body, () => { body.innerHTML = html; });
    else body.innerHTML = html;
  }
  function closeSheet() {
    if (sheet) sheet.classList.remove('open');
    state.form = null; state.detailKey = null;
  }

  function sourceLabel(it) {
    if (it.src === 'app' && it.watchSource) return 'Entreno en HABIT · datos del reloj';
    if (it.src === 'app') return 'Entreno en la app';
    if (it.src === 'manual') return typeLabel(it.type);
    if (it.key.startsWith('k:')) return 'Fuerza · Skandi Fit';
    return typeLabel(it.type) + ' · ' + (it.src === 'intervals' ? 'de tu reloj' : it.src === 'strava' ? 'de Strava' : 'Skandi Fit');
  }
  async function openDetail(key) {
    const it = find(key);
    if (!it) return;
    state.detailKey = key; state.form = null;
    openSheet(it.title, detailHtml(it, needsSets(it) ? null : itemStickerData(it)));
    if (!needsSets(it)) return;
    try {
      const data = await stickerData(it);
      if (state.detailKey === key) setSheetBody(detailHtml(it, data));
    } catch (e) {
      if (state.detailKey === key) setSheetBody(detailHtml(it, { type: 'strength', title: it.title, ds: it.ds, durationSec: it.durationSec, number: it.number }));
    }
  }
  function detailHtml(it, data) {
    const S = share();
    const f = data && S ? S.workoutFacts(data) : null;
    let html = '<div class="act-d-top"><span class="act-ic big" style="--c:' + esc(it.color) + '">' + (ICONS[it.type] || ICONS.other) + '</span>'
      + '<div><div class="act-kicker">' + esc(fmtDS(it.ds)) + ' · Nº ' + it.number + '</div><div class="act-d-type">' + esc(sourceLabel(it)) + '</div></div></div>';
    if (!f) return html + '<div class="empty">Cargando…</div>';
    html += '<div class="act-d-hero">' + esc(f.hero.value) + '<span>' + esc(f.hero.label.toLowerCase()) + '</span></div>';
    const stats = f.stats.filter((s) => s.value !== f.hero.value + ' ' + f.hero.unit);
    if (stats.length) html += '<div class="act-d-stats">' + stats.map((s) => '<div><b>' + esc(s.value.toLowerCase()) + '</b><span>' + esc(s.label.toLowerCase()) + '</span></div>').join('') + '</div>';
    if (f.exercises.length) html += '<div class="act-d-ex">' + (data.exercises || []).map((e) => '<div><span>' + esc(e.name) + '</span><b>' + esc(e.best || '') + '</b></div>').join('') + '</div>';
    if (it.notes) html += '<p class="act-d-notes">' + esc(it.notes) + '</p>';
    html += '<button class="hs-share-main act-d-share" data-act="share" data-k="' + esc(it.key) + '">' + S.SHARE_ICON + 'Compartir sticker</button>';
    if (it.src === 'manual') html += '<div class="act-d-actions"><button class="btn-sm" data-act="edit" data-k="' + esc(it.key) + '">Editar</button><button class="btn-sm act-del" data-act="delete" data-k="' + esc(it.key) + '">Eliminar</button></div>';
    else if (it.src !== 'app') html += '<p class="act-d-src">Se corrige en ' + (it.src === 'intervals' ? 'tu reloj o en Intervals.icu' : it.src === 'strava' ? 'Strava' : 'Skandi Fit') + '.</p>';
    return html;
  }

  // Lo mínimo es el tipo y cuánto duró (o la distancia); todo lo demás es opcional y va plegado
  // en «Más datos», para que registrar una corrida sean tres toques y un número.
  function openForm(key) {
    const it = key ? find(key) : null;
    const a = it && it.src === 'manual' ? it.row : null;
    const dur = a && a.duration_sec || 0;
    state.form = {
      id: a ? a.id : null, kind: a ? a.kind : 'run', ds: a ? a.ds : mazToday(),
      h: dur ? String(Math.floor(dur / 3600)) : '', m: dur ? String(Math.round((dur % 3600) / 60)) : '',
      dist: a && a.distance_m ? String(a.kind === 'swim' ? a.distance_m : Math.round(a.distance_m) / 1000) : '',
      title: a && a.title || '', effort: a && a.effort || 0, avg_hr: a && a.avg_hr || '', kcal: a && a.kcal || '',
      elevation_m: a && a.elevation_m || '', notes: a && a.notes || '', more: !!(a && (a.avg_hr || a.kcal || a.elevation_m || a.notes))
    };
    state.detailKey = null;
    openSheet(state.form.id ? 'Editar actividad' : 'Registrar actividad', formHtml());
  }
  // Lo escrito vive en el DOM: antes de repintar (cambiar de tipo, de día) se copia al estado.
  function readForm() {
    const f = state.form;
    if (!f || !sheet) return;
    const v = (id) => { const el = sheet.querySelector('#act-f-' + id); return el ? el.value : null; };
    ['h', 'm', 'dist', 'title', 'avg_hr', 'kcal', 'elevation_m', 'notes'].forEach((k) => { const x = v(k); if (x !== null) f[k] = x; });
    const more = sheet.querySelector('#act-f-more');
    if (more) f.more = more.open;
    const date = v('date');
    if (date && /^\d{4}-\d{2}-\d{2}$/.test(date)) f.ds = date;
  }
  // Quien repinta ya leyó el formulario y cambió algo: volver a leer aquí pisaría ese cambio con
  // lo que seguía en pantalla («Ayer» o «90 min» no hacían nada).
  function repaintForm() { setSheetBody(formHtml(), true); }
  function formHtml() {
    const f = state.form, today = mazToday(), yesterday = addDaysDS(today, -1);
    const swim = f.kind === 'swim';
    const field = (id, label, attrs, val) => '<label class="act-f"><span>' + label + '</span><input id="act-f-' + id + '" ' + attrs + ' value="' + esc(val) + '"></label>';
    return '<div class="act-types">' + TYPES.map((t) => '<button class="act-type' + (f.kind === t ? ' on' : '') + '" style="--c:' + COLORS[t] + '" data-act="kind" data-v="' + t + '">' + ICONS[t] + '<span>' + esc(typeLabel(t)) + '</span></button>').join('') + '</div>'
      + '<div class="act-k">¿Cuándo?</div>'
      + '<div class="act-chips"><button class="act-chip' + (f.ds === today ? ' on' : '') + '" data-act="day" data-v="' + today + '">Hoy</button>'
      + '<button class="act-chip' + (f.ds === yesterday ? ' on' : '') + '" data-act="day" data-v="' + yesterday + '">Ayer</button>'
      + '<input id="act-f-date" class="act-date' + (f.ds !== today && f.ds !== yesterday ? ' on' : '') + '" type="date" max="' + today + '" value="' + esc(f.ds) + '" data-act-change="day" aria-label="Otro día"></div>'
      + '<div class="act-k">¿Cuánto duró?</div>'
      + '<div class="act-dur">' + field('h', 'horas', 'type="number" inputmode="numeric" min="0" max="24" placeholder="0"', f.h) + field('m', 'minutos', 'type="number" inputmode="numeric" min="0" max="59" placeholder="45"', f.m) + '</div>'
      + '<div class="act-chips act-quick">' + [20, 30, 45, 60, 90].map((n) => '<button class="act-chip" data-act="minutes" data-v="' + n + '">' + (n < 60 ? n + ' min' : (n === 60 ? '1 h' : '1 h 30')) + '</button>').join('') + '</div>'
      + (hasDistance(f.kind) ? '<div class="act-k">Distancia</div><div class="act-dist">' + field('dist', swim ? 'metros' : 'kilómetros', 'type="number" inputmode="decimal" min="0" step="' + (swim ? '25' : '0.01') + '" placeholder="' + (swim ? '1500' : '5.0') + '"', f.dist) + '</div>' : '')
      + '<div class="act-k">Nombre <em>opcional</em></div>'
      + '<label class="act-f"><input id="act-f-title" type="text" maxlength="80" placeholder="' + esc(typeNoun(f.kind)) + '" value="' + esc(f.title) + '"></label>'
      + '<div class="act-k">¿Qué tal estuvo? <em>opcional</em></div>'
      + '<div class="act-chips">' + EFFORTS.map(([n, l]) => '<button class="act-chip' + (f.effort === n ? ' on' : '') + '" data-act="effort" data-v="' + n + '">' + l + '</button>').join('') + '</div>'
      + '<details id="act-f-more" class="act-more-fields"' + (f.more ? ' open' : '') + '><summary>Más datos</summary>'
      + '<div class="act-dur">' + field('avg_hr', 'FC promedio', 'type="number" inputmode="numeric" min="30" max="250" placeholder="lpm"', f.avg_hr) + field('kcal', 'calorías', 'type="number" inputmode="numeric" min="0" placeholder="kcal"', f.kcal) + '</div>'
      + (hasDistance(f.kind) ? '<div class="act-dur">' + field('elevation_m', 'desnivel', 'type="number" inputmode="numeric" min="0" placeholder="metros"', f.elevation_m) + '</div>' : '')
      + '<label class="act-f"><span>notas</span><textarea id="act-f-notes" rows="3" maxlength="500" placeholder="Cómo te sentiste, con quién, dónde…">' + esc(f.notes) + '</textarea></label>'
      + '</details>'
      + '<button class="btn act-save" data-act="save">' + (f.id ? 'Guardar cambios' : 'Guardar') + '</button>';
  }
  async function save() {
    const uid = userId();
    if (!state.form || !uid) return;
    readForm();
    const f = state.form, num = (x) => { const n = parseFloat(String(x || '').replace(',', '.')); return isFinite(n) && n > 0 ? n : 0; };
    const dur = Math.round(num(f.h) * 3600 + num(f.m) * 60);
    const dist = hasDistance(f.kind) && num(f.dist) ? Math.round(f.kind === 'swim' ? num(f.dist) : num(f.dist) * 1000) : 0;
    if (!dur && !dist) { say('Escribe cuánto duró' + (hasDistance(f.kind) ? ' o la distancia' : ''), 'warn'); return; }
    if (dur && dur < 60) { say('Pon al menos un minuto', 'warn'); return; }
    if (dur > 86400) { say('Eso es más de un día', 'warn'); return; }
    if (f.ds > mazToday()) { say('Ese día todavía no llega', 'warn'); return; }
    const int = (x, lo, hi) => { const n = Math.round(num(x)); return n >= lo && n <= hi ? n : null; };
    const payload = {
      kind: f.kind, ds: f.ds, title: String(f.title || '').trim().slice(0, 80) || null, duration_sec: dur || null, distance_m: dist || null,
      effort: f.effort || null, avg_hr: int(f.avg_hr, 30, 250), kcal: int(f.kcal, 1, 20000), elevation_m: hasDistance(f.kind) ? int(f.elevation_m, 1, 20000) : null,
      notes: String(f.notes || '').trim().slice(0, 500) || null
    };
    const btn = sheet && sheet.querySelector('.act-save');
    if (btn) btn.disabled = true;
    try {
      const q = f.id
        ? sb.from('training_activities').update(payload).eq('id', f.id).eq('user_id', uid).select().single()
        : sb.from('training_activities').insert({ ...payload, user_id: uid }).select().single();
      const { data, error } = await q;
      if (error) throw error;
      const fresh = !f.id;
      closeSheet();
      await loadData(true);
      paint();
      say(fresh ? 'Actividad guardada' : 'Cambios guardados', 'ok');
      // Recién registrada, el sticker: es para lo que muchos la registran.
      if (fresh) shareItem('a:' + data.id);
    } catch (e) {
      if (btn) btn.disabled = false;
      say(isMissingTable(e) ? 'Falta activar el registro de actividades' : 'No se pudo guardar: ' + (e.message || e), 'err');
    }
  }
  async function remove(key) {
    const it = find(key), uid = userId();
    if (!it || it.src !== 'manual' || !uid) return;
    if (!await confirmSheet('¿Eliminar «' + it.title + '» del ' + fmtDS(it.ds) + '?', { danger: true, confirmLabel: 'Eliminar' })) return;
    const { error } = await sb.from('training_activities').delete().eq('id', it.row.id).eq('user_id', uid);
    if (error) { say('No se pudo eliminar: ' + error.message, 'err'); return; }
    closeSheet();
    await loadData(true);
    paint();
    say('Actividad eliminada', 'ok');
  }

  // Un solo escucha para todo lo que pinta la sección (la lista y la hoja se repintan con
  // innerHTML, así que nada lleva su propio onclick).
  function onClick(e) {
    const t = e.target && e.target.closest && e.target.closest('[data-act]');
    if (!t) return;
    const act = t.getAttribute('data-act'), key = t.getAttribute('data-k'), v = t.getAttribute('data-v');
    if (act === 'detail') openDetail(key);
    else if (act === 'share') shareItem(key);
    else if (act === 'share-week') shareWeek();
    else if (act === 'add') openForm();
    else if (act === 'edit') openForm(key);
    else if (act === 'delete') remove(key);
    else if (act === 'filter') { state.filter = v; paint(); }
    else if (act === 'more') { state.windowDays += 180; render(); }
    else if (act === 'sync') autoSync(true);
    else if (act === 'train') { if (typeof sv === 'function') sv('rutinas'); }
    else if (act === 'close') closeSheet();
    else if (!state.form) return;
    else if (act === 'kind') { readForm(); state.form.kind = v; repaintForm(); }
    else if (act === 'day') { readForm(); state.form.ds = v; repaintForm(); }
    else if (act === 'effort') { readForm(); const n = Number(v); state.form.effort = state.form.effort === n ? 0 : n; repaintForm(); }
    else if (act === 'minutes') {
      readForm();
      const min = Number(v);
      state.form.h = min >= 60 ? String(Math.floor(min / 60)) : '';
      state.form.m = String(min % 60 || (min >= 60 ? '0' : ''));
      repaintForm();
    } else if (act === 'save') save();
  }
  function onChange(e) {
    const t = e.target;
    if (!t || !t.getAttribute || t.getAttribute('data-act-change') !== 'day' || !state.form) return;
    readForm();
    if (/^\d{4}-\d{2}-\d{2}$/.test(t.value)) state.form.ds = t.value;
    repaintForm();
  }
  function onKey(e) {
    if (e.key === 'Escape' && sheet && sheet.classList.contains('open')) closeSheet();
    else if ((e.key === 'Enter' || e.key === ' ') && e.target && e.target.classList && e.target.classList.contains('act-row')) {
      e.preventDefault(); openDetail(e.target.getAttribute('data-k'));
    }
  }

  // Mismo lenguaje que la tarjeta de hoy de Crew: etiqueta chica espaciada, cifras grandes, sin
  // cajas dentro de cajas. Colores de las dos apps (--card, --surface…; son el mismo grafito).
  // Campos de 16 px: con menos, el iPhone hace zoom al escribir.
  const CSS = `
.act-top{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:2px 2px 14px;min-height:40px}
.act-kicker{font-size:11px;font-weight:600;letter-spacing:.22em;text-transform:uppercase;color:var(--gray,#8a8f99)}
.act-add{display:inline-flex;align-items:center;gap:6px;border:0;border-radius:999px;background:var(--white,#fff);color:#0b0b0b;font:700 14px 'Inter',sans-serif;padding:10px 16px 10px 12px;cursor:pointer;flex-shrink:0}
.act-add svg{width:17px;height:17px;fill:none;stroke:currentColor;stroke-width:2.2;stroke-linecap:round}
.act-sync{display:flex;align-items:center;gap:8px;margin:-6px 2px 14px;font-size:12.5px;color:var(--gray,#8a8f99)}
.act-sync svg{width:15px;height:15px;flex-shrink:0;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.act-sync.busy svg{animation:actSpin 1s linear infinite}
.act-sync.err{color:#f59e0b}
.act-sync span{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.act-sync button{border:0;background:var(--surface,#23252b);color:var(--gl,#c9ccd2);border-radius:999px;font:600 12px 'Inter',sans-serif;padding:6px 11px;cursor:pointer;flex-shrink:0}
.act-week{background:var(--card,#1c1d21);border-radius:22px;padding:20px 18px 16px;margin-bottom:18px}
.act-week-n{display:flex;align-items:center;gap:14px;font-size:64px;font-weight:900;letter-spacing:-.05em;line-height:.9;color:var(--white,#fff)}
.act-week-n span{font-size:13px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;line-height:1.35;color:var(--gray,#8a8f99)}
.act-week-meta{font-size:14px;color:var(--gl,#c9ccd2);margin-top:12px}
.act-week-days{display:grid;grid-template-columns:repeat(7,1fr);gap:4px;margin-top:16px;text-align:center;font-size:11px;font-weight:600;color:var(--gray,#8a8f99)}
.act-week-days span{display:flex;flex-direction:column;align-items:center;gap:6px}
.act-week-days i{width:26px;height:26px;border-radius:50%;border:1.5px dashed rgba(255,255,255,.18)}
.act-week-days .on i{border:0;background:#22c55e;box-shadow:0 0 0 4px rgba(34,197,94,.14)}
.act-week-days .on{color:var(--white,#fff)}
.act-week-share,.act-row-share{display:inline-flex;align-items:center;gap:7px;border:0;background:none;color:var(--gl,#c9ccd2);font:600 13px 'Inter',sans-serif;cursor:pointer}
.act-week-share{margin-top:16px;padding:6px 0;letter-spacing:.06em;text-transform:uppercase;font-size:12px}
.act-week-share svg,.act-row-share svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
.act-filters{display:flex;gap:6px;overflow-x:auto;margin:0 -16px 6px;padding:2px 16px 8px;scrollbar-width:none}
.act-filters::-webkit-scrollbar{display:none}
.act-filter{flex-shrink:0;border:0;border-radius:999px;background:var(--surface,#23252b);color:var(--gl,#c9ccd2);font:600 13px 'Inter',sans-serif;padding:8px 14px;cursor:pointer}
.act-filter.on{background:var(--white,#fff);color:#0b0b0b}
.act-month{display:flex;justify-content:space-between;font-size:11px;font-weight:600;letter-spacing:.22em;text-transform:uppercase;color:var(--gray,#8a8f99);margin:18px 2px 8px}
.act-row{display:flex;align-items:center;gap:12px;padding:10px 2px;border-radius:14px;cursor:pointer}
.act-row:active{background:var(--surface,#23252b)}
.act-ic{--c:#2563eb;width:44px;height:44px;border-radius:14px;flex-shrink:0;display:flex;align-items:center;justify-content:center;background:color-mix(in srgb,var(--c) 17%,transparent);color:var(--c)}
.act-ic svg{width:23px;height:23px;fill:none;stroke:currentColor;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}
.act-ic.big{width:52px;height:52px;border-radius:16px}
.act-ic.big svg{width:27px;height:27px}
.act-row-main{flex:1;min-width:0;display:flex;flex-direction:column;gap:3px}
.act-row-t{font-size:15.5px;font-weight:700;color:var(--white,#fff);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.act-row-m{font-size:12.5px;color:var(--gray,#8a8f99);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.act-row-share{width:42px;height:42px;justify-content:center;border-radius:50%;flex-shrink:0}
.act-row-share:active{background:var(--surface,#23252b)}
.act-more{display:block;margin:18px auto 6px;border:0;background:none;color:var(--gray,#8a8f99);font:600 13px 'Inter',sans-serif;padding:10px;cursor:pointer}
.act-note,.act-d-src{font-size:12.5px;color:var(--gray,#8a8f99);text-align:center;margin:10px 0}
.act-empty{text-align:center;padding:36px 12px 20px;display:flex;flex-direction:column;align-items:center;gap:12px}
.act-empty-ic{display:flex;gap:10px;color:var(--gray,#8a8f99)}
.act-empty-ic svg{width:28px;height:28px;fill:none;stroke:currentColor;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}
.act-empty-t{font-size:22px;font-weight:800;letter-spacing:-.02em;color:var(--white,#fff)}
.act-empty p{font-size:14px;line-height:1.5;color:var(--gray,#8a8f99);max-width:300px;margin:0 0 6px}
.act-empty .btn{max-width:300px}
.act-overlay{position:fixed;inset:0;z-index:10000;background:rgba(6,7,9,.66);display:none;align-items:flex-end;justify-content:center}
.act-overlay.open{display:flex;animation:actFade .18s ease both}
.act-sheet{width:100%;max-width:520px;max-height:92vh;background:var(--black,#141518);color:var(--white,#fff);border-radius:22px 22px 0 0;display:flex;flex-direction:column;overflow:hidden;animation:actUp .3s cubic-bezier(.2,.8,.2,1) both;padding-bottom:env(safe-area-inset-bottom,0px);font-family:'Inter',sans-serif}
.act-sheet-head{display:flex;align-items:center;gap:12px;padding:16px 16px 4px}
.act-sheet-head h2{flex:1;min-width:0;margin:0;font-size:17px;font-weight:700;letter-spacing:0;text-transform:none;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--white,#fff)}
.act-sheet-close{background:none;border:0;color:#9aa0aa;font-size:26px;line-height:1;cursor:pointer;padding:4px 6px}
.act-sheet-body{overflow-y:auto;overscroll-behavior:contain;padding:12px 16px 22px;line-height:1.4}
.act-d-top{display:flex;align-items:center;gap:12px}
.act-d-type{font-size:15px;font-weight:700;color:var(--white,#fff);margin-top:4px}
.act-d-hero{font-size:76px;font-weight:900;letter-spacing:-.05em;line-height:1;color:var(--white,#fff);margin:22px 0 4px;display:flex;align-items:baseline;gap:10px;flex-wrap:wrap}
.act-d-hero span{font-size:15px;font-weight:600;letter-spacing:.04em;color:var(--gray,#8a8f99)}
.act-d-stats{display:grid;grid-template-columns:repeat(3,1fr);gap:16px 10px;margin:18px 0 6px}
.act-d-stats b{display:block;font-size:19px;font-weight:800;color:var(--white,#fff);letter-spacing:-.01em}
.act-d-stats span{font-size:11px;color:var(--gray,#8a8f99);letter-spacing:.06em}
.act-d-ex{margin:16px 0 4px;display:grid;gap:2px}
.act-d-ex div{display:flex;justify-content:space-between;gap:12px;padding:9px 0;font-size:14px;color:var(--gl,#c9ccd2)}
.act-d-ex b{color:var(--white,#fff);font-weight:700;white-space:nowrap}
.act-d-notes{font-size:14px;color:var(--gl,#c9ccd2);line-height:1.5;margin:14px 0 0;white-space:pre-wrap}
.act-d-share{margin-top:22px}
.act-d-actions{display:flex;justify-content:center;gap:10px;margin-top:12px}
.act-del{color:#ef4444!important}
.act-types{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}
.act-type{--c:#2563eb;display:flex;flex-direction:column;align-items:center;gap:6px;border:0;border-radius:16px;background:var(--surface,#23252b);color:var(--gl,#c9ccd2);font:600 12.5px 'Inter',sans-serif;padding:12px 4px 10px;cursor:pointer}
.act-type svg{width:24px;height:24px;fill:none;stroke:var(--c);stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}
.act-type.on{background:color-mix(in srgb,var(--c) 20%,transparent);color:var(--white,#fff);box-shadow:inset 0 0 0 1.5px var(--c)}
.act-k{font-size:11px;font-weight:600;letter-spacing:.2em;text-transform:uppercase;color:var(--gray,#8a8f99);margin:20px 2px 8px}
.act-k em{font-style:normal;letter-spacing:.06em;text-transform:none;opacity:.7;margin-left:4px}
.act-chips{display:flex;flex-wrap:wrap;gap:6px;align-items:center}
.act-chip{border:0;border-radius:999px;background:var(--surface,#23252b);color:var(--gl,#c9ccd2);font:600 14px 'Inter',sans-serif;padding:9px 14px;cursor:pointer}
.act-chip.on{background:var(--white,#fff);color:#0b0b0b}
.act-date{border:0;border-radius:999px;background:var(--surface,#23252b);color:var(--gl,#c9ccd2);font:600 14px 'Inter',sans-serif;padding:8px 12px;min-height:36px;color-scheme:dark}
.act-date.on{background:var(--white,#fff);color:#0b0b0b;color-scheme:light}
.act-quick{margin-top:8px}
.act-quick .act-chip{font-size:13px;padding:7px 12px}
.act-dur,.act-dist{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.act-dist{grid-template-columns:1fr}
.act-f{display:flex;flex-direction:column;gap:5px;position:relative}
.act-f span{font-size:11px;color:var(--gray,#8a8f99);letter-spacing:.04em;padding-left:4px}
.act-f input,.act-f textarea{width:100%;box-sizing:border-box;border:0;border-radius:14px;background:var(--card2,#26282e);color:var(--white,#fff);font:600 16px 'Inter',sans-serif;padding:13px 14px;outline:none}
.act-f textarea{font-weight:500;resize:none;line-height:1.45}
.act-f input:focus,.act-f textarea:focus{box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.35)}
.act-more-fields{margin-top:18px}
.act-more-fields summary{font-size:13px;font-weight:600;color:var(--gl,#c9ccd2);cursor:pointer;padding:6px 2px;list-style:none}
.act-more-fields summary::-webkit-details-marker{display:none}
.act-more-fields summary::before{content:'+ '}
.act-more-fields[open] summary::before{content:'– '}
.act-more-fields>*+*{margin-top:8px}
.act-save{margin-top:22px}
@keyframes actFade{from{opacity:0}to{opacity:1}}
@keyframes actUp{from{transform:translateY(40px);opacity:.4}to{transform:none;opacity:1}}
@keyframes actSpin{to{transform:rotate(360deg)}}
@media (prefers-reduced-motion:reduce){.act-overlay.open,.act-sheet,.act-sync.busy svg{animation:none}}`;

  if (doc && doc.addEventListener) {
    if (doc.head && !doc.getElementById('act-css')) {
      const style = doc.createElement('style');
      style.id = 'act-css';
      style.textContent = CSS;
      doc.head.appendChild(style);
    }
    doc.addEventListener('click', onClick);
    doc.addEventListener('change', onChange);
    doc.addEventListener('keydown', onKey);
  }

  const api = {
    APP_GLOBALS, TYPES, DIST_TYPES, COLORS, typeFromSkandi, itemFromAppSession, itemFromManual, itemFromSkandiActivity,
    itemFromSkandiSession, numberItems, reconcileActivities, syncWindowDays, syncDue, skandiBestSet, skandiStickerData,
    render, invalidate, offerSessionStickers, totalCount
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.HabitActivity = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
