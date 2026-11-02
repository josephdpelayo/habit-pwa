// HABIT Skills — escaleras de calistenia: la curva de progreso, el estándar y los cues.
//
// Módulo puro: sin DOM y sin Supabase, igual que skandi-recovery.js, para poder ejercitarlo
// desde Node (scripts/check-skills.js). Trae a HABIT el motor de las migraciones 078/079 de
// Skandi, con una diferencia que no es un detalle: **aquí nada sube de escalón solo.**
// readiness() dice "ya cumple el estándar" y el coach decide, porque la forma de un front
// lever la juzga quien ve el video, no quien lo hace. Ver migración 141.
//
// Depende de HabitTraining (metricType, parseSeconds) y lo busca en cada llamada, así que el
// orden de los <script> no importa. En Node, el test carga habit-training.js primero.
(function (global) {
  'use strict';

  const ht = () => global.HabitTraining;

  // ---- La escalera -------------------------------------------------------------------------

  // Los escalones de una línea, del más fácil al más difícil. Un escalón sin rank no entra:
  // sin posición no es un escalón, y dejarlo colarse desordenaría toda la curva.
  function rungs(catalog, group) {
    if (!group) return [];
    return (catalog || [])
      .filter(ex => ex && ex.progression_group === group && Number(ex.progression_rank) > 0)
      .slice()
      .sort((a, b) => Number(a.progression_rank) - Number(b.progression_rank));
  }

  const rungAt = (list, rank) => (list || []).find(ex => Number(ex.progression_rank) === Number(rank)) || null;
  const topRank = list => ((list || []).length ? Number(list[list.length - 1].progression_rank) : 0);

  function nextRung(list, rank) {
    const idx = (list || []).findIndex(ex => Number(ex.progression_rank) === Number(rank));
    return idx >= 0 ? (list[idx + 1] || null) : null;
  }

  const isFinalRung = (list, rank) => !!(list || []).length && Number(rank) >= topRank(list);

  // ---- La marca ----------------------------------------------------------------------------

  // Un escalón se mide en segundos (aguantes) o en repeticiones (elevaciones), y eso lo dice
  // el propio ejercicio del catálogo. No hay un tercer caso: una distancia no es un skill.
  const markUnit = rung => (ht().metricType(rung) === 'time' ? 'time' : 'reps');

  // La marca de una serie registrada. actual_seconds existe desde la migración 117; en series
  // viejas el tiempo quedó escrito en actual_reps ("0:30", "30s"), y parseSeconds lo entiende.
  function setMark(rung, set) {
    if (!rung || !set) return 0;
    if (markUnit(rung) === 'time') {
      if (set.actual_seconds != null && set.actual_seconds !== '') return Math.max(0, Number(set.actual_seconds) || 0);
      return Math.max(0, ht().parseSeconds(set.actual_reps) || 0);
    }
    const reps = Number(String(set.actual_reps == null ? '' : set.actual_reps).replace(/[^\d.]/g, ''));
    return Number.isFinite(reps) ? Math.max(0, reps) : 0;
  }

  // La mejor serie palomeada. Una serie sin palomear no es una marca: es una intención.
  function bestMark(rung, sets) {
    return (sets || []).reduce((best, s) => (s && s.done ? Math.max(best, setMark(rung, s)) : best), 0);
  }

  // ---- La curva ----------------------------------------------------------------------------

  // Lo que hace que una línea de skill sea UNA cosa en la que mejoras por años es que la marca
  // cruda se reinicia en cada escalón: 20 s de tuck se vuelven 6 s de tuck avanzado y la
  // gráfica se lee como un derrumbe. Nivel = escalón + qué tanto llevas DE ese escalón, así
  // que subir cae exactamente en el número donde terminó el anterior y la curva no se rompe.
  // Sale de progression_rank y progression_target, que ya son el estándar: no hay coeficiente
  // de dificultad inventado que haya que mantener honesto.
  function skillLevel(list, rank, mark) {
    const rung = rungAt(list, rank);
    if (!rung) return null;
    const idx = list.findIndex(x => x === rung);
    // El último escalón no tiene objetivo propio: se mide contra el del anterior, que es la
    // marca que hubo que hacer para llegar ahí.
    const target = Number(rung.progression_target) || Number(list[idx - 1] && list[idx - 1].progression_target) || 0;
    if (!target) return Number(rung.progression_rank);
    return Math.round((Number(rung.progression_rank) + Math.min(1, (Number(mark) || 0) / target)) * 100) / 100;
  }

  // Qué tanto llevas del escalón actual, 0 a 1. Es la barra que ve el alumno.
  function rungProgress(list, rank, mark) {
    const level = skillLevel(list, rank, mark);
    if (level == null) return 0;
    return Math.min(1, Math.max(0, level - Number(rank)));
  }

  // ---- El estándar -------------------------------------------------------------------------

  // ¿Ya cumple el estándar de ESTE escalón? progression_target_sets series en el objetivo, en
  // cada una de las dos últimas sesiones donde entrenó este ejercicio. Pedir N series y no la
  // mejor es deliberado (078): una serie con suerte alcanzaba para decirle que subiera a un
  // escalón que no podía repetir. Una sesión donde no lo entrenó se salta; una donde SÍ lo
  // entrenó y no llegó rompe la racha, así que son dos sesiones seguidas, no dos cualquiera.
  //
  // `sessions`: de la más reciente a la más vieja, cada una {id, sets:[...]}. Solo sesiones
  // cerradas y sin la que está en curso — si no, la sesión de hoy a medias rompe la racha.
  //
  // Lo que devuelve es una SUGERENCIA para el coach, nunca un cambio de escalón: aquí no se
  // mide la forma, y la forma es justo lo que decide si un front lever cuenta.
  function readiness(list, rank, sessions) {
    const rung = rungAt(list, rank);
    const needed = Math.max(1, Number(rung && rung.progression_target_sets) || 1);
    const target = Number(rung && rung.progression_target) || 0;
    const out = { ready: false, needed, target, streak: 0, lastQualified: false, final: isFinalRung(list, rank) };
    if (!rung || !target || out.final) return out;
    for (const session of sessions || []) {
      const sets = (session && session.sets) || [];
      if (!sets.some(s => s && s.done)) continue;           // no lo entrenó: no cuenta ni rompe
      const qualifying = sets.filter(s => s && s.done && setMark(rung, s) >= target).length;
      if (out.streak === 0) out.lastQualified = qualifying >= needed;
      if (qualifying < needed) break;                        // lo entrenó y no llegó: rompe
      out.streak += 1;
      if (out.streak >= 2) { out.ready = true; break; }
    }
    return out;
  }

  // ---- Cues --------------------------------------------------------------------------------

  // Las "Indicaciones" de un ejercicio son un solo campo de texto (boards.exercises[].note),
  // y así se han escrito siempre. Partirlas en puntos no cambia el campo: lo que cambia es que
  // 3 cues numerados se pueden señalar por número ("se te fue el 2") y un párrafo no.
  // Una sola línea sigue siendo una sola: no se numera lo que no es lista.
  const CUE_MAX = 6;
  const CUE_LEN = 140;

  function cueList(note) {
    const raw = String(note == null ? '' : note);
    if (!raw.trim()) return [];
    return raw
      .split(/\r?\n|;|\s·\s|\s\|\s/)
      .map(s => s.replace(/^\s*(?:[-*•–—]|\d+[.)])\s*/, '').trim())
      .filter(Boolean)
      .slice(0, CUE_MAX)
      .map(s => (s.length > CUE_LEN ? s.slice(0, CUE_LEN - 1).trimEnd() + '…' : s));
  }

  // ---- La animación ------------------------------------------------------------------------

  // animation_url es un GIF o un MP4 corto en bucle, columna aparte de video_url a propósito
  // (migración 141). Solo hay dos formas de pintarlo y ninguna es un iframe: una animación
  // que hay que tocar para que corra no enseña la posición.
  function animationKind(url) {
    const raw = String(url == null ? '' : url).trim().toLowerCase().split(/[?#]/)[0];
    if (!raw) return null;
    if (/\.(mp4|webm|mov)$/.test(raw)) return 'video';
    if (/\.(gif|webp|png|jpe?g|avif)$/.test(raw)) return 'image';
    return null;
  }

  const api = {
    CUE_MAX, CUE_LEN,
    rungs, rungAt, topRank, nextRung, isFinalRung,
    markUnit, setMark, bestMark,
    skillLevel, rungProgress, readiness,
    cueList, animationKind
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.HabitSkills = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
