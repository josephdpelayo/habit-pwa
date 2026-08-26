// Skandi Fit — la cola de escrituras pendientes.
//
// El contexto de uso es un barco. La señal se va, y hasta aquí eso significaba que marcar una
// serie a media rutina soltaba una alerta con el error crudo del navegador ("Load failed" en
// iOS) y dejaba la serie SIN marcar: la app te peleaba justo cuando estabas entrenando.
//
// Lo que se encola aquí son UPDATE sobre filas que YA existen, identificadas por su id. Ese
// recorte no es pereza, es lo que hace que la cola sea segura sin inventar un motor de
// sincronización:
//
//   - Son idempotentes: reenviar el mismo patch dos veces deja la fila igual.
//   - No generan ids, así que no hay filas huérfanas si la cola se pierde.
//   - No tienen orden entre sí más allá de "sobre la misma fila, el último gana", que es
//     exactamente lo que hace el merge de abajo.
//
// Un INSERT (empezar un entrenamiento, registrar una comida) no cumple nada de eso y por eso
// NO se encola: haría falta generar el id en el cliente y respetar dependencias entre filas.
// Queda para otra pasada, con la puerta abierta pero sin fingir que ya está.
//
// El módulo es puro a propósito —ni DOM ni Supabase— para poder ejercitarlo desde Node, igual
// que skandi-recovery.js o skandi-nutrition.js. Quien lo usa (skandi.html) pone el transporte.

(function (global) {

// Un tope por si algo se atasca: sin él, semanas sin señal llenarían localStorage y la app
// dejaría de arrancar. Al pasarse, se tira lo MÁS VIEJO — lo reciente es lo que el miembro
// acaba de hacer y lo que espera ver.
const MAX_ENTRIES = 300;

const keyOf = (table, id) => `${table}:${id}`;

// Mete un patch en la cola. Si ya había uno para la misma fila, se funden campo por campo y
// gana el nuevo: dos toques seguidos al mismo peso no son dos escrituras, son una.
function enqueue(queue, entry, now) {
  const list = Array.isArray(queue) ? queue.slice() : [];
  const at = Number(now) || Date.now();
  if (!entry || !entry.table || !entry.id || !entry.patch) return list;
  const key = keyOf(entry.table, entry.id);
  const idx = list.findIndex(e => keyOf(e.table, e.id) === key);
  if (idx >= 0) {
    const prev = list[idx];
    list[idx] = {
      table: prev.table,
      id: prev.id,
      patch: Object.assign({}, prev.patch, entry.patch),
      // firstAt es lo que se le enseña al miembro ("desde hace 20 min"), así que sobrevive al
      // merge; lastAt manda para el orden de envío.
      firstAt: prev.firstAt || at,
      lastAt: at,
      tries: prev.tries || 0
    };
    return list;
  }
  list.push({ table: entry.table, id: entry.id, patch: Object.assign({}, entry.patch), firstAt: at, lastAt: at, tries: 0 });
  return list.length > MAX_ENTRIES ? list.slice(list.length - MAX_ENTRIES) : list;
}

function drop(queue, table, id) {
  const key = keyOf(table, id);
  return (Array.isArray(queue) ? queue : []).filter(e => keyOf(e.table, e.id) !== key);
}

function bumpTries(queue, table, id) {
  const key = keyOf(table, id);
  return (Array.isArray(queue) ? queue : []).map(e =>
    keyOf(e.table, e.id) === key ? Object.assign({}, e, { tries: (e.tries || 0) + 1 }) : e);
}

const pending = queue => (Array.isArray(queue) ? queue.length : 0);
const pendingFor = (queue, table) => (Array.isArray(queue) ? queue : []).filter(e => e.table === table).length;

// La pieza que evita el bug silencioso: una recarga del servidor trae la fila SIN el cambio
// que todavía está en la cola, así que sin esto un loadAll() en segundo plano desmarcaría la
// serie que el miembro acaba de marcar. Se vuelven a poner encima los patches pendientes.
function applyTo(queue, table, rows) {
  const list = (Array.isArray(queue) ? queue : []).filter(e => e.table === table);
  if (!list.length || !Array.isArray(rows)) return rows;
  const byId = new Map(list.map(e => [e.id, e.patch]));
  return rows.map(r => {
    const patch = r && byId.get(r.id);
    return patch ? Object.assign({}, r, patch) : r;
  });
}

// El más viejo primero: se envía en el orden en que ocurrió, que es el orden en que el miembro
// lo vivió.
function nextUp(queue) {
  const list = (Array.isArray(queue) ? queue : []).slice()
    .sort((a, b) => (a.firstAt || 0) - (b.firstAt || 0));
  return list[0] || null;
}

function serialize(queue) {
  try { return JSON.stringify(Array.isArray(queue) ? queue : []); }
  catch (e) { return '[]'; }
}

// Lo que sale de localStorage no es de fiar: puede venir de una versión anterior, a medio
// escribir, o simplemente no ser un arreglo. Una cola corrupta no debe impedir que la app
// arranque, así que lo que no encaja se descarta en silencio en vez de reventar.
function parse(raw) {
  let data;
  try { data = JSON.parse(raw || '[]'); } catch (e) { return []; }
  if (!Array.isArray(data)) return [];
  return data
    .filter(e => e && typeof e === 'object' && typeof e.table === 'string' && e.id
      && e.patch && typeof e.patch === 'object' && !Array.isArray(e.patch))
    .map(e => ({
      table: e.table, id: String(e.id), patch: e.patch,
      firstAt: Number(e.firstAt) || Date.now(),
      lastAt: Number(e.lastAt) || Number(e.firstAt) || Date.now(),
      tries: Number(e.tries) || 0
    }))
    .slice(0, MAX_ENTRIES);
}

// Un fallo de red se reintenta; uno de datos, no. Reintentar para siempre un error de
// constraint o de RLS es cómo una cola se convierte en un bucle que nunca vacía y que además
// esconde el problema real. `offline` manda sobre el mensaje: si el dispositivo dice que no
// hay red, cualquier fallo es de red.
const NETWORK_HINTS = ['load failed', 'failed to fetch', 'networkerror', 'network error',
                       'timeout', 'timed out', 'connection', 'err_internet', 'offline'];
function isRetryable(err, offline) {
  if (offline) return true;
  const msg = String((err && (err.message || err.msg)) || err || '').toLowerCase();
  if (!msg) return false;
  return NETWORK_HINTS.some(h => msg.includes(h));
}

// Tras varios intentos fallidos que NO son de red, la entrada está envenenada: se suelta y se
// avisa, en vez de dejarla bloqueando a las de atrás para siempre.
const MAX_TRIES = 5;
const isPoisoned = entry => (entry && entry.tries || 0) >= MAX_TRIES;

const api = {
  MAX_ENTRIES, MAX_TRIES,
  enqueue, drop, bumpTries, pending, pendingFor, applyTo, nextUp,
  serialize, parse, isRetryable, isPoisoned, keyOf
};

if (typeof module !== 'undefined' && module.exports) module.exports = api;
global.SkandiOutbox = api;

})(typeof globalThis !== 'undefined' ? globalThis : this);
