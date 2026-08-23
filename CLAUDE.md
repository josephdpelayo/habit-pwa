# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HABIT Training Hub — a PWA for a gym in Mazatlán, Mexico. Members book training slots, pay via Stripe, and open the gym door from their phone. The app is deployed on Vercel with Supabase as the backend.

This repo ships **two** front-ends off the same Vercel project and the same Supabase database:

- **HABIT Training Hub** (`app.html`, served at `/`) — the gym: bookings, payments, door access, coaching.
- **Skandi Fit** (`skandi.html`, served at `/skandi`) — a separate training app for the crew of the
  Skandi Nomad (a DOF vessel). Shares `profiles` and `auth.users` with HABIT, and shares two pure JS
  modules (`skandi-recovery.js`, `body-figure.js`), but has its own tables (`skandi_*`), its own
  manifest, and no overlap in UI code. See `docs/PROYECTO_SKANDI_V2.md` for the roadmap in progress.

## Commands

```bash
# Check syntax of all API files and sw.js
npm run check

# Parse every migration against the real PostgreSQL grammar (needs `pip install --user pglast`)
npm run check:sql

# Deploy: push to git → Vercel auto-deploys
```

There is no build step, no bundler, no test suite. `npm run check` runs `node --check` on each API file — it validates syntax only, not runtime behavior. `npm run check:sql` parses `migrations/*.sql` with libpg_query (Postgres' own parser), including plpgsql function bodies — worth running before pasting a migration into the Supabase SQL Editor, where a syntax error leaves you half-applied. It checks syntax, not that the tables or columns exist.

## Architecture

### Frontend (`app.html`)
A single ~5500-line file containing all HTML, CSS, and JavaScript. There is no framework, no bundler, no imports — it's vanilla JS loaded as inline `<script>`. The Supabase JS client is loaded from CDN.

The app has four screens (`#s-auth`, `#s-main`, `#s-admin`, `#s-reception`), toggled by adding/removing the `.active` CSS class. Within `#s-main`, tabs are toggled via `.view.active`. Admin has its own tab system via `admTab()`.

- `index.html` — just redirects to `app.html` with a version query string for cache busting
- `sw.js` — service worker: push notifications + app shell cache. **One registration at scope `/` serves both apps** — two service workers at the root would evict each other, so Skandi registers this same file. Fetch handler: icons and the shared JS modules are cache-first, navigation is network-first (and refreshes the cached shell with what it just fetched), API calls pass through untouched. `shellFor()` picks the offline fallback by path: `/skandi*` → `skandi.html`, everything else → `app.html`.
- `manifest.json` / `skandi-manifest.json` — one PWA manifest per app. Both use `scope: "/"` and are told apart by `id`.

**Version / cache busting**: one version string covers the whole project, because one service worker caches both apps. It lives in `APP_VERSION` (`app.html`), `SKANDI_VERSION` (`skandi.html`) and `CACHE_VERSION` (`sw.js`), plus the `?v=` strings in `index.html`, both manifests' `start_url`, and the `<link>`/`<script>` tags at the top of `app.html` and `skandi.html`. **Changing either app means bumping all of them to the same value** — a stale `CACHE_VERSION` leaves the offline shell frozen at the previous deploy.

### Frontend (`skandi.html`)
Same architecture as `app.html` — a single ~4,500-line vanilla-JS file, Supabase from CDN, no build
step — but a completely separate app with its own navy/ice design system and its own i18n (`t()`,
Spanish/English). Views (`home`, `train`, `crew`, `progress`, `body`, `library`) are swapped by
`setView()`, which re-renders `#screen` from template strings.

Pure logic lives in sibling modules, never inline: `skandi-recovery.js` (per-muscle fatigue decay,
the engine behind the body figure), `body-figure.js` (the 11-region SVG), `skandi-nutrition.js`
(targets, daily totals, portion scaling) and `skandi-strava.js` (one Strava activity → one
`skandi_external_activities` row). All four are DOM-free and Supabase-free so they can be
exercised from Node — keep new engines to that pattern rather than growing `skandi.html`.
`skandi-strava.js` is the odd one out: it is the **only** module the browser never loads (the
server `require`s it and nothing else consumes it), so it is absent from `sw.js`'s `SHELL`.

The `food` view is the nutrition tab. Its ordering rule is load-bearing: the add-meal chooser lists
saved dish and catalog food (free, instant, offline) above photo and text (AI, priced in the label).
Editing an item's grams rescales it by density and upserts the correction into `skandi_foods` —
that's the mechanism that makes the AI progressively unnecessary. Adding it took the tab bar from 6
to 7 columns, which is why the Spanish labels for crew and library were shortened to fit 375px.

### Backend (`api/*.js`)
Vercel serverless functions. Files prefixed with `_` (`_plans.js`, `_fulfillment.js`) are shared modules, not routes.

**Hard ceiling: 12 functions.** The Hobby plan refuses to build a deployment with more than 12
Serverless Functions, and this project sits exactly at 12. One file = one function, so a new
endpoint means folding it into an existing router by `req.body.action` (see `skandi.js`, and
`search-users.js`, which carries `create` / `reception-active` / `email`), not adding a file.
Strava did exactly this: it is six actions inside `skandi.js`, not a `strava.js` of its own — the
file was renamed from `nutrition.js` when it stopped being only about food. When a third party
needs a fixed URL it cannot get by posting an `action` (Strava's OAuth callback and webhook), the
answer is a **rewrite in `vercel.json`** to `/api/skandi?action=…` — a rewrite costs no function.

Key routes:
- `stripe-webhook.js` — receives `checkout.session.completed` from Stripe; calls `activateMembership()` from `_fulfillment.js`
- `create-checkout-session.js` / `confirm-checkout-session.js` — Stripe Checkout flow
- `validate-access-code.js` — physical keypad validation; authenticated with `ACCESS_API_SECRET` bearer token
- `request-door-open.js` — in-app door open button; authenticated with Supabase JWT + GPS proximity check, then triggers Shelly Cloud relay API
- `skandi.js` — Skandi Fit's whole server side behind one function (was `nutrition.js`; the old
  path is kept alive by a rewrite for clients holding a cached HTML). `{action:'analyze'}`: a meal photo
  and/or written description → Claude (vision) with a strict JSON-Schema `output_config.format` →
  `skandi_meal_items`; the photo is pulled from the private bucket with service-role and the daily
  quota is enforced in the DB (`skandi_bump_ai_usage`, migration 074), never in the client. Needs
  `ANTHROPIC_API_KEY`. `{action:'barcode'}`: barcode → Open Food Facts → a `skandi_foods` row, **no
  AI and no quota** — a packaged product ships its own macros. `{action:'meal-suggestion'}`: today's
  remaining macros, today's planned/logged training and the member's saved-dish/food catalog (all
  already computed client-side by `skandi-nutrition.js`, never recomputed server-side — the client
  owns "today" because the boat changes time zones) → Claude (text-only, same JSON-Schema pattern,
  no image) → a cook-to-close-the-day suggestion plus concrete pre/post-workout food examples.
  Shares the same daily quota as `analyze`; nothing it returns is persisted. All three take a
  Supabase JWT.
  Then Strava (migration 081): `strava-connect` returns the authorize URL with an **HMAC-signed
  `state`** — the callback arrives with no session, so the signed state is the only thing saying
  whose `code` it is; `strava-callback` (GET, via rewrite) exchanges it and stores the tokens;
  `strava-webhook` (GET answers `hub.challenge`, POST takes events) **replies 200 before doing the
  work**, because Strava wants an answer in two seconds; `strava-sync` is the manual pull that
  doubles as the webhook's safety net; `strava-disconnect` deauthorizes at Strava then deletes the
  tokens, keeping the already-imported activities (they happened); `strava-subscription` is the
  one-time webhook subscription admin, gated on `profiles.role = 'admin'`.
  Re-importing an activity **never overwrites an `intensity_source = 'manual'` effort** — that is
  why the import is a read-then-split, not a blind upsert
- `search-users.js` — admin user search (service-role Supabase query)
- `sync-stripe-payments.js` — admin-triggered payment sync

Plans (prices, credits, expiry days) are defined centrally in `api/_plans.js` and shared by `_fulfillment.js`, `create-checkout-session.js`, and `confirm-checkout-session.js`.

### Database (Supabase)
Schema is in `habit-supabase-setup.sql`. Additional migrations are separate `.sql` files that must be run manually in the Supabase SQL Editor.

Core tables:
- `profiles` — extends `auth.users`; has `role` (`user`/`admin`/`reception`), 4-digit `access_code`, `credits`, `plan_id`, `plan_expiry`
- `bookings` — reservations; `ds` = date (`YYYY-MM-DD`), `start_idx` = slot index 0–47 (each slot = 30 min), `slots_used` = 2 or 3
- `slot_occupancy` — one row per booked slot per user per day
- `slot_blocks` — admin-created manual blocks
- `payments` — payment records (Stripe and manual)
- `door_commands` — queue of door open requests with Shelly execution status
- `access_log` — history of door access events
- `boards` / `board_assignments` / `scores` — workout boards feature. A board with `owner_id` null
  is a gym/coach board; with `owner_id` set it's a member-built routine (migration 070), and the
  `SELECT` policy is `owner_id is null or owner_id = auth.uid()`. Member routines always carry
  `MEMBER_ROUTINE_COLOR`; the color is what tells a member's routine apart from the coach's, so
  it is not theirs to pick and `routineColor()` resolves it at render time
**Entrenar vs Coaching.** The `rutinas` view (labelled "Entrenar") owns everything about
training and is open to every member: today's session, the weekly grid, the member's routines,
the muscle-fatigue body and the Progreso screen. The `coaching` view is only for David's clients
(`profiles.coaching_beta`) and owns only what the coach relationship adds: chat, habits, fasting,
adherence and the post-workout feedback he reads. Nothing is rendered in both — Coaching links
into Entrenar instead. `coaching_week_templates.created_by` says who set each weekday, which is
what lets Entrenar mark a day as "de tu coach" and the coach's panel mark one as set by the
member; both sides rewrite the whole week on save, so that marking is the only thing preventing
a silent overwrite.

- `coaching_week_templates` / `coaching_programs` / `coaching_program_days` — the member's weekly
  plan (`dow` 0 = Monday) and named programs that overwrite it. Activating a program rewrites
  every `coaching_week_templates` row, then re-materializes the week via the
  `ensure_coaching_week_from_template` RPC
- `coaching_schedule.session_exercises` — JSONB overlay of exercises swapped in or added during a
  live session. `boards.exercises` is never mutated by a workout; `sessionExerciseList()` in
  `app.html` merges the two and is the single source of the effective exercise list
- `exercise_catalog` — the only place a member can pick an exercise from. Migration 071 imported
  Skandi Fit's `skandi_exercises` into it (names translated to Spanish, English name kept as an
  alias); its `video_url` values are GIFs and MP4s, not embeds, so `mediaKind()` in `app.html`
  decides between `<img>`, `<video>` and an iframe
