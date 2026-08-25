// Skandi Fit muscle recovery engine.
//
// Pure math, no DOM/Supabase coupling, so it can be reasoned about and tested in
// isolation from the UI: `node -e "const R=require('./skandi-recovery.js'); ..."`.
//
// Model: every lifting set or external activity contributes a "stimulus" to the
// muscles it works. That stimulus decays exponentially per muscle, using a time
// constant derived from that muscle's base recovery window (bigger muscle groups
// recover slower). Freshness is a 0-100 display score derived from current fatigue;
// hours-until-fresh is the analytic inverse of the same decay, i.e. a literal ETA.
(function(global){
'use strict';

// ---- Per-muscle base recovery windows (hours), sports-science defaults ----
const MUSCLE_RECOVERY_HOURS = {
  Chest:72, Back:72, Quads:72, Hamstrings:72, Glutes:72,
  Shoulders:48, Core:48,
  Biceps:36, Triceps:36, Forearms:36, Calves:36
};
const RECOVERY_MUSCLES = Object.keys(MUSCLE_RECOVERY_HOURS);

// ---- Tunable constants ----
const RECOVERY_EPSILON = 0.05;      // a single stimulus is "spent" (5% left) at its base-window hour mark
const RECOVERY_LOOKBACK_DAYS = 10;  // >> 5*max(tau) so older events decay to negligible before the window edge
const SET_WORK_REFERENCE = 500;     // kg*reps defining "one hard working set" = 1.0 stimulus unit (SU)
const BODYWEIGHT_KG_PROXY = 70;     // used when weight_kg is null (bodyweight/isometric movement)
const FRESHNESS_K = 1;              // steepness of fatigue -> freshness mapping
const FRESH_THRESHOLD = 70;         // freshness score >= this = "rested"

// ---- External activity -> muscle % split ----
// hiit/hyrox get their own split instead of falling into `other`: a Hyrox class is
// leg-dominant with real back/shoulder carry work (sled, farmer's carry), and lumping it into
// other's Core/Shoulders/Quads/Chest split understates exactly the muscles that take 72h to
// recover from the eccentric loading (sled pulls, lunges). HIIT skews lighter on legs and
// heavier on core/shoulders because bodyweight circuits (burpees, mountain climbers) dominate
// over loaded carries.
const ACTIVITY_MUSCLE_MAP = {
  running:  {Quads:30, Hamstrings:25, Glutes:20, Calves:20, Core:5},
  cycling:  {Quads:45, Hamstrings:15, Glutes:20, Calves:15, Core:5},
  swimming: {Shoulders:30, Back:25, Chest:15, Core:20, Triceps:10},
  rowing:   {Back:35, Shoulders:15, Hamstrings:15, Quads:10, Biceps:10, Core:15},
  walking:  {Quads:25, Hamstrings:20, Glutes:20, Calves:30, Core:5},
  hiit:     {Core:25, Shoulders:20, Quads:20, Glutes:15, Hamstrings:10, Chest:10},
  hyrox:    {Quads:25, Glutes:20, Back:20, Shoulders:15, Hamstrings:10, Core:10},
  other:    {Core:40, Shoulders:20, Quads:20, Chest:20}
};

// ---- Core math ----

// tau_m: decay time constant s.t. exp(-H_m/tau_m) = RECOVERY_EPSILON  =>  tau_m = H_m / ln(1/epsilon)
function tauHoursForMuscle(name){
  const H = MUSCLE_RECOVERY_HOURS[name] || 48;
  return H / -Math.log(RECOVERY_EPSILON);
}

// One lifting set -> stimulus units (SU).
function setStimulusUnits(set){
  if (!set.done) return 0;
  const weight = Number(set.weight_kg) || 0;
  const reps = Number(set.reps) || 0;
  const seconds = Number(set.seconds) || 0;
  const load = weight > 0 ? weight : BODYWEIGHT_KG_PROXY;
  const repsEquivalent = reps > 0 ? reps : Math.max(1, seconds / 30);
  return (load * repsEquivalent) / SET_WORK_REFERENCE;
}

// Heart rate mapped onto the same 1-10 scale as effort-based RPE, so a run logged with heart
// rate feeds the exact same stimulus formula. Distance/pace aren't given a separate term: for
// a fixed duration a harder pace already shows up as a higher heart rate, and where duration
// itself differs that's already in the duration term — adding pace on top would double-count
// the same effort.
//
// The bands are relative, not absolute: 130 bpm is a jog for one person and near-maximal for
// another, so what matters is the fraction of that athlete's own max. HR_BANDS keeps the
// original absolute edges, and HR_MAX_REFERENCE is the max HR they implied — dividing one by
// the other turns them into percentages. With no max HR on file (skandi_settings.max_heart_rate,
// migration 081) the reference is used as-is, which reproduces the old absolute behaviour
// exactly, so no existing activity's stimulus moves until the member fills the field in.
const HR_BANDS = [[110, 3], [130, 5], [150, 6.5], [170, 8]];
const HR_TOP_INTENSITY = 9.5;
const HR_MAX_REFERENCE = 190;

// Intensidad 1-10 por zona, de Z1 a Z5. Son los mismos números que ya usaban las bandas
// relativas, así que estrenar las zonas del reloj no reescribe la historia por capricho:
// solo corrige dónde caen las fronteras.
const ZONE_INTENSITY = [3, 5, 6.5, 8, 9.5];

// zoneBounds = pisos de Z2, Z3, Z4 y Z5 en ppm (migración 087), copiados del reloj. Cuando
// existen mandan sobre el porcentaje de FC máxima: vienen de una prueba de umbral, no de una
// fórmula, y la diferencia no es cosmética — con FCmáx 193 las bandas relativas metían un
// rodaje suave de 140-150 ppm en la misma casilla que 160.
function zoneOf(bpm, zoneBounds){
  if (!Array.isArray(zoneBounds) || zoneBounds.length !== 4) return null;
  const b = zoneBounds.map(Number);
  if (!b.every(n => Number.isFinite(n) && n > 0)) return null;
  for (let i = 0; i < 4; i++) if (bpm < b[i]) return i + 1;   // Z1..Z4
  return 5;
}

function heartRateIntensity(bpm, maxHeartRate, zoneBounds){
  bpm = Number(bpm) || 0;
  if (!bpm) return null;
  const zone = zoneOf(bpm, zoneBounds);
  if (zone) return ZONE_INTENSITY[zone - 1];
  const max = Number(maxHeartRate);
  const reference = max >= 120 && max <= 230 ? max : HR_MAX_REFERENCE;
  const pct = bpm / reference;
  for (let i = 0; i < HR_BANDS.length; i++) {
    if (pct < HR_BANDS[i][0] / HR_MAX_REFERENCE) return HR_BANDS[i][1];
  }
  return HR_TOP_INTENSITY;
}

// One external activity -> stimulus units. Calibrated so 30 min @ RPE 5 == 1.0 SU (~one hard
// set).
//
// Precedence: an effort the athlete actually DECLARED (intensity_source 'manual') wins over
// heart rate. Average heart rate used to win, and it is the wrong arbiter for the sessions
// that matter most here: in an interval workout the average is dragged down by the
// recoveries, so 45 min containing 15 min of Z4 scores the same as a steady easy hour. Heart
// rate also measures cardiovascular strain, not muscle damage — a downhill trail run wrecks
// quads at a moderate pulse, and swimming at 160 bpm barely touches legs. What it beats is a
// number nobody stood behind, which is why the declaration has to be a real one:
// intensity_source distinguishes a typed effort from the form's pre-filled 5 (migration 084).
//
// Heart rate is still derived live rather than read from the stored column, so correcting
// max_heart_rate repaints every past activity instead of freezing yesterday's estimate.
function activityStimulusUnits(activity, maxHeartRate, zoneBounds){
  const duration = Number(activity.duration_min) || 0;
  const declared = activity.intensity_source === 'manual' ? Number(activity.intensity) : NaN;
  const intensity = (declared >= 1 && declared <= 10)
    ? declared
    : (heartRateIntensity(activity.avg_heart_rate, maxHeartRate, zoneBounds) ?? (Number(activity.intensity) || 5));
  return (duration * intensity) / 150;
}

// Flatten sets+activities into per-muscle timestamped stimulus events within the lookback window.
function buildStimulusEvents({ sets, sessions, exercises, activities, userId, now, maxHeartRate, hrZones }){
  const sessionById = new Map((sessions||[]).map(s => [s.id, s]));
  const exerciseById = new Map((exercises||[]).map(e => [e.id, e]));
  const since = now - RECOVERY_LOOKBACK_DAYS * 864e5;
  const events = [];

  (sets||[]).forEach(s => {
    if (!s.done || (userId && s.user_id !== userId)) return;
    const session = sessionById.get(s.session_id);
    const t = new Date(session && session.completed_at || s.created_at).getTime();
    if (!t || t < since || t > now) return;
    const ex = exerciseById.get(s.exercise_id);
    if (!ex) return;
    const su = setStimulusUnits(s);
    if (!su) return;
    Object.entries(ex.muscles || {}).forEach(([muscle, pct]) => {
      if (!MUSCLE_RECOVERY_HOURS[muscle]) return; // ignore unrecognized muscle keys
      events.push({ t, muscle, su: su * (Number(pct) || 0) / 100 });
    });
  });

  (activities||[]).forEach(a => {
    if (userId && a.user_id !== userId) return;
    const t = new Date(a.performed_at).getTime();
    if (!t || t < since || t > now) return;
    const su = activityStimulusUnits(a, maxHeartRate, hrZones);
    const map = ACTIVITY_MUSCLE_MAP[a.activity_type] || ACTIVITY_MUSCLE_MAP.other;
    Object.entries(map).forEach(([muscle, pct]) => {
      events.push({ t, muscle, su: su * pct / 100 });
    });
  });

  return events;
}

// Fatigue-at-time-t, stacking every past event with exponential decay:
//   F_m(t) = sum_i [ su_i * exp( -(t - t_i) / tau_m ) ]
function muscleFatigueAt(events, t){
  const F = new Map(RECOVERY_MUSCLES.map(m => [m, 0]));
  events.forEach(ev => {
    const tauMs = tauHoursForMuscle(ev.muscle) * 3600e3;
    const decay = Math.exp(-(t - ev.t) / tauMs);
    if (decay > 0) F.set(ev.muscle, (F.get(ev.muscle) || 0) + ev.su * decay);
  });
  return F;
}

// 0-100 freshness score from fatigue: freshness = 100 * exp(-k * F)
function freshnessScore(fatigue){
  return Math.max(0, Math.min(100, 100 * Math.exp(-FRESHNESS_K * fatigue)));
}

// Inversion: every contribution to a given muscle shares the same tau_m, so the whole
// stacked sum decays forward from "now" as a single exponential:
//   F_m(t) = F_m(now) * exp( -(t-now) / tau_m )   for t >= now
// Solve for hours-until-fresh (freshness crosses FRESH_THRESHOLD, i.e. F falls to F_crit):
//   F_crit = -ln(FRESH_THRESHOLD/100) / k
//   dt = tau_m * ln( F_m(now) / F_crit )     (0 if already <= F_crit)
function hoursUntilFresh(fatigueNow, muscleName){
  const Fcrit = -Math.log(FRESH_THRESHOLD / 100) / FRESHNESS_K;
  if (fatigueNow <= Fcrit) return 0;
  const tau = tauHoursForMuscle(muscleName);
  return tau * Math.log(fatigueNow / Fcrit);
}

// Public entry point: returns rows sorted ascending by score (least-fresh/most-fatigued first).
function computeMuscleRecovery({ sets, sessions, exercises, activities, userId, now, maxHeartRate, hrZones }){
  now = now || Date.now();
  const events = buildStimulusEvents({ sets, sessions, exercises, activities, userId, now, maxHeartRate, hrZones });
  const F = muscleFatigueAt(events, now);
  return RECOVERY_MUSCLES.map(name => {
    const f = F.get(name) || 0;
    const score = Math.round(freshnessScore(f));
    return {
      name,
      fatigue: f,
      score,
      hoursUntilFresh: Math.round(hoursUntilFresh(f, name) * 10) / 10,
      rested: score >= FRESH_THRESHOLD
    };
  }).sort((a, b) => a.score - b.score);
}

const SkandiRecovery = {
  MUSCLE_RECOVERY_HOURS, RECOVERY_MUSCLES, ACTIVITY_MUSCLE_MAP,
  RECOVERY_LOOKBACK_DAYS, FRESH_THRESHOLD, HR_MAX_REFERENCE,
  tauHoursForMuscle, setStimulusUnits, activityStimulusUnits, heartRateIntensity, zoneOf, ZONE_INTENSITY,
  buildStimulusEvents, muscleFatigueAt, freshnessScore, hoursUntilFresh,
  computeMuscleRecovery
};

if (typeof module !== 'undefined' && module.exports) module.exports = SkandiRecovery;
else global.SkandiRecovery = SkandiRecovery;

})(typeof window !== 'undefined' ? window : globalThis);
