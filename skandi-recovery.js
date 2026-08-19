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
const ACTIVITY_MUSCLE_MAP = {
  running:  {Quads:30, Hamstrings:25, Glutes:20, Calves:20, Core:5},
  cycling:  {Quads:45, Hamstrings:15, Glutes:20, Calves:15, Core:5},
  swimming: {Shoulders:30, Back:25, Chest:15, Core:20, Triceps:10},
  rowing:   {Back:35, Shoulders:15, Hamstrings:15, Quads:10, Biceps:10, Core:15},
  walking:  {Quads:25, Hamstrings:20, Glutes:20, Calves:30, Core:5},
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

// Absolute-bpm bands used as a heart rate zone proxy (no personalized max HR on file —
// manual entry only, no device integration) mapped onto the same 1-10 scale as effort-based
// RPE, so a run logged with heart rate feeds the exact same stimulus formula. Distance/pace
// aren't given a separate term: for a fixed duration a harder pace already shows up as a
// higher heart rate, and where duration itself differs that's already in the duration term —
// adding pace on top would double-count the same effort.
function heartRateIntensity(bpm){
  bpm = Number(bpm) || 0;
  if (!bpm) return null;
  if (bpm < 110) return 3;
  if (bpm < 130) return 5;
  if (bpm < 150) return 6.5;
  if (bpm < 170) return 8;
  return 9.5;
}

// One external activity -> stimulus units. Calibrated so 30 min @ RPE 5 == 1.0 SU (~one hard
// set). Heart rate, when logged, replaces the manual RPE as the intensity driver — it's the
// more objective signal of actual cardiovascular effort. Falls back to RPE when no heart rate
// was entered, so older/unlogged activities are unaffected.
function activityStimulusUnits(activity){
  const duration = Number(activity.duration_min) || 0;
  const intensity = heartRateIntensity(activity.avg_heart_rate) ?? (Number(activity.intensity) || 5);
  return (duration * intensity) / 150;
}

// Flatten sets+activities into per-muscle timestamped stimulus events within the lookback window.
function buildStimulusEvents({ sets, sessions, exercises, activities, userId, now }){
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
    const su = activityStimulusUnits(a);
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
function computeMuscleRecovery({ sets, sessions, exercises, activities, userId, now }){
  now = now || Date.now();
  const events = buildStimulusEvents({ sets, sessions, exercises, activities, userId, now });
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
  RECOVERY_LOOKBACK_DAYS, FRESH_THRESHOLD,
  tauHoursForMuscle, setStimulusUnits, activityStimulusUnits, heartRateIntensity,
  buildStimulusEvents, muscleFatigueAt, freshnessScore, hoursUntilFresh,
  computeMuscleRecovery
};

if (typeof module !== 'undefined' && module.exports) module.exports = SkandiRecovery;
else global.SkandiRecovery = SkandiRecovery;

})(typeof window !== 'undefined' ? window : globalThis);