- `posts` / `post_reactions` / `post_comments` — community feed
- `booking_guest_passes` — group session guest passes (from `group-guest-passes.sql`)
- `admin_notifs` — in-app notifications for admin

**Skandi Fit tables** (all prefixed `skandi_`, migrations 040–073). They share `profiles` with HABIT
and nothing else:
- `skandi_exercises` — Skandi's own exercise catalog, separate from HABIT's `exercise_catalog`.
  `muscles` is a jsonb split (`{"Chest":60,"Triceps":25}`) summing to ~100, in the recovery engine's
  muscle names — that split is what `skandi-recovery.js` consumes
- `skandi_templates` / `skandi_template_items` — routines; `weekday` is the single source of truth
  for "my week" (`skandi_programs` / `skandi_program_days` just re-stamp it, migration 069)
- `skandi_sessions` / `skandi_sets` — logged workouts, with `rir` per set and `report_*` recovery
  fields on the session (064)
- `skandi_external_activities` / `skandi_activity_templates` — cardio: running, cycling, swimming,
  rowing, walking; manual entry with RPE, heart rate and target zone (046, 063), plus Strava
  import (081). `external_source` + `external_id` carry a **plain unique index, not a partial
  one** — a partial index cannot arbitrate an `ON CONFLICT` that does not repeat its predicate,
  which PostgREST never emits, and NULLs are distinct so hand-logged rows never collide.
  `external_type` keeps Strava's raw `sport_type` because `activity_type` reduces ~50 sports to
  six (that reduction exists only to pick a muscle map). `intensity_source` says where the effort
  number came from — `default` means nobody measured it and the row is badged for review.
  046's `duration_min <= 600` / `distance_km <= 500` were raised to 1440 / 1000: on a form those
  ceilings catch typos, on an import they silently drop a real activity
