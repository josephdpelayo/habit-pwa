// HABIT Skills — escaleras de calistenia: la curva de progreso, el estándar y los cues.
//
// Módulo puro: sin DOM y sin Supabase, igual que skandi-recovery.js, para poder ejercitarlo
// desde Node (scripts/check-skills.js). Trae a HABIT el motor de las migraciones 078/079 de
// Skandi, con una diferencia que no es un detalle: **aquí nada sube de escalón solo.**
// readiness() dice "ya cumple el estándar" y decide una persona: el coach, porque la forma
// de un front lever la juzga quien ve el video (migración 141), o el propio alumno cuando
// entrena sin coach y la línea la eligió él (migración 144, rungOwner()).
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

  // ---- Quién mueve el escalón --------------------------------------------------------------

  // Migración 144: una fila de coach_student_skills es del alumno si la puso él
  // (set_by = user_id) y de su coach si la puso otra persona. Sin fila, la línea está libre y
  // el alumno elige dónde empieza. Un set_by en null (se borró la cuenta del coach) cuenta como
  // del coach, igual que en la RLS: de solo lectura, porque no se sabe quién la decidió.
  function rungOwner(row) {
    if (!row) return 'none';
    return row.set_by && row.set_by === row.user_id ? 'self' : 'coach';
  }

  // ---- Entrenar un escalón -----------------------------------------------------------------

  // Lo que entra en la hoja al tocar «Entrenar este escalón»: el estándar del escalón como
  // objetivo de cada serie, para que cumplirlo en la hoja sea exactamente lo que readiness()
  // cuenta. Al menos RUNG_MIN_SETS series, porque el estándar de algunos escalones es una sola
  // (45 s de colgado invertido) y un entreno de una serie no es práctica. El descanso es el de
  // trabajo de skill, más largo que los 90 s de la hoja: un aguante al límite pide recuperar.
  const RUNG_MIN_SETS = 3;
  const RUNG_REST_SEC = 120;

  function rungWorkout(list, rank) {
    const rung = rungAt(list, rank);
    if (!rung) return null;
    const idx = list.indexOf(rung);
    const unit = markUnit(rung);
    // El último escalón no tiene objetivo propio: hereda el del anterior, como en skillLevel().
    const target = Number(rung.progression_target)
      || Number(list[idx - 1] && list[idx - 1].progression_target)
      || (unit === 'time' ? 10 : 5);
    const plan = {
      sets: String(Math.max(RUNG_MIN_SETS, Number(rung.progression_target_sets) || 1)),
      reps: unit === 'time' ? target + 's' : String(target),
      rest: RUNG_REST_SEC + 's'
    };
    if (unit === 'time') plan.repsType = 'time';
    return plan;
  }

  // Un ejercicio agregado en vivo desde el catálogo guarda sus series con ex_key "cat-<slug>"
  // (y "#2", "#3" si se repite en la misma sesión; wsUniqueExKey en crew.html). Esa llave es
  // estable entre sesiones, así que también es el puente entre una serie y su escalón cuando
  // el ejercicio no viene de una rutina guardada, que es justo el caso de quien entrena el
  // escalón desde la escalera.
  function catalogSlugFromExKey(exKey) {
    const m = String(exKey == null ? '' : exKey).match(/^cat-(.+?)(?:#\d+)?$/);
    return m ? m[1] : null;
  }

  // ---- ¿Cumplió el estándar en esta sesión? --------------------------------------------------

  // Las series de UNA sesión contra el estándar de un escalón: progression_target_sets series
  // en el objetivo. Es la prueba de fase de un programa (docs/PROGRAMA_HANDSTAND.md §5), que se
  // mide en un solo sábado; readiness() en cambio pide dos sesiones seguidas para subir.
  function meetsStandard(rung, sets) {
    const target = Number(rung && rung.progression_target) || 0;
    const needed = Math.max(1, Number(rung && rung.progression_target_sets) || 1);
    const qualifying = target
      ? (sets || []).filter(s => s && s.done && setMark(rung, s) >= target).length
      : 0;
    return { passed: !!target && qualifying >= needed, qualifying, needed, target,
             best: bestMark(rung, sets) };
  }

  // ---- Programas por fases (handstand-8, migración 145) --------------------------------------

  // Lo que la app necesita saber del programa para pintarlo y decidir; las rutinas, los días y
  // las semanas viven en la base. `rank` es el escalón de la escalera que mide la prueba de
  // cada fase: la fase termina cuando se cumple ese estándar.
  const HANDSTAND_PROGRAM = {
    key: 'handstand-8', group: 'handstand', weeks: 8, weeksPerPhase: 2, minutes: 20, days: 6,
    phases: [
      { n: 1, rank: 1, es: 'Base', en: 'Base' },
      { n: 2, rank: 3, es: 'Línea en pared', en: 'Wall line' },
      { n: 3, rank: 4, es: 'Equilibrio', en: 'Balance' },
      { n: 4, rank: 5, es: 'Libre', en: 'Freestanding' }
    ]
  };

  // La fase de una semana del ciclo (1..weeks), o null fuera del ciclo (0 = no empezó,
  // -1 = terminó, como coaching_program_week_index en SQL).
  function programPhase(program, weekIndex) {
    const w = Number(weekIndex);
    if (!program || !(w >= 1) || w > program.weeks) return null;
    return program.phases[Math.ceil(w / program.weeksPerPhase) - 1] || null;
  }

  // La segunda semana de cada fase termina en la prueba (su sábado).
  function isPhaseTestWeek(program, weekIndex) {
    return !!programPhase(program, weekIndex) && Number(weekIndex) % program.weeksPerPhase === 0;
  }

  // Por dónde entra alguien que ya está en el escalón `rank` de la escalera: la primera fase
  // cuya prueba es ese escalón o uno más arriba. Escalón 1 → fase 1; 2–3 → fase 2 (su prueba es
  // el 3); 4 → fase 3; 5 o más → fase 4. Devuelve la primera semana de esa fase.
  function placementWeek(program, rank) {
    const r = Math.max(1, Number(rank) || 1);
    const phase = program.phases.find(p => p.rank >= r) || program.phases[program.phases.length - 1];
    return (phase.n - 1) * program.weeksPerPhase + 1;
  }

  // Fechas ISO (YYYY-MM-DD) en UTC, sin horas: un día es un día en cualquier zona.
  function addDaysIso(iso, days) {
    const d = new Date(String(iso).slice(0, 10) + 'T00:00:00Z');
    d.setUTCDate(d.getUTCDate() + Number(days || 0));
    return d.toISOString().slice(0, 10);
  }

  // start_date tal que el lunes `firstMonday` sea la semana `startWeek` del ciclo: entrar en la
  // fase 3 es un programa que «empezó» cuatro semanas antes. Así no hace falta otro motor: el
  // calendario ya se estampa desde start_date (115).
  function programStartDate(firstMonday, startWeek) {
    return addDaysIso(firstMonday, -7 * (Math.max(1, Number(startWeek) || 1) - 1));
  }

  // Repetir la fase: la fecha de inicio se corre lo que dura una fase, y las semanas que siguen
  // vuelven a ser de la fase que se está terminando.
  function repeatPhaseStartDate(program, startDate) {
    return addDaysIso(startDate, 7 * program.weeksPerPhase);
  }

  // ---- Cuánto dura una sesión ---------------------------------------------------------------

  // Trabajo + descanso de cada serie. Un 'max' se cuenta como MAX_HOLD_SEC (aguante) o
  // MAX_REPS repeticiones, y una repetición como REP_SEC: es lo que permite probar que las
  // rutinas de 20 minutos de verdad caben en 20 minutos.
  const MAX_HOLD_SEC = 40, MAX_REPS = 10, REP_SEC = 3;

  function exerciseSeconds(ex) {
    const sets = Math.max(1, parseInt(ex && ex.sets, 10) || 1);
    const reps = String(ex && ex.reps == null ? '' : ex.reps).trim().toLowerCase();
    const timed = String(ex && ex.repsType || '').toLowerCase() === 'time' || ht().metricType(ex) === 'time';
    const isMax = /^(max|máx|fallo)$/.test(reps);
    const work = timed
      ? (isMax ? MAX_HOLD_SEC : (ht().parseSeconds(reps) || 0))
      : (isMax ? MAX_REPS : (parseInt(reps, 10) || 0)) * REP_SEC;
    const rest = ht().parseSeconds(String(ex && ex.rest || '').replace(/\s+/g, '')) || 0;
    return sets * (work + rest);
  }

  function sessionSeconds(exercises) {
    return (exercises || []).reduce((n, ex) => n + exerciseSeconds(ex), 0);
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
    // El SVG animado cuenta como imagen: dentro de un <img> corre su propia animación
    // (SMIL o CSS) sin JavaScript, pesa unos kilobytes y se ve nítido a 58 px igual que a
    // 1080. Es con lo que nacen las escaleras antes de que haya video real de cada escalón.
    if (/\.(gif|webp|png|jpe?g|avif|svg)$/.test(raw)) return 'image';
    return null;
  }

  const api = {
    CUE_MAX, CUE_LEN, RUNG_MIN_SETS, RUNG_REST_SEC,
    rungs, rungAt, topRank, nextRung, isFinalRung,
    markUnit, setMark, bestMark,
    skillLevel, rungProgress, readiness,
    rungOwner, rungWorkout, catalogSlugFromExKey, meetsStandard,
    HANDSTAND_PROGRAM, programPhase, isPhaseTestWeek, placementWeek,
    addDaysIso, programStartDate, repeatPhaseStartDate,
    MAX_HOLD_SEC, MAX_REPS, REP_SEC, exerciseSeconds, sessionSeconds,
    cueList, animationKind
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.HabitSkills = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
