// HABIT Training — utilidades puras y outbox IndexedDB para Entrenar.
(function (global) {
  'use strict';

  const DB_NAME = 'habit-training';
  const STORE = 'outbox';
  const DB_VERSION = 1;
  const MAX_ENTRIES = 500;

  const keyOf = (table, id) => `${table}:${id}`;

  function mergeEntries(entries, entry, now) {
    const list = Array.isArray(entries) ? entries.slice() : [];
    if (!entry || !entry.table || !entry.id || !entry.patch) return list;
    const at = Number(now) || Date.now();
    const key = keyOf(entry.table, entry.id);
    const idx = list.findIndex(item => item.key === key);
    const next = {
      key,
      table: String(entry.table),
      id: String(entry.id),
      patch: Object.assign({}, idx >= 0 ? list[idx].patch : {}, entry.patch),
      firstAt: idx >= 0 ? list[idx].firstAt : at,
      lastAt: at,
      tries: idx >= 0 ? (list[idx].tries || 0) : 0
    };
    if (idx >= 0) list[idx] = next;
    else list.push(next);
    return list.sort((a, b) => a.firstAt - b.firstAt).slice(-MAX_ENTRIES);
  }

  function applyPending(entries, table, rows) {
    const patches = new Map((entries || []).filter(e => e.table === table).map(e => [e.id, e.patch]));
    return (rows || []).map(row => patches.has(String(row.id))
      ? Object.assign({}, row, patches.get(String(row.id)), {_pendingSync: true})
      : row);
  }

  const NETWORK_HINTS = [
    'load failed', 'failed to fetch', 'networkerror', 'network error', 'timeout',
    'timed out', 'connection', 'err_internet', 'offline'
  ];
  function isRetryable(error, offline) {
    if (offline) return true;
    const message = String(error && (error.message || error.msg) || error || '').toLowerCase();
    return NETWORK_HINTS.some(hint => message.includes(hint));
  }

  function metricType(exercise) {
    const raw = String(exercise && (
      exercise.metricType || exercise.default_tracking || exercise.repsType || exercise.tracking
    ) || '').toLowerCase();
    if (raw === 'time' || raw === 'seconds' || raw === 'isometric') return 'time';
    if (raw === 'distance' || raw === 'meters' || raw === 'metres') return 'distance';
    return 'reps';
  }

  function parseSeconds(value) {
    const raw = String(value == null ? '' : value).trim().toLowerCase();
    if (!raw) return null;
    if (/^\d+(\.\d+)?$/.test(raw)) return Math.round(Number(raw));
    const colon = raw.match(/^(\d+):(\d{1,2})$/);
    if (colon) return Number(colon[1]) * 60 + Number(colon[2]);
    const minutes = raw.match(/^(\d+(?:\.\d+)?)\s*m(?:in)?$/);
    if (minutes) return Math.round(Number(minutes[1]) * 60);
    const seconds = raw.match(/^(\d+(?:\.\d+)?)\s*s(?:ec)?$/);
    if (seconds) return Math.round(Number(seconds[1]));
    return null;
  }

  function estimated1RM(weight, reps) {
    const w = Number(weight), r = Number(reps);
    if (!(w > 0) || !(r > 0)) return 0;
    return r === 1 ? w : w * (1 + Math.min(r, 30) / 30);
  }

  function sortScores(rows) {
    return (rows || []).slice().sort((a, b) =>
      new Date(a.logged_at || 0).getTime() - new Date(b.logged_at || 0).getTime());
  }

  // Si la semana actual todavía no tiene entreno, la racha se cuenta desde la
  // anterior. Así el lunes por la mañana no borra visualmente meses de trabajo.
  function weeklyStreak(weekKeys, currentWeek, previousWeek) {
    const weeks = new Set(weekKeys || []);
    let cursor = weeks.has(currentWeek) ? currentWeek : previousWeek;
    let streak = 0;
    while (weeks.has(cursor)) {
      streak++;
      const date = new Date(cursor + 'T12:00:00');
      date.setDate(date.getDate() - 7);
      const y = date.getFullYear();
      const m = String(date.getMonth() + 1).padStart(2, '0');
      const d = String(date.getDate()).padStart(2, '0');
      cursor = `${y}-${m}-${d}`;
    }
    return streak;
  }

  function database() {
    return new Promise((resolve, reject) => {
      if (!global.indexedDB) return reject(new Error('IndexedDB unavailable'));
      const request = global.indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE, {keyPath: 'key'});
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error || new Error('Could not open training outbox'));
    });
  }

  async function list() {
    const db = await database();
    return new Promise((resolve, reject) => {
      const request = db.transaction(STORE, 'readonly').objectStore(STORE).getAll();
      request.onsuccess = () => resolve((request.result || []).sort((a,b) => a.firstAt - b.firstAt));
      request.onerror = () => reject(request.error);
    });
  }

  async function enqueue(entry) {
    const db = await database();
    const existing = await list();
    const merged = mergeEntries(existing, entry);
    const next = merged.find(item => item.key === keyOf(entry.table, entry.id));
    return new Promise((resolve, reject) => {
      const request = db.transaction(STORE, 'readwrite').objectStore(STORE).put(next);
      request.onsuccess = () => resolve(next);
      request.onerror = () => reject(request.error);
    });
  }

  async function remove(key) {
    const db = await database();
    return new Promise((resolve, reject) => {
      const request = db.transaction(STORE, 'readwrite').objectStore(STORE).delete(key);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
  }

  async function bump(entry) {
    const db = await database();
    const next = Object.assign({}, entry, {tries: (entry.tries || 0) + 1, lastAt: Date.now()});
    return new Promise((resolve, reject) => {
      const request = db.transaction(STORE, 'readwrite').objectStore(STORE).put(next);
      request.onsuccess = () => resolve(next);
      request.onerror = () => reject(request.error);
    });
  }

  const api = {
    MAX_ENTRIES, keyOf, mergeEntries, applyPending, isRetryable,
    metricType, parseSeconds, estimated1RM, sortScores, weeklyStreak,
    list, enqueue, remove, bump
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.HabitTraining = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