- `skandi_training_blocks` (N build weeks + deload, 066), `skandi_bodyweight_logs` (067),
  `skandi_progression_state` (calisthenics progressions)
- `skandi_body_measurements` / `skandi_progress_photos` (090) — tape and photo tracking, added
  because a normal scale is not reliable aboard a moving boat; a tape measure and a camera are.
  Measurements are one row per day (`unique(user_id, measured_at)`, upserted, all seven cm
  columns optional but a DB trigger requires at least one); photos allow several per day (front/
  side/back is normal) so carry no such uniqueness. Photos live in the private
  `skandi-progress-photos` bucket, same per-user-folder RLS as `skandi-meals` (073) and
  `skandi-set-clips` (079). Body tab gained sub-tabs (Recovery/Measurements/Photos,
  `state.bodyTab`) to hold this without crowding the muscle-recovery figure that was already there
- Strava (081): `skandi_integrations` holds the OAuth tokens and has **RLS on with zero
  policies** — that denies every client read, which is the point; only the service-role in
  `api/skandi.js` touches it, and the app asks the `skandi_strava_status()` definer RPC for the
  handful of facts it may know. A partial unique index on `(provider, athlete_id)` forbids two
  members claiming one Strava athlete, because the webhook identifies the owner by `athlete_id`
  alone and ambiguity there has no safe resolution. `skandi_settings.max_heart_rate` is what
  turns bpm into comparable effort; it lives in its own private table and **not on `profiles`,
  which every authenticated gym member can read** (migration 007). With it unset,
  `SkandiRecovery.heartRateIntensity()` falls back to absolute bpm bands — the same numbers as
  before, since those bands were the `HR_MAX_REFERENCE = 190` case all along. Strength sessions
  logged in Strava (`WeightTraining`, `Crossfit`) are deliberately **not** imported: Skandi
  already has them as `skandi_sessions`, and importing would fatigue the same muscle twice
- Skill lines (078): `progression_group` + `progression_rank` order a ladder, and levelling up
  is a **standard, not a best set** — `progression_target_sets` sets at `progression_target`,
  each rated `form_quality` >= 8, in two consecutive sessions that trained that rank.
  `progression_criteria` is the one-line form standard for that rung and is shown on the card
  during the workout, because "clean" means something different on a tuck than on a straddle.
  `skandi_sets.form_quality` (1–10) replaces the tri-state `hold_clean` (065), which is never
  written any more but is still read as a fallback for older sets (`setQuality()` in
  `skandi.html`: clean → 8, broken → 4, untagged → null). Quality replaces the RIR column for
  any exercise with `track_quality` — a nordic curl or a front lever raise is taken to where
  form breaks, not to RIR 2
- Skill depth (079). A skill line's progress is **one curve, not one per rank**: `skillLevel()`
  = `progression_rank + min(1, mark / progression_target)`, so levelling up lands on exactly the
  number the previous rank ended at. It is derived, not stored — there is no difficulty
  coefficient column to keep honest. `skandi_progression_events` is the memory
  `skandi_progression_state` never had (it holds only the current rank), and is seeded by
  reconstructing when each variant first appears in a completed session. `skandi_skill_goals`
  holds a weekly time-under-tension target per line, where TUT = logged seconds + reps ×
  `REP_TUT_SEC` (3) — in statics the volume is seconds, not sets. `skandi_sets.side` splits
  unilateral work (`skandi_exercises.unilateral`; sides are pre-alternated at set creation) and
  `clip_path` points into the **private** `skandi-set-clips` bucket, one folder per uid — unlike
  the shared public `skandi-exercise-media` (058), a set clip is the member's own
- `skandi_foods` / `skandi_meals` / `skandi_meal_items` / `skandi_nutrition_targets` /
  `skandi_ai_usage` — nutrition (073, 074, 075). Meal macros are stored **absolute** per row, meal
  totals are maintained by a trigger (never by the app), and meals are strictly private — no crew
  visibility, and the `skandi-meals` storage bucket is private, unlike the public
  `skandi-exercise-media` (058). A meal is registered four ways (`input_kind`): photo, free text,
  barcode, or manual. Cooking fat is never folded into a dish — the model returns it as its own
  `is_cooking_fat` row, and `skandi_meals.venue` (casa/restaurante/fonda) decides both how much it
  estimates and whether that row arrives checked. Unchecking sets `included = false`, which drops
  it from the trigger's sum without destroying it
- `skandi_dishes` / `skandi_dish_items` — saved dishes (076). **The cost ladder for logging a meal
  is: saved dish → catalog food → AI.** A dish is snapshotted from an already-corrected meal
  (`skandi_save_meal_as_dish`), so it carries the user's fixes, not the model's guess; logging it
  again is `skandi_create_meal_from_dish` with a scale factor — zero tokens, works offline.
  `skandi_add_food_to_meal` covers "180 g of chicken", which is a multiplication, not a vision
  problem. The `skandi_quick_picks` view is what the UI should show before ever opening the camera.
  Deliberately, saved dishes are NOT sent to the model: the saving is in not calling it
- Sugar (077) is tracked as its own macro across all five tables, but it is a **ceiling, not a
  goal** — the UI turns it red on excess and a null `sugar_g_target` means "don't track it". Its
  kcal already live inside `carbs_g`; never add it to the calorie total
- Added sugar (089): `sugar_g` is total sugar (fruit included), `added_sugar_g` is the part a
  person or a process added — the WHO's actual target, and what `added_sugar_g_target` caps.
  Every client write outside the jsonb-based RPCs (`updateItemGrams`, `rememberFood`,
  `saveTargets` in skandi.html) tolerates the columns being absent and retries without them,
  because this migration can be live in the repo before it's run in Supabase and a raw
  insert/update to a column that doesn't exist yet fails the whole write, not just that field
- `SkandiNutrition.dayRecommendation()` adjusts today's target by the **difference between today's
  planned training burn and the weekly average**, never by the whole burn — the target's activity
  factor already assumes training, so adding the day's burn on top double-counts. The delta goes to
  carbs only. `plannedSessions()` + `fuelPlan()` turn that delta into timed advice (carbs before,
  during only for endurance over 75 min, carbs+protein after). A short easy session deliberately
  gets no pre-load — inventing one just pushes the member to eat more

### Time & Slots
All time logic uses **America/Mazatlan (UTC−7)**. The constant `MAZ_UTC_OFFSET_H = 7` converts UTC midnight to Mazatlán midnight. A day has 48 slots of 30 minutes. A typical booking is `slots_used = 3` (90 min). Access windows open 10 minutes before a booking's `start_idx`.

### Door Access: Two Paths
1. **Physical keypad** → `POST /api/validate-access-code` with `Authorization: Bearer ACCESS_API_SECRET`
2. **In-app button** → `POST /api/request-door-open` with Supabase JWT + GPS coords → Shelly Cloud API

### Native (Capacitor)
`capacitor.config.json` targets `app.habittraininghub.app`. The `ios/` and `www/` directories contain the Capacitor build output. The `www/` dir is generated from `app.html` — do not edit it directly.

### Environment Variables (Vercel)
```
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
STRIPE_SECRET_KEY
STRIPE_WEBHOOK_SECRET
ACCESS_API_SECRET        # shared secret for keypad controller
GYM_LAT / GYM_LNG       # GPS coordinates of gym
GYM_RADIUS_METERS        # default 120
GYM_MAX_ACCURACY_METERS  # default 150
SHELLY_SERVER_URL        # e.g. https://shelly-247-eu.shelly.cloud
SHELLY_AUTH_KEY
SHELLY_DEVICE_ID
SHELLY_CHANNEL           # default 0
SHELLY_TURN              # 'off' releases the magnetic lock
PUBLIC_APP_URL
ANTHROPIC_API_KEY        # Skandi Fit meal analysis (api/skandi.js)
MEAL_AI_DAILY_LIMIT      # default 25 analyses per user per day
MEAL_AI_MODEL            # default claude-opus-5
STRAVA_CLIENT_ID         # strava.com/settings/api
STRAVA_CLIENT_SECRET
STRAVA_WEBHOOK_VERIFY_TOKEN  # any long random string; Strava echoes it back on subscribe
```

Strava's app settings need `Authorization Callback Domain` set to the bare host of
`PUBLIC_APP_URL` (`habittraininghub.app`, no scheme, no path) or the OAuth redirect is rejected.

`LOCATION_EXEMPT_EMAILS` in `request-door-open.js` lists emails that bypass GPS checks.

### SQL Migrations
All migrations live in `migrations/` with numeric prefixes (`001_schema.sql` … `083_skandi_garmin_strength.sql`). Run them in order in the Supabase SQL Editor. New migrations follow the same naming convention. The API handlers detect missing tables and return descriptive error messages pointing to the required migration.
