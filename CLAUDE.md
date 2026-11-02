# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HABIT Training Hub — a PWA for a gym in Mazatlán, Mexico. Members book training slots, pay via Stripe, and open the gym door from their phone. The app is deployed on Vercel with Supabase as the backend.

## Requisito permanente: español e inglés

Joseph confirmó el 1 de noviembre de 2026 que HABIT y HABIT Crew deben poder usarse en
**español e inglés**. Es un requisito del producto, no una función opcional. Incluye pantallas,
botones, mensajes, notificaciones, información de entrenamiento y textos de los stickers.
La implementación global sigue pendiente: no anunciar que ya existe un selector de idioma.
Preparar los textos nuevos para ambas traducciones y evitar nuevas dependencias de español
fijo. La solución deberá permitir elegir ES/EN, recordar la elección y localizar fechas y
números. Los nombres de marca y el contenido escrito por cada usuario conservan su identidad.
Este requisito sustituye las notas antiguas que trataban el inglés como opcional o decían
que HABIT no necesitaba un sistema de idiomas.

This repo ships **two** front-ends off the same Vercel project and the same Supabase database:

- **HABIT Training Hub** (`app.html`, served at `/`) — the gym: bookings, payments, door access, coaching.
- **HABIT Crew** (`crew.html`, served at `/crew` by `cleanUrls`) — training and the community, open
  to anyone. **Since 31 oct 2026 it is its own file.** Until then Crew was `app.html` itself,
  rewritten to `/crew`; that day every UX change landed in both apps, and Joseph asked for HABIT to
  stay exactly as it was. So `app.html` was restored to `7618bef` (only the version strings
  differ) and `crew.html` is the copy that carries everything since: 3-field signup, Inicio with
  today's workout, Desde cero / Elegir rutina, the initials button, the new Perfil, folded
  comments, community word filter + Normas, and the Instagram stickers (`habit-share.js`).
  **`app.html` (HABIT, the gym app) is frozen: do not change it unless Joseph asks for that
  specific change in HABIT.** What he has asked for so far reaches HABIT as a shared module it
  only loads: the stickers (`habit-share.js`) and Actividad (`habit-activity.js`). New work goes to `crew.html`; the `scripts/check-*.js` tests read
  `crew.html`. `crew.html` still contains the gym code and decides the brand from the path
  (`#brand-boot` → `IS_CREW`), so at `/crew` it hides everything that is the gym's
  (`GYM_ONLY_VIEWS`: book, planes, historial, shop; the door card, bookings, guest passes;
  admin/reception routing — staff enter Crew as members). Markup that differs carries
  `gym-only` / `crew-only`. One account works in both because it is one database. See
  `docs/HABIT_PARA_TODOS.md` D11–D13
- **Skandi Fit** (`skandi.html`, served at `/skandi`) — a separate training app for the crew of the
  Skandi Nomad (a DOF vessel). Shares `profiles` and `auth.users` with HABIT, and shares two pure JS
  modules (`skandi-recovery.js`, `body-figure.js`), but has its own tables (`skandi_*`), its own
  manifest, and no overlap in UI code. See `docs/PROYECTO_SKANDI_V2.md` for the roadmap in progress.

Plus one standalone page: **`competencia.html`** (served at `/competencia`) — the live scoreboard of
a lifting competition, for the gym's TV. Read-only; it's captured in Admin → Competencia.

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
- `sw.js` — service worker: push notifications + app shell cache. **One registration at scope `/` serves both apps** — two service workers at the root would evict each other, so Skandi registers this same file. Fetch handler: icons and the shared JS modules are cache-first, navigation is network-first (and refreshes the cached shell with what it just fetched), API calls pass through untouched. `shellFor()` picks the offline fallback by path: `/skandi*` → `skandi.html`, `/competencia*` → `competencia.html`, `/crew*` → `crew.html`, everything else → `app.html`. Any new standalone page needs its own line there: the navigation handler stores what it fetched under `shellFor()`, so a page that falls through to `app.html` overwrites the app's offline copy with itself. **Every response the worker stores or hands to a navigation goes through `clean()`**: Vercel answers `/app.html` with a redirect to `/app`, `cache.addAll` stored that as a `redirected` response, and Safari refuses to give one to a navigation — the installed iPhone app opened completely blank (not even the login screen) whenever it fell back to the cache. Saving the offline copy is a side effect that must never replace a page that did arrive from the network.
- `habit-share.js` — **stickers para historias de Instagram** (`docs/HISTORIAS_INSTAGRAM.md`),
  en **las dos apps**. Todo vive aquí —el dibujo, la galería (crea su propia hoja y su CSS, clases
  `hs-*`) y compartir— para que HABIT, congelada, solo reciba el `<script>` y una marca: un
  elemento con `data-hs-share="quote"` (+ `data-hs-text`, `data-hs-date`) abre la galería por
  un solo escucha de clics en el documento. Cada sticker es un PNG transparente de un color
  (`PALETTE`: 12, blanco y negro primero, o uno libre; la tinta de lo relleno la elige `inkFor()`
  por contraste), en Inter con el logo real, y **todos firman como HABIT Crew, también los de
  HABIT** (Joseph, 1 nov 2026: la marca que crece es Crew); la prueba falla si un estilo no dice
  CREW. La galería se desliza de un estilo a otro (miniaturas para saltar,
  **directo y no suave**: con scroll-snap, un salto suave que se cruza con un sticker recién
  pintado regresa al primero) y un solo botón **Compartir** (`navigator.share` con el archivo;
  sin hoja de compartir, descarga). Tres tipos en `KINDS`: `quote` (11 estilos), `workout` (hasta 19;
  `workoutFacts()` pone en palabras un entreno de la app o una carrera/nado/rodada, y el estilo
  que no tiene qué enseñar devuelve null y no sale) y `week` (hasta 22, según datos de disciplinas y sesiones). Una app abre los de entreno con
  `HabitShare.open({kind, data, title, subtitle})`. Las casillas (`data.fields`) no deben
  reducir el catálogo a los tres estilos editoriales: `workoutFacts` filtra la información antes
  de las plantillas, y `weeklyStudioLayout` adapta los semanales; Ritual, Bitácora y Balance son
  los primeros. Cada diseño semanal usa una firma de ancho objetivo 320 px sobre 1080. Los estilos nuevos son listas de trazos
  (`ops`) que dibuja `drawOps`, y `scripts/check-share.js` revisa que ninguno se salga del
  lienzo. **El cuadro de un logo es su tinta** (`LOGO_INK`: el PNG trae margen y `drawLogo` lo
  agranda) y todos firman abajo con el mismo logotipo a `SIG`; ninguna letra secundaria baja de
  ~30 px, porque en una historia el sticker se ve a un tercio. `ACTIVITY_TYPES` (palabras de cada tipo de actividad) vive aquí y Crew lo usa. Inter
  100–900 e itálica se piden al abrir la galería. Cambiar el módulo sin subir la versión deja a
  los teléfonos con el viejo: el service worker lo sirve cache-first por su URL con `?v=`
- `habit-skills.js` — **escaleras de skills de calistenia** (migración 141,
  `docs/PROYECTO_COACH.md`), para el coaching 1:1. Módulo puro (sin DOM ni Supabase, como
  `skandi-recovery.js`) con el motor de las 078/079 de Skandi: la **curva continua**
  (`skillLevel` = escalón + marca/objetivo, para que subir caiga en el número donde terminó el
  anterior y la gráfica no se lea como un derrumbe), el **estándar** (`readiness`:
  `progression_target_sets` series en el objetivo en **dos sesiones seguidas**; una sesión donde
  no entrenó ese ejercicio se salta, una donde sí y no llegó rompe la racha) y `cueList`.
  **Diferencia de fondo con Skandi: aquí nada sube de escalón solo.** HABIT no tiene nota de
  calidad por serie y la forma de un front lever la juzga quien ve el video, así que `readiness`
  le avisa al alumno que ya cumple para que lo grabe, y **el coach mueve el escalón**
  (`coach_student_skills`; un trigger lo historia en `coach_skill_events`). **Sin coach, lo
  mueve el alumno** (migración 144): `set_by` decide de quién es la fila (`rungOwner()`) —puesta
  por él, la elige, la sube y la quita él; puesta por otra persona, es del coach y la RLS no le
  deja tocarla (el USING del update mira la fila como estaba, que es lo que frena un upsert),
  ni escribir `coach_note`. Subir sigue siendo una persona tocando un botón cuando `readiness`
  dice que cumple, nunca la app sola. **Entrenar este escalón** (`skillTrainRung`) es un
  entreno libre con el nombre del skill, o el ejercicio agregado al que está abierto, con el
  estándar como objetivo (`rungWorkout`: mín. 3 series, 120 s de descanso); entra por
  `wsAddExercise` con su llave `cat-<slug>`, que `loadSkillMarksSb` también lee
  (`catalogSlugFromExKey`) — antes un escalón agregado en vivo no le contaba a la escalera. Y
  `wsExerciseFromCatalog` pone `repsType:'time'` a un aguante del catálogo: sin él la hoja pedía
  kg y reps para un front lever. Cada escalón **es un ejercicio del `exercise_catalog`** —así entra en
  rutinas, se le registran series y tiene ficha— con `progression_group/rank/target/
  target_sets/criteria` encima. La **animación** (`animation_url`, GIF o MP4 corto en bucle,
  bucket público `skill-media`) es columna aparte de `video_url` a propósito: `videoKindRank`
  pone YouTube/Drive por encima de un GIF, así que pegar el video de técnica borraría la
  animación de la escalera. La marca sale de `coaching_session_sets` (`actual_seconds` de la
  117, o un `actual_reps` viejo tipo "0:30"), y el puente entre una serie y un escalón son las
  rutinas del propio alumno: `ex_key` es el id del ejercicio dentro de su rutina, no el slug del
  catálogo. Una línea **puede mezclar unidades** (en handstand los heel pulls son repeticiones
  entre aguantes) porque cada escalón se mide contra su propio objetivo; el único que hereda el
  del anterior es el último, que por eso sí comparte unidad. En Crew: pestaña **Skills** en
  Entrenar, una sola hoja de escalera para alumno y coach (`openSkillSheet`) y los **cues
  numerados** del coach (`exercises[].note` partido en puntos) más el criterio del escalón en la
  hoja de entreno — antes `.ex-note` solo salía en la lista de la rutina y desaparecía justo al
  entrenar. `scripts/check-skills.js` lo prueba y, de paso, **compila el script principal de
  `crew.html`**, que no lo hacía nadie
- `skill-anim/*.svg` + `scripts/make-skill-anim.py` — **el dibujo de los 35 escalones**, las
  siete líneas (migraciones 142 y 143, que los enlazan en `animation_url` **solo donde está
  vacío**: el video que suba el coach manda). SVG animados con SMIL, que dentro de un `<img>`
  corren solos, pesan 4 KB y se ven nítidos lo mismo a 58 px que a tamaño de hoja; se sirven
  desde el repo, sin pasar por el bucket. Tres cosas del generador que no hay que deshacer: la
  figura se dibuja **ya en su posición** (la animación es solo lo de encima, así el script sabe
  dónde cae cada articulación), **la pose está quieta** —en una escalera se comparan ocho
  posiciones de un vistazo y ocho figuras repitiendo la entrada las dejan todas a mitad de
  camino— salvo donde el movimiento ES el ejercicio (el jalón de talón, el traspaso de peso), y
  el **viewBox se calcula y se cuadra solo**: un colgado invertido ocupa alto y un front lever
  ocupa ancho, y la miniatura es 1:1 con `object-fit:cover`, que a un lienzo alto le cortaría
  las piernas. **Lo que mira la cara es parte del dibujo**: un front lever y un back lever son
  la misma línea horizontal y lo único que los separa es ir de cara al techo o al piso, que un
  palo no dice; la nariz lo resuelve en un trazo. Y las dos líneas donde el movimiento ES el
  ejercicio —las elevaciones y el nórdico— sí se mueven de verdad, con la bajada ocupando más
  de la mitad del ciclo porque la lentitud es el estándar; un muscle-up negativo en cambio se
  baja doblando el brazo, así que es estático en la transición y no una marometa alrededor del
  hombro
- `habit-activity.js` — **la sección Actividad, en las dos apps** (HABIT la pidió el 1 nov 2026):
  un contenedor `#actividad-content`, su pestaña y `HabitActivity.render(el)` desde `sv()`. Junta
  los entrenos de la app, lo registrado a mano (`training_activities`), las sesiones de fuerza de
  Skandi y su cardio (`skandi_external_activities`, del reloj por Intervals.icu o Strava), y con
  Intervals conectado se sincroniza sola al abrir (`/api/skandi` `intervals-status` →
  `intervals-sync`, cada 20 min como mucho). Crea su propia hoja (`.act-overlay`, z-index 10000:
  debajo de la galería de stickers y de `confirmSheet`) y atiende sus clics con un escucha en el
  documento por `data-act`. **No es independiente**: usa globales de la app (`APP_GLOBALS`: `sb`,
  `sbUser`, fechas de Mazatlán, `sessionExerciseList`…), y `scripts/check-activity.js` falla si a
  alguna de las dos le falta una o si los botones de abajo no van en el orden de la lista que los
  marca (HABIT los empata por posición). Crew le pasa el cierre de un entreno
  (`HabitActivity.offerSessionStickers`); HABIT no
- `manifest.json` / `crew-manifest.json` / `skandi-manifest.json` — one PWA manifest per app. All use `scope: "/"` and are told apart by `id`.

**Version / cache busting**: one version string covers the whole project, because one service worker caches both apps. It lives in `APP_VERSION` (`app.html` **and** `crew.html`), `SKANDI_VERSION` (`skandi.html`) and `CACHE_VERSION` (`sw.js`), plus the `?v=` strings in `index.html`, the three manifests' `start_url`, the `<link>`/`<script>` tags at the top of `app.html`, `crew.html` and `skandi.html`, and the `v` inside the `#brand-boot` script of `app.html` and `crew.html`. Bumping the version is the one change `app.html` still takes. **Changing either app means bumping all of them to the same value** — a stale `CACHE_VERSION` leaves the offline shell frozen at the previous deploy.

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

**Entrenar → Rutinas son tres capas, de arriba abajo**: programa (`programCardHtml` →
`openProgramSheet`) → tu semana → rutinas. El botón de la pantalla es **«+ Crear»**
(`openCreateChooser`) con los tres verbos en orden de tamaño — programa, rutina, ejercicio — y
no un atajo para asignar rutinas ya existentes. La hoja del programa edita sus siete días en el
lugar (`openProgramDayEditor` → `setProgramDay`); mientras el programa esté cargado, esa
escritura va a `skandi_program_days`. Desde la migración 102, un programa activo con
`start_date` es la fuente de la verdad de la semana y `skandi_ensure_week` estampa el calendario
desde sus días; `skandi_templates.weekday` queda como día sugerido y como respaldo completo para
quien no tenga programa activo. Ver `docs/CAPAS_ENTRENAR_SKANDI.md`.

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
  `ANTHROPIC_API_KEY`. `{action:'analyze', append:true, photo_path, note}` (migration 092): a
  second (or third) photo added to a meal already registered — nobody photographs the whole plate
  in one shot on a boat — goes through `skandi_append_meal_items()` instead of
  `skandi_save_meal_items()`, which **adds** rows instead of replacing them; a failure here never
  marks the meal `failed` (it already has valid rows) and any uploaded-but-unsaved append photo is
  removed from the bucket rather than left orphaned. `{action:'barcode'}`: barcode → Open Food
  Facts → a `skandi_foods` row, **no AI and no quota** — a packaged product ships its own macros.
  `{action:'meal-suggestion'}`: today's
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
- `delete-user.js` — the admin deletes a member (with a reason), or a member deletes their own
  account from Perfil (`{self:true}`, `role = 'user'` only). Same function: the 12-function ceiling
- `sync-stripe-payments.js` — admin-triggered payment sync

Plans (prices, credits, expiry days) are defined centrally in `api/_plans.js` and shared by `_fulfillment.js`, `create-checkout-session.js`, and `confirm-checkout-session.js`.

### Database (Supabase)
Schema is in `habit-supabase-setup.sql`. Additional migrations are separate `.sql` files that must be run manually in the Supabase SQL Editor.

Core tables:
- `profiles` — extends `auth.users`; has `role` (`user`/`admin`/`reception`), 4-digit `access_code`, `credits`, `plan_id`, `plan_expiry`
- **Entrenar y la Comunidad son de cualquier cuenta, no solo de socios** (migración 127,
  `docs/HABIT_PARA_TODOS.md`). `MEMBER_LOCKED_VIEWS` es solo `['book']`, y el candado que de
  verdad cuenta es `book_my_slot` (120): la puerta solo mira reservas. La comunidad es una sola
  en HABIT y en HABIT Crew (las políticas de `posts` siempre pidieron solo sesión).
  `profiles.joined_as` (`gym`/`app`) dice **por dónde entró** —la app en la que se registró:
  HABIT es `gym`, HABIT Crew es `app`—, no qué puede hacer —
  no confundir con `profiles.source` (habit/skandi, 055). Lo escribe `handle_new_user` desde
  los metadatos del `signUp` (el perfil nace en ese trigger, antes de que la app llame
  `ensure_habit_profile`), y con `app` el trigger de la 122 no asigna rutinas básicas, no
  sale el push "Nuevo socio" y se aceptan los términos de la app; el reglamento del gym se
  acepta en `doPay` antes de su primera membresía. `isAppOnly()` (app) /
  `isAppOnlyProfile()` (admin) = `joined_as = 'app'` **y** nunca ha tenido plan ni pago real:
  en cuanto compra cuenta como socio. Su onboarding vive en `training_profiles` (privada, como
  `skandi_settings`). Borrar la propia cuenta es `api/delete-user.js` con `{self:true}`
  (solo `role = 'user'`), que Apple exige para publicar
- `bookings` — reservations; `ds` = date (`YYYY-MM-DD`), `start_idx` = slot index 0–47 (each slot = 30 min), `slots_used` = 2 or 3
- `slot_occupancy` — one row per booked slot per user per day
- **Reservar, cancelar y cambiar de horario los hace el servidor** (migración 120):
  `book_my_slot` / `cancel_my_booking` / `reschedule_my_booking`, cada uno una transacción con
  candado por día. Las reglas de `canStartAt()` / `canCancelBk()` (cupo de 4, bloqueos, una
  reserva por día, 7 días, plan vigente ese día, 12 h / 2 h) viven **dos veces**: en la app para
  avisar rápido y en esos RPC para decidir — cambiar una regla es cambiarla en los dos lados.
  `bookings.credit_charged` dice si la reserva cobró visita, y cancelar devuelve eso. El socio
  ya no escribe `bookings`, `slot_occupancy` ni `payments`, y `guard_profile_billing` (trigger
  **security invoker**: distingue por `current_user`, que dentro de un RPC security definer es
  el dueño) le impide tocar `credits`/`plan_*` de su perfil; el admin y el service-role siguen
  escribiendo directo. Los errores salen como códigos (`SLOT_FULL`…) que `BOOKING_RPC_ERRORS`
  traduce. Las funciones `legacy*` de app.html son el camino previo a la 120 y se pueden borrar.
  **Cuidado con NULL en esas reglas**: `plan_id in ('im','gm')` con `plan_id` null da null, y
  `false or null` también; sin `coalesce`, una cuenta nueva sin plan ni visitas reservaba y
  quedaba en −1 (encontrado antes de correr la 120, probado contra Postgres real)
- `slot_blocks` — admin-created manual blocks
- `payments` — payment records (Stripe and manual)
- `door_commands` — queue of door open requests with Shelly execution status
- `access_log` — history of door access events
- `boards` / `board_assignments` / `scores` — workout boards feature. A board with `owner_id` null
  is a gym/coach board; with `owner_id` set it's a member-built routine (migration 070), and the
  `SELECT` policy is `owner_id is null or owner_id = auth.uid()`. Member routines always carry
  `MEMBER_ROUTINE_COLOR`; the color is what tells a member's routine apart from the coach's, so
  it is not theirs to pick and `routineColor()` resolves it at render time
- **Una serie en pirámide** (10-9-8-7-6-5-4-3-2-1) no es un campo nuevo: es un objetivo por
  serie, guardado en el mismo `boards.exercises[].reps` con `repsType:'pyramid'`, y las series
  se derivan de los escalones — `exerciseSetCount()` manda sobre el campo `sets`, que se guarda
  sincronizado solo para que lo lea quien no sepa de pirámides. `coaching_session_sets.
  reps_target` ya era `text` y siempre fue por fila, así que la siembra solo pasó de repetir la
  misma cifra a repartir `repsTargetForSet(ex, i)`; una serie agregada de más al final repite el
  último escalón. Adivinar una pirámide en un dato que nadie marcó pide **3+ escalones**
  (`sniffPyramidReps`): "8-10" es el rango de toda la vida, no una pirámide de dos series — por
  eso el builder del socio y el alta masiva del catálogo la reconocen con solo escribirla,
  mientras que el formulario del coach la elige explícita en Objetivo → Pirámide (y ahí sí
  admite dos escalones). El consejo de progresión compara escalón contra escalón, no contra un
  rango, porque una pirámide no tiene mínimo ni máximo
**La pestaña Plan del coach son tres capas, de arriba abajo**: programa
(`coachProgramSectionHtml` → `openCoachProgramManage`) → semana → rutinas del
cliente. Elegir la rutina de un día abre `openCoachBoardPicker(mode, dow, ds)`,
una hoja con buscador —que entra también en los nombres de los ejercicios— vista
previa del contenido y filtros; el `<select>` con el catálogo entero que había
antes no decía qué trae cada rutina, que es justo lo que hay que ver antes de
asignarla. La misma hoja sirve para un día de la semana y para un día del
programa: lo único que cambia es a dónde va la elección (`coachPicker.mode`).
`coachWeekDayState(i)` resuelve todo lo que se sabe de un día y la consumen el
render y el guardado — el guardado ya no lee el DOM, así que no depende de que
el panel esté pintado.

**Una sola hoja para elegir rutina, cinco destinos** (`openCoachBoardPicker(mode, dow, ds,
programId)`): `week` / `program` son el coach sobre su cliente, `my-week` / `my-program` el socio
sobre lo suyo, y `start` es el socio entrenando algo ahora — ahí la primera fila deja de ser
«Descanso» y pasa a ser «Entreno libre», que es lo que funde los dos botones que había en Hoy.
`coachPickerIsMember()` decide de dónde salen las rutinas (`myRoutines` o `coachAssignableBoards()`),
qué filtros se ofrecen y con qué vocabulario se etiqueta cada una — el coach necesita saber si ya
se la asignó, el socio si es suya o del gym. Elegir una rutina es el mismo acto lo haga quien lo
haga, así que es el mismo componente; `openDayPicker` del socio quedó reducido a una llamada.

**El chooser del socio (`openCreateChooser`) tiene tres verbos, no cuatro**: entrenar ahora, una
rutina, un programa. No hay «crear ejercicio» a propósito — en HABIT el ejercicio se elige del
`exercise_catalog` y no se escribe, porque escribirlo a mano deja fichas sin músculo, sin
indicaciones y sin video, que son los datos de los que vive la ficha de técnica.

**El editor de semana del coach guarda dos cosas distintas** (`saveCoachingWeekSb(mode)` en
`app.html`): `'week'` toca solo los siete días en pantalla, `'base'` reescribe la plantilla que
se repite. Eran un solo botón, y por eso ajustar el miércoles de la semana que viene cambiaba el
miércoles del cliente para siempre. Un descanso de una sola semana se marca `status='skipped'`
conservando `base_template_dow`, no se borra: borrar la fila solo hace que el RPC la vuelva a
sembrar. Y solo se escribe lo que el coach movió — `coachAdminWeekDraft` guarda esos días en
memoria porque el panel se repinta entero por causas ajenas al editor.

**Entrenar vs Coaching.** The `rutinas` view (labelled "Entrenar") owns everything about
training and is open to every member: today's session, the weekly grid, the member's routines,
the muscle-fatigue body and the Progreso screen. The `coaching` view is only for David's clients
(`profiles.coaching_beta`) and owns only what the coach relationship adds: chat, habits, fasting,
adherence and the post-workout feedback he reads. Nothing is rendered in both — Coaching links
into Entrenar instead. `coaching_week_templates.created_by` says who set each weekday, which is
what lets Entrenar mark a day as "de tu coach" and the coach's panel mark one as set by the
member; both sides rewrite the whole week on save, so that marking is the only thing preventing
a silent overwrite.
**La sección Coaching del socio está apagada** (26 oct 2026: 16 socios la tenían y el último
mensaje era del 18 sep). Es un interruptor, `COACHING_SECTION_ON = false` en `app.html`, y no un
borrado: `canAccessCoaching()` lo respeta, y con él se van la pestaña, el chat en vivo, el ayuno de
Inicio, el botón «Asesoría» de la ficha y las "solicitudes" al coach al editar un día que él puso
(el socio lo edita directo, porque nadie leería la solicitud). `coaching_beta`, los datos y el
panel del coach en Admin siguen igual: el coach puede seguir armando semanas y programas, que el
socio ve en Entrenar. Encenderla de nuevo es poner `true`.

- `coaching_week_templates` / `coaching_programs` / `coaching_program_days` /
  `coaching_program_weeks` — the member's weekly plan (`dow` 0 = Monday) and the programs that
  own it. Migration 114 opened programs to the coach (admin RLS was `select`-only), added
  `created_by`, and made `user_id` nullable: **a program with `user_id` null is a gym template**
  — nobody follows it, it gets copied onto a client (a CHECK forbids a template being active),
  the same trick as `boards.owner_id` null. Migration 115 turns a program into a dated cycle:
  `start_date` + `weeks`, `coaching_program_days.week_index` (0 = every week, N = that week only)
  and `coaching_program_weeks.phase`. **`start_date` is the switch** — without it a program is
  still one repeating week and everything behaves as before.
  With it, `ensure_coaching_week_from_template` stamps the calendar from the program, week by
  week, and `coaching_schedule.program_id` / `program_week_index` record which cycle each day
  came from. The resolution rule lives in exactly one place, `coaching_week_slots()`, and is
  **replacement, not merge**: if week N has a row for that day, it is the whole day. A
  `coaching_program_days` row with `board_id` null is a **rest-day marker**, not a half-written
  row — it is the only way to say "week 5 rests on Friday", since deleting the row would make
  that day inherit from the week-0 rows again; the stamping ignores those rows.
  A cycle **never repeats itself by calendar alone** (past the last week the index goes -1 and
  stamping stops) — finishing a block is when the coach re-evaluates. Applying a program goes
  through the `apply_coaching_program` RPC, not loose client writes: it is four writes that must
  land together, and half of them leaves the member with no week at all
- **La hoja de entrenamiento** (`renderWorkoutSheet`; pulido Fase A, bitácora de
  `docs/HABIT_PARA_TODOS.md`). Palomear sin escribir es "hice lo planeado": `defaultRepsFromTarget` guarda el número del
  objetivo o el **piso** de un rango ("8-10" → 8; registrar de menos nunca inventa progreso); "al
  fallo" o "rondas" no se suponen. El peso de una serie se copia a la siguiente y se ve en su campo
  al instante. "La vez pasada" sale de **una** consulta, `lastScoresFor(exKeys, excludeScheduleId)`
  (memo de 60 s, compartida por la siembra, la hidratación y "Última vez"), y **excluye la sesión
  en curso** — si no, la primera serie de hoy se volvía "Última vez" y sugería subir de peso a
  media sesión. Cancelar borra los `user_scores` de la sesión **antes** que las series (la FK es
  `on delete set null`: después quedan huérfanos y salen como PR). Nada se mueve bajo el dedo:
  con la hoja abierta no se pliega un ejercicio recién terminado (`wsExpandedDone`), la siguiente
  serie se marca en su lugar (`wsMarkNextRow`) y `wsScrollToFocus` solo desplaza si no se ve.
  RIR aparece si el socio lo encendió (`habit_show_rir` en localStorage), o si la rutina o la serie
  lo traen; borrar una serie y "Marcar todas" viven en el menú ••• del ejercicio, no junto a cada
  palomita. Sin descanso escrito, 90 s (`DEFAULT_REST_SEC`), salvo calentamiento y movilidad,
  como barra ancha (`ws-rest-strip`). Asistencia (WhatsApp) vive en Perfil, no en Entrenar
- **Cambiar, agregar y cerrar un entreno** (bloque 1 del análisis de uso, oct 2026: en 90 días
  nadie cambió un ejercicio a media sesión y 40 de 89 entrenos se cerraron sin una serie). Deslizar
  la cabeza de un ejercicio a la izquierda descubre Cambiar / Quitar (`.ws-ex-swipe`, gesto por
  delegación en el documento porque la hoja se repinta con `innerHTML`; el ••• sigue igual). Solo
  salen los botones que aplican: Cambiar si quedan series, y Quitar pasa a **Terminar** en un
  ejercicio empezado — borra solo las series pendientes y deja las hechas, sin tocar el overlay.
  Cambiar ordena el catálogo por parecido (`wsSimilarity`: reparto de músculos, patrón, equipo;
  haber hecho un ejercicio hace poco desempata, pero no cuenta para el umbral de «parecido»);
  Agregar muestra primero **Recientes** (`wsLoadRecents`), sacados de las series de tus últimos
  entrenos cerrados y no de `user_scores`, que solo guarda series con peso. Al finalizar con series
  sin palomear, la primera opción es «Hice todo lo planeado» (`wsMarkPendingAsPlannedSb`, misma
  regla que palomear sin escribir); con cero series no existe «finalizar vacío», la otra opción
  es descartarlo. Con cambios en la sesión, `wsOfferSaveSessionChanges` ofrece
  dejarlos en la rutina (la tuya se actualiza; la del coach o del gym se copia como tuya), y cada
  ejercicio se guarda con `id` = su ex_key de hoy para que "La vez pasada" lo encuentre. Un entreno
  abierto hace más de 3 h se pregunta al volver (`wsCheckForgottenSession`) y se cierra sin el RPC,
  terminando en la última serie palomeada (máx. 4 h). Todo cierre pasa por `wsAfterSessionClosed`.
  `scripts/check-session-edits.js` lo prueba. Un `replaces` se sigue igual sobre un ejercicio de
  la rutina que sobre uno agregado hoy (`sessionExerciseList`): antes solo en los de la rutina, y
  en un entreno libre cambiar un ejercicio lo dejaba igual
- **Empezar a entrenar** (bloque 2, oct 2026: 53 socios reservaban y solo 16 registraban).
  **La puerta pregunta «¿Qué entrenas hoy?»**: abrirla desde la app (`requestDoorOpen` →
  `doorTrainingPrompt('door')`) saca una hoja con lo de hoy, «Repetir …» y «Otra cosa»
  (`doorTrainChoices`), una vez al día y nunca si ya entrenó o tiene uno en curso. Entrar con
  el teclado manda la misma pregunta como notificación (`sendTrainingPush` en
  `api/validate-access-code.js`, solo en la primera entrada de la reserva, solo a quien tiene
  `push_subscriptions` —eran 3 socios en oct 2026— y con tope de 1.2 s, porque el teclado espera
  esa respuesta para abrir). La notificación lleva `url: '/app?entrenar=1'`: `notificationclick`
  en `sw.js` abre esa url o, con HABIT ya abierta, le manda `habit-notification-click` por
  `postMessage`; `handleTrainDeepLink()` (al final de `showMainSb`) y ese mensaje llaman
  `doorTrainingPrompt('push')`, que pregunta siempre. **«Repetir el último»** en Hoy cuando no hay
  nada agendado (`hoyRepeatable` sobre `loadRecentSessionsSb`, los últimos 20 entrenos cerrados
  sin series): repetir es **la rutina, no sus cambios** —lo que se quiso fijo ya se guardó al
  cerrar—, y un entreno libre se repite copiando los ejercicios agregados con su misma `ex_key`
  para que "La vez pasada" traiga los pesos. **Tus rutinas en Hoy**: una fila que se desliza
  (`hoyRoutinesHtml`, máx. 8), la entrenada hace poco primero y luego el orden de `myRoutines`;
  tocar una pide confirmar (`hoyStartRoutine`), porque en una fila que se desliza los toques sin
  querer son normales. `scripts/check-hoy.js` lo prueba.
  **Lo que se pasó esta semana** (`hoyMissedHtml`): un día de esta semana que nadie empezó sale
  en Hoy con «Hacer hoy» y «Omitir»; la semana pasada no se arrastra. «Hacer hoy» **no mueve la
  fila** —`ensure_coaching_week_from_template` borra lo estampado por la base que ya no cae en
  su día y vuelve a estampar el hueco, así que lo movido desaparecía y reaparecía en su día
  (por eso `moveMissedWorkoutToTodaySb`, de Coaching, no se usa aquí)—: crea uno propio para
  hoy y deja el original en `skipped`, que conserva `base_template_dow` y ocupa su hueco.
  El 29 oct 2026 se cerraron a mano los 9 entrenos `in_progress` empezados antes del 20 oct y
  sin una serie hecha (ago–oct): quedaron `skipped` **con `started_at`**, que es lo que los
  distingue de un descanso normal si hubiera que revertirlo
- **Avisos (web push) del socio** (migración 137, oct 2026). Del 18 may al 26 oct 2026 **ningún
  socio guardó su suscripción**: un "hard revert" (60da6cc) quitó las llamadas a `registerPush()`
  y quedaban 3 filas. Ahora: `ensurePushSubscription()` suscribe en silencio, al entrar
  (`showMainSb`, y `renderPushBanner` en el admin), a quien ya dio permiso; el permiso se pide
  **solo desde un toque** (`enablePush`, que llama `requestPermission` antes de cualquier
  `await`, porque iOS ignora la petición que no sale de un gesto) y con contexto: tras reservar y
  al entrar a la lista de espera (`maybeAskPush`, máx. 3 veces y una por semana), la tarjeta de
  Inicio (`#inicio-push-card`, se oculta con ×) y Perfil → Avisos. Nada más pide el permiso:
  `sendNotif` ya no lo hace. `pushStateFor()` decide el caso — `install` es un iPhone en Safari
  sin agregar a inicio, donde iOS no da avisos y lo único útil es enseñar a instalarla
  (`openPushInstallGuide`); `native` es la app de Capacitor, que aún no los trae (necesita APNs).
  Guardar pasa por `save_push_subscription()` (137): la llave es el **dispositivo**
  (`endpoint`, columna generada con índice único), no la persona —antes no había llave y el
  upsert del admin `on_conflict=user_id` fallaba—; un teléfono que cambia de cuenta pasa la
  fila a la cuenta nueva (la RLS no deja tocar la ajena) y el `role` lo pone el servidor. La
  lectura del admin en esa tabla mira `virtus.auth_user_role()`, no el rol de HABIT: el conteo
  de Admin → Notificaciones sale de `push_subscription_stats()`. `scripts/check-push.js`
  La ficha de un ejercicio (`exercise-focus-modal`) se abre **encima** de la hoja: su botón de
  arriba es «‹ Ejercicios» (`exerciseFocusBack`, vuelve a la hoja en el ejercicio que se veía),
  no «Pausar» — así decía y nadie encontraba la lista. Pausar la sesión vive en el reloj de la hoja.
  **El Reloj** (`openClockSheet`, `#clock-sheet`) es aparte del descanso entre series: cronómetro
  con vueltas, temporizador y intervalos (Tabata/EMOM, 5 s de «Prepárate», 3-2-1 sonoro). Todo
  contra el reloj de pared y guardado en `localStorage` (`habit_clock_v1`), porque iOS duerme el
  PWA; un temporizador que terminó con la app dormida no suena tarde al volver. Lo abren los
  botones `.clk-launch` (botón flotante, ficha, panel de tiempo de la hoja), que muestran la
  cuenta mientras algo corre
- **Icono de cada ejercicio** en lugar del número (hoja de entreno, lista de la rutina, Cambiar /
  Agregar): `HabitTraining.exercisePattern(ex)` en `habit-training.js` decide el patrón de
  movimiento por el nombre —en español o en inglés— y solo si el nombre no dice nada cae a los
  músculos; `EXERCISE_ICONS` en `app.html` dibuja uno por patrón (línea de 1.6 en rejilla de 24).
  **El orden de las reglas es la lógica**: lo específico gana, así que «Pike push up» y «de pica»
  son press arriba, «remadora» es cardio, «Retracción escapular en flexión (calentamiento)» es
  flexión y no movilidad, «plancha» es abdomen pero «planche» es planche, y las variantes del
  front lever que no dicen "lever" (front press, half press, touch tuck) son lever.
  `scripts/check-training.js` lo prueba con nombres reales de las rutinas
- `coaching_schedule.session_exercises` — JSONB overlay of exercises swapped in or added during a
  live session. `boards.exercises` is never mutated by a workout; `sessionExerciseList()` in
  `app.html` merges the two and is the single source of the effective exercise list
- `exercise_catalog` — the only place a member can pick an exercise from. Migration 071 imported
  Skandi Fit's `skandi_exercises` into it (names translated to Spanish, English name kept as an
  alias); its `video_url` values are GIFs and MP4s, not embeds, so `mediaKind()` in `app.html`
  decides between `<img>`, `<video>` and an iframe. **The gym's own Drive/YouTube videos live in
  `boards.exercises`, not in the catalog**: picking a catalog exercise and pasting a link used to
  save it only on that routine. `muscleExerciseVideo()` (the muscle sheet's play button) looks in
  the exercise itself → every gym board (`loadGymExerciseVideoIndex`, by catalog id / name slug /
  alias) → the catalog, and adding a catalog exercise with a link now also fills the catalog's
  `video_url` (`upgradeCatalogVideo`). Among the candidates the **type** wins before the order:
  YouTube/Drive > MP4 > GIF (`videoKindRank`), because the GIFs and MP4s are Skandi's import and
  a routine that picked the exercise from the catalog carries a copy of that GIF; a gym-recorded
  video replaces a GIF in the catalog too, never an equal or better one.
  **An exercise's identity is its name signature, not its spelling**: `exerciseSignature()` (no
  accents, no "de/con/en", singular, a few synonyms — lagartija = push up, bench = banca, bar =
  barra) is what `findExerciseCatalogMatch()` falls back to after the exact match, so a coach
  typing "Extension de tricep con cuerda" links to "Extensión tríceps cuerda" instead of creating
  a new catalog row (the live search while typing stays exact, `strict`). The same signature keys
  the video index (`g:`). `saveExerciseCatalogFromBoardExercise` no longer rewrites a row that
  already exists — its upsert renamed it after the routine and emptied its aliases — it only
  upgrades the video. Duplicates already in the catalog are grouped by signature (aliases
  included) in Admin → Ejercicios → "Posibles repetidos", and `merge_exercise_catalog(keep, drop)`
  (migration 123) merges a pair: the dropped row goes `is_active = false`, its name and slug
  become aliases of the kept one, it keeps the best video and fills what the kept one lacked, and
  routines and `session_exercises` are repointed (`catalogId`/`exerciseKey` only — names and set
  history are untouched, since history goes by each routine exercise's own id).
  **A null `auth.uid()` is not proof of the SQL Editor**: a call with the app's public anon key
  arrives without one too, and Supabase's default privileges grant EXECUTE on every new `public`
  function to `anon`, so `revoke … from public` doesn't remove it. 123 trusted a null uid and the
  anon key could merge any exercise; 124 revokes `anon` explicitly and checks `auth.role()` (empty
  in the SQL Editor, `service_role` from the server) instead. It also revokes `anon` on 057's
  `assign_default_member_boards` — only if it exists, since production doesn't have it and a
  revoke on a missing function aborts the whole migration.
  **Admin → Ejercicios** is the catalog's own screen (before, it was only ever written as a side
  effect of saving a routine exercise — which is how the coach's upsert renamed "Hip thrust" to
  "HIP THRUST" and emptied its muscle; migration 125 repaired those from `muscle_split`, 037's
  seed with 072's leg mapping, and `skandi_exercises` via 071's translation, gave the hand-typed
  exercises a muscle, and merged the clear duplicates). It edits name, aliases, muscles (changing
  them empties `muscle_split` so the app derives it), video (offering the videos the exercise
  already has in routines, and optionally pushing the new one into them), and hides / restores /
  merges. "Posibles repetidos" shows the exact-signature groups plus **parecidos**: names equal but
  for one word or one typo (`sigTokenClose`, edit distance ≤ 1), unless that word marks a variant
  (`EXERCISE_VARIANT_WORDS`: inclinado, tuck, multipower…) — dismissed pairs live in localStorage.
  **Ver un video o foto** pasa por un solo visor, `openMediaViewer(videos, {title, idx, ex})`
  (`#media-viewer`): una hoja que sube, respeta la forma del medio (YouTube 16:9; Shorts y
  Drive 9:16, porque el gym graba con el teléfono; fotos/GIF/MP4 a su tamaño), arranca solo
  (YouTube con `mute=1`, que es lo único que iOS deja reproducir sin gesto), y abajo muestra
  músculos y «cómo se hace». En la ficha el video va arriba sin botón para mostrarlo
  (`exerciseInlineMediaHtml`): GIF/MP4 corren mudos en bucle y YouTube/Drive enseñan su
  miniatura y reproducen ahí mismo al tocarla. `renderExerciseFocusVideo` no repinta si ya
  muestra ese video, porque la ficha se refresca sola al llegar la rutina del servidor y eso
  reiniciaba el reproductor; cerrar la ficha o el visor quita el iframe, que es lo que detiene
  el sonido. `openVideoModal` queda como alias para el editor del admin.
  During a workout the video is `exerciseVideosForWorkout()`: the routine's own, unless the catalog
  has one of a better kind (YouTube over the GIF the routine copied, anything over nothing), so a
  video changed in Ejercicios reaches the workout without touching every routine
- `boards.is_starter` (migration 116) — a **rutina básica**: a gym board every member sees
  without anyone assigning it. Not `board_assignments`, which is one row per member per board:
  seeding those leaves thousands of rows to maintain and covers nobody who registers tomorrow.
  A starter board is the gym's, like a `user_id`-null program template (114), so it is marked
  once on the board. RLS didn't change — `boards` already lets any authenticated user read
  everything with `owner_id` null; what was missing was the app knowing which ones to show.
  116 seeds it from the blue (`#2563eb`) gym boards that have exercises, printing the list as
  NOTICEs first: blue was only the seed heuristic (it is the editor's default colour), and from
  then on the column is what counts — the "Rutina básica" toggle in Admin → Rutinas moves it.
  **116 replaces migration 057**, which did this with assignments (`assign_default_member_boards`
  + an after-insert trigger on `profiles`): one row per member per board, only created at
  registration so yesterday's members never got a newly-added starter, and indistinguishable in
  the coach's panel from what he assigned on purpose. 116 dropped that trigger and deleted the
  assignments pointing at a starter board.
  **Migration 122 brings the assignments back on top of `is_starter`**, because in Admin →
  Editar socio → "Pizarrones asignados" the starters showed unchecked, and an empty list reads as
  a member with no routines. The column still decides: `default_member_board_ids()` is now "the
  starter boards", and the after-insert trigger on `profiles` assigns them to every new HABIT
  member (inserting directly, and degrading any error to a WARNING — a failed assignment must
  never abort the profile insert). 122 also marked the blue gym boards made after 116 as
  starters, and backfilled members with no assigned and no own routine. Visibility still comes
  from `is_starter` alone, so a starter reaches members who registered before it was marked;
  the assignment only makes it show as checked
  `loadMyRoutinesSb` asks for the three origins separately (own / assigned / starter) and tags
  `_starterOnly` on every `is_starter` board, assigned or not, which is what splits the member's
  list into "De tu entrenador" and "Rutinas básicas"
**Estilo grafito** (oct 2026): la última capa de la hoja de estilos de `app.html` («HABIT
GRAFITO») sube el fondo de negro puro a grafito (`--black:#141518`, `--card`, `--card2`) con los
mismos colores de marca, y quita bordes: las capas se distinguen por tono. Va al final a propósito,
para pisar por orden en lugar de reescribir cientos de reglas; un estilo nuevo que pinte un fondo
debe usar `var(--black)` / `var(--card)`, no `#050505`. Sin `backdrop-filter` en barras y hojas
(el blur sobre contenido en movimiento tiraba cuadros en iPhone). Pantallas, hojas y modales
entran con una animación CSS que arranca sola al pasar de `display:none` a visible, así que el JS
que las abre no cambió y repintar su contenido no la repite. Videos y fotos siguen sobre negro.

**No queda un `confirm()` ni un `prompt()` nativo en `app.html`**: los sustituyen `confirmSheet()`
y `promptSheet()` (mismo patrón que Skandi en `a6ea2cb`, sin su i18n), que devuelven promesas —
`if(!confirm(x))` pasó a `if(!await confirmSheet(x))`, y las cinco funciones que no eran `async`
lo son ahora. `promptSheet` imita al nativo a propósito: `null` al cancelar, string al aceptar,
`''` si se borró todo. Tocar el fondo cancela, nunca confirma. Las acciones destructivas pasan
`{danger:true}` y un verbo propio ("Eliminar", "Cancelar entreno") en vez de un "Aceptar" genérico.
El overlay (`#confirm-overlay`, z-index 10050) y el toast (10060) van **encima de toda hoja**
(`.terms-modal` 9999): se abren desde dentro de ellas, y con 2600 quedaban detrás, invisibles.
`choiceSheet(body, choices)` es el tercero del mismo overlay: una lista de opciones
(`{key, label, danger}`) que resuelve con la `key` elegida o `null` — el menú ⋯ de la comunidad.

**`withScrollKept(el, paint)`** envuelve los repintados de una pieza (`innerHTML` entero) para
devolver el scroll del contenedor. Marcar un día o asignar una rutina devolvía al usuario arriba
del todo, que es lo que hacía sentir que la página se recargaba en vez de que cambiara lo tocado.

**Coaching → Seguimiento** (tab id still `programa`) shows how the week went — day states,
feedback, habits, fasting — and links out to Entrenar to change anything. It was called "Plan",
which was the only reason it looked like it duplicated Entrenar's week; nothing is edited in both
places. PRs live in **Progreso** only: Historial used to render them too, with its own
`user_scores` query, and now keeps what its name promises (reservas y pagos) plus a link.

- **Actividad** (HABIT y Crew por `habit-activity.js`, migración 139, `docs/HABIT_PARA_TODOS.md`
  bitácora del 1 nov 2026; además lee Skandi, ver arriba):
  una pestaña con todo lo que entrenas — los entrenos de la app (`coaching_schedule` `done`) y lo
  registrado de fuera en `training_activities` (correr, bici, nadar, caminar, fuerza, cardio,
  yoga, deporte, otro; `ds`, `duration_sec`, `distance_m` —nadar también en metros—, esfuerzo
  1–10 y opcionales). Privada: RLS de cada quien sobre lo suyo. `source` + `external_id` (índice
  único normal, no parcial) son para importar de Strava después sin otra tabla. La lista no pide
  las series (pesan): `stickerData()` las trae al abrir un entreno. El Nº de cada entreno cuenta
  también lo anterior a la ventana (`state.windowDays`) y todas las fuentes. En Crew, al cerrar un
  entreno, `wsAfterSessionClosed` abre sus stickers (`HabitActivity.offerSessionStickers`) en
  lugar del «¿Cómo te fue?», que queda para quien tiene coaching. Sin la 139, la sección muestra
  lo demás y esconde Registrar
- `posts` / `post_reactions` / `post_comments` — community feed. **Las listas nunca piden
  `img_url` junto con lo demás** (`POST_LIST_COLUMNS` + `attachPostImages()`): las fotos de antes
  de la 017 están en base64 dentro de la tabla (una pesa 6.4 MB y hacía tardar el feed ~6 s), así
  que las URLs se piden aparte con `not like 'data:%'`, de las incrustadas solo el id, y esas se
  muestran como "Ver foto" y se bajan al tocarlas (`loadEmbeddedPostImage`)
- **Moderación de la comunidad** (migración 128, `docs/HABIT_PARA_TODOS.md` D13): lo que Apple
  pide (guideline 1.2) a una app con contenido de usuarios, en HABIT y HABIT Crew a la vez.
  `community_reports`: el socio inserta (solo `post_id`/`comment_id`, `reason`, `details`:
  permisos por columna) y **no lee ninguno, ni los suyos** — el duplicado se sabe por el 23505
  de los índices parciales (uno pendiente por persona y cosa). Quién reporta, a quién y una
  **copia** de lo reportado (texto, foto, autor) los pone un trigger: el cliente no puede mentir
  sobre a quién reporta, y la cola sigue sirviendo si el autor lo borra. Todas sus referencias
  son `on delete set null` (un reporte es historia), y por eso no hay CHECK de "post o
  comentario": el set null lo rompería y el borrado del post fallaría. El admin solo cambia
  `status`/`resolution_note`; `resolved_by`/`resolved_at` los pone otro trigger, que desde el
  service role respeta el `resolved_by` que llega. Cada reporte deja un aviso en `admin_notifs`
  (trigger) y la app manda además un push al admin.
  `community_blocks` es privada: el bloqueado nunca la lee. **El filtro del bloqueo está en la
  RLS, no en `renderFeedSb`** — políticas `restrictive` (se suman con AND a las permisivas que
  haya, que la 001/005/007 recrearon con nombres distintos) sobre la lectura de `posts`,
  `post_comments` y `user_notifications` (`community_visible_author()`) y sobre el insert de
  comentarios y reacciones (`community_can_interact()`); así lo embebido
  (`posts?select=*,post_comments(…)`) también se filtra y lo bloqueado no llega al teléfono.
  Corre en los dos sentidos —el bloqueado tampoco ve ni comenta lo de quien lo bloqueó, que es
  lo que impide el acoso en los comentarios— salvo hacia el admin: bloquearlo no lo deja ciego.
  Son `to authenticated` porque `anon` no ejecuta esas funciones y su lectura de `posts` pasaría
  de vacía a error. Borrar sigue siendo `api/delete-community-item.js`, que ahora resuelve los
  pendientes de lo que borra (los busca **antes** de borrar: después el set null ya no deja
  encontrarlos). En la app: ⋯ solo en lo ajeno (`communityMoreBtn` → `openCommunityItemMenu`;
  el admin solo ve "Bloquear", porque él borra), Perfil → Usuarios bloqueados
  (`renderPerfilBlocks`, que se esconde si falta la 128) y Admin → Comunidad arriba del feed
  (`renderAdminReports`, agrupado por lo reportado; el badge suma posts nuevos + pendientes)
  **Filtro de palabras** (migración 138): el trigger `community_text_guard` rechaza con
  `COMMUNITY_TEXT_BLOCKED` el texto de posts, comentarios, retos y notas de marcas con una
  palabra de `community_blocked_terms()`; la app revisa lo mismo antes (`communityTextBlocked`).
  La lista vive dos veces y `scripts/check-community-filter.js` falla si se separan. Las
  **Normas de la comunidad** (`#community-rules-modal`, Perfil y pie del feed) son el contacto
  publicado que pide Apple, y se aceptan una vez antes de publicar (`ensureCommunityRules`)
- **Retos** (migración 129, `docs/RETOS.md`): `challenges` (un reto: título, el WOD escrito,
  `score_type` amrap / for_time / max_reps / max_load / max_time, fechas) y `challenge_entries`
  (**una marca por persona y reto**, que se corrige mientras esté abierto). Cualquier cuenta crea
  y registra, en HABIT y HABIT Crew, y se publica directo; el admin oculta (`status`) y marca
  oficial (`is_official`). Un trigger valida cada marca contra el tipo (las columnas ajenas van
  a null) y contra las fechas de Mazatlán (`challenge_is_open()`; "abierto" no se guarda); el
  lugar vive solo en la vista `challenge_standings` (`security_invoker`, empate → `scored_at`, que
  solo se mueve si cambia la marca), y `challenge_cards` da la fase y los participantes. Los
  nombres van **copiados en la fila** porque desde la 117 nadie lee perfiles ajenos. Registrar
  es insert y corregir update por id, no upsert (`challenge_id` no tiene permiso de update).
  Respeta los bloqueos de la 128 (restrictive) y se reporta por `community_reports.challenge_id`
  / `entry_id`; borrar desde el admin resuelve los reportes por trigger, sin endpoint.
  **En prueba: en HABIT solo lo ven `RETOS_HABIT_TEST_EMAILS`; en Crew, todos** (`retosEnabled()`).
  En la app es la pestaña Retos de Comunidad (`setCommunityTab`) y una sola hoja, `#reto-modal`,
  con tres modos en `retoOpen.mode` (detalle / proponer-editar / registrar marca); el admin
  modera abriendo el mismo reto. `COMMUNITY_ITEM_KINDS` nombra los cuatro tipos reportables.
  Fase 2 (migración 130): el orden vive en `challenge_sort_key()`, que usan la vista y el trigger
  `challenge_entry_notify` ("registró en tu reto" / "te pasó", en `user_notifications.challenge_id`;
  la app no puede insertar avisos `challenge_*`). El push lo manda la app tras guardar
  (`retoPushAfterScore`). Los retos nuevos salen en el feed (`loadFeedRetos`), los tuyos en Inicio
  (`renderInicioRetos`), y `openRetoTimer` es el cronómetro que llena «Registrar marca»
- `booking_guest_passes` — group session guest passes (from `group-guest-passes.sql`)
- `admin_notifs` — in-app notifications for admin
- `lift_competitions` / `lift_competitors` (migration 126) — **competencia de levantamiento**.
  Admin → Competencia captures each competitor's two attempts (kg + válido/nulo); `/competencia`
  (`competencia.html`) shows them on the TV. `best_kg` (best *valid* attempt) and `best_at` are set
  by a trigger, never by the client; `best_at` only moves when `best_kg` changes, and it is the
  tie-break (same kilos → whoever lifted it first). The ranking lives in **one** place, the
  `lift_competition_standings` view (`security_invoker`, `place` null until a valid attempt) — the
  admin and the TV both read `place` from it. RLS: anon may read only the competition with
  `on_screen = true` (a partial unique index allows one) and its competitors, so the TV needs no
  login; `?id=` previews any other one and needs an admin session; writes are admin-only. The TV
  listens on Realtime and re-reads every 15 s as a fallback. In the admin the list stays in capture
  order and a save **updates rows in place** (`syncCompetitionAdmin`, "por lugar" via CSS `order`):
  rebuilding the row the admin is already typing the next attempt into blurs it, and the browser
  then commits the half-typed number

**Skandi Fit tables** (all prefixed `skandi_`, migrations 040–073). They share `profiles` with HABIT
and nothing else:
- `skandi_exercises` — Skandi's own exercise catalog, separate from HABIT's `exercise_catalog`.
  `muscles` is a jsonb split (`{"Chest":60,"Triceps":25}`) summing to ~100, in the recovery engine's
  muscle names — that split is what `skandi-recovery.js` consumes
- `skandi_templates` / `skandi_template_items` — routines; `weekday` is only a suggested day and
  the fallback when no dated program is active. Since 102, `skandi_programs` +
  `skandi_program_days.week_index` own the cycle; 103 adds `skandi_program_weeks` phase metadata
  and stamps `program_id` / `program_week_index` onto calendar rows for cycle adherence
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
- `skandi_foods.user_id is null` is, since 073, the mechanism for a **global** food (visible to
  every crew member via the SELECT policy, no per-user seeding needed). Migration 093 uses exactly
  that to seed ~20 generic staples (chicken, rice, oats, tuna...) so no new member's catalog starts
  empty — `openAddMeal()`'s "Load starter catalog" button (`seedStarterCatalog()` in skandi.html,
  shown only when both dishes and owned foods are empty) then combines a few of those globals into
  a handful of starter `skandi_dishes` for whoever taps it, client-side, via `SkandiNutrition.
  scaleFood()`. Deliberately generic, not any one member's actual coaching plan: `skandi_dishes.
  user_id` has no global/shared concept (unlike `skandi_foods`), and a personal meal plan is a
  coach's content, not something to hardcode into a shared multi-user codebase — the starter set
  is real nutrition data any member can edit or delete like any other dish
- `skandi_supplements` / `skandi_supplement_logs` (093) — a daily check-off, not a dose log:
  `dose`/`timing` describe the member's own plan ("5 g", "en la noche"), and whether they actually
  took it that day is only the log row existing for that `(supplement_id, taken_on)`, never a
  second "how much did you really take" field. `SUPPLEMENT_PRESETS` in skandi.html offers generic,
  commonly-cited doses (creatine, omega-3, magnesium, whey, turmeric+pepper) as one-tap starting
  points when a member has none yet — general supplement-dosing facts, not anyone's personal stack
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
  carbs only. What counts as planned is **not** its business: the caller passes `plannedKcal` /
  `avgDaily`, and the one place they come from is the calendar — `sessionsForFuel(key, weightKg)`
  and `weeklyPlannedFromCalendar(weightKg)` in skandi.html, over `skandi_planned_sessions` (080).
  Asking `skandi_templates.weekday` instead (the old `plannedSessions`/`weeklyPlan`, removed) is
  blind to a special week: a deload or a trip lives only in the calendar, with `weekday = NULL` on
  its routines (086), which is exactly when the day's food should change. `fuelPlan()` turns the
  delta into timed advice (carbs before, during only for endurance over 75 min, carbs+protein
  after). A short easy session deliberately gets no pre-load — inventing one just pushes the
  member to eat more. The three consumers (`trainingDayCard`, `nutritionForBrief`,
  `loadMealSuggestion`) all read `targetsForDay(key)`, never `state.nutritionTargets`: with a
  per-date override (094) the coach already fixed the number, so `rec.delta` is forced to 0 rather
  than stacked on top, and `override.note` is the short why shown on the card
- `SkandiNutrition.suggestTargets()`'s protein target is **banded by mode**
  (`PROTEIN_G_PER_KG_BY_MODE = {deficit: 2.0, mantenimiento: 1.6, superavit: 1.8}`), not a flat
  2.0g/kg — a maintenance or surplus member doesn't need deficit-level protein, and flattening it
  overstated targets for two of the three modes. Bands follow Morton et al. 2018 and the ENFAF
  hybrid-training guide (1.4-1.6g/kg typical, up to 2.0-2.2g/kg in deficit or high training
  volume). `isLowEnergy(kcal, weightKg)` is a separate, deliberately conservative floor
  (`LOW_ENERGY_KCAL_PER_KG_FLOOR = 24`, referencing RED-S / Mountjoy et al. 2018) — it exists to
  catch a **manually-typed** kcal target low enough that not even the app's own worst-case
  deficit would suggest it (`saveTargets()` in skandi.html confirms before saving), not to flag
  the algorithm's own deficit output. An earlier attempt folded a `lowEnergyWarning` straight into
  `suggestTargets()`'s return using a 30kcal/kg floor; it fired on nearly every deficit-mode
  suggestion the app itself generates (a -15% deficit off a typical activity factor already sits
  ~29kcal/kg) and was removed before shipping
- Bodyweight (067) is best-effort, not enforced: a normal scale doesn't work at sea, so
  `latestWeightKg()` (used by `suggestTargets`, targets math, the "add to week" flows) can go
  stale for weeks. `weightNudgeHtml()` on Home surfaces a low-pressure reminder once the last log
  is 14+ days old (`WEIGHT_NUDGE_DAYS`) — never blocking, just a tap-through to
  `openLogBodyweight()`. Tape measurements and progress photos (090) are the mechanism that keeps
  working when the scale can't

### Time & Slots
All time logic uses **America/Mazatlan (UTC−7)**. The constant `MAZ_UTC_OFFSET_H = 7` converts UTC midnight to Mazatlán midnight. A day has 48 slots of 30 minutes. A typical booking is `slots_used = 3` (90 min). Access windows open 10 minutes before a booking's `start_idx`.

### Door Access: Two Paths
1. **Physical keypad** → `POST /api/validate-access-code` with `Authorization: Bearer ACCESS_API_SECRET`
2. **In-app button** → `POST /api/request-door-open` with Supabase JWT + GPS coords → Shelly Cloud API

### Native (Capacitor)
`capacitor.config.json` targets `app.habittraininghub.app`. The `ios/` and `www/` directories contain the Capacitor build output. The `www/` dir is generated from `app.html` — do not edit it directly.

### Garmin: la fuerza de HABIT en el reloj (`garmin_sync/`)
Correr y bici viajan al reloj por Intervals.icu (`intervals_import/`, plan JSON →
`/athlete/0/events/bulk`). **La fuerza no puede ir por ahí**: el exportador de Intervals a Garmin
ignora ejercicio, reps y peso, y descarta los pasos sin duración, así que al reloj llegan bloques
de tiempo ("Go 0:40") sin decir qué hacer (petición abierta en su foro desde sep 2026). Para que
el Venu 4 **inicie y siga** un entreno de fuerza —animación, cuenta de reps, peso por serie— el
workout tiene que nacer como workout de fuerza de Garmin Connect, y eso es `garmin_sync/`.

- `garmin_sync.py` lee la semana de HABIT y la escribe en Garmin: `ensure_coaching_week_from_template`
  para estampar lo que nadie ha abierto en la app, `coaching_schedule` + `boards.exercises` con la
  misma regla de `sessionExerciseList`, y `upload_strength_workout` + `schedule_workout` del lado
  de Garmin. **HABIT se lee como el socio**: la llave anon que ya vive en `app.html` más su propia
  sesión (refresh token en el Llavero, servicio `habit-supabase`); la RLS hace el resto y la
  service-role no entra aquí. Garmin no tiene API pública para personas: es
  `python-garminconnect` (API no oficial, tokens en `~/.garminconnect`) en un venv propio
  (`garmin_sync/.venv`, gitignored) con Python 3.13, porque la librería pide 3.12+.
- **Idempotente por contenido**: cada día lleva la firma de sus ejercicios en
  `~/.habit-garmin/state.json`; lo que no cambió se deja, lo que cambió en HABIT se vuelve a
  subir, y un día que pasó a descanso se borra de Garmin. Un cambio es **borrar y volver a
  subir**, no un PUT: actualizar exige reenviar los ids de cada paso y un desajuste deja el
  workout a medias. `done` y `skipped` no se tocan.
- Los objetivos se traducen como en la app: un rango vale su piso (`defaultRepsFromTarget`), una
  pirámide es un bloque de una serie por escalón, `20s` es serie de tiempo, sin descanso escrito
  90 s (0 en calentamiento y movilidad), y **"al fallo" termina con el botón de vuelta del reloj**
  (`lap.button`), no con una cuenta inventada.
- `exercise_map.json` traduce al catálogo de Garmin (1 527 ejercicios). **Una llave de dos
  palabras o más vale también dentro de un nombre más largo** —en HABIT los ejercicios se llaman
  como se hablan ("Flexiones de pino profundas en pared en paralelas")— y las de una sola palabra
  solo exactas: "flexiones" dentro de "flexiones de pino libre" apuntaría a la lagartija. Lo que
  no se encuentra cae a la categoría del patrón (`PATTERN_RULES`, portadas de
  `habit-training.js`), y el nombre de HABIT siempre viaja en la nota del paso.
- `./.venv/bin/python check_garmin_sync.py` prueba sin red que cada par categoría/ejercicio del
  mapa exista de verdad en Garmin y que cada forma de objetivo arme los pasos correctos.
- **Lo automático no corre desde el repo**: macOS protege `~/Downloads` y a un agente de launchd
  le niega hasta ejecutar un archivo que viva ahí (`Operation not permitted`), aunque la Terminal
  sí pueda. Por eso `habit-garmin instalar` copia el programa a `~/.habit-garmin/app/` con su
  propio entorno y un `config.json` (la URL y la llave anon, que de otro modo salen de leer
  `app.html`), y escribe y carga el agente apuntando ahí. El repo sigue siendo el original:
  cambiar `garmin_sync.py` o `exercise_map.json` **pide volver a correr `instalar`**.

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

## Fuerza independiente del reloj (20261101-8)

`skandi-intervals.js` también importa fuerza Garmin sin una sesión previa. Se guarda como
`activity_type=other` y `external_type=WeightTraining` (o su tipo real), y `habit-activity.js` la
clasifica como Fuerza. No volver a descartar esa fuerza: iniciar HABIT no es requisito. Primero
se enlaza con Skandi si hay pareja; los ids enlazados se excluyen de la importación y al enlazar
se elimina su copia externa para no sumar dos veces. `scripts/check-intervals.js` prueba el flujo
del endpoint con dependencias en memoria. Apple Salud sigue siendo una propuesta para iOS,
no una integración disponible desde la PWA.

## Stickers semanales por disciplina (20261101-10)

`HabitActivity.weekSummary` agrega disciplinas desde la lista conciliada y las pasa a
`HabitShare.open`. Los campos `discipline:run`, `discipline:strength`, etc. son independientes
de los totales. `normalizeDisciplines` no inventa un desglose a partir de sumas generales.
Los estilos This Week, Mix, Pasaporte y Tipográfico se añaden a los anteriores; estos también
usan `disciplineBlock`. Conservar los pictogramas vectoriales (`sport`) y la medición de
texto expandido (`scaleX`) al modificar el renderer.

## Referencias Aura y detalle semanal (20261101-11)

Diario, Notas, Barras, Tabla e Impacto se añaden a los diseños anteriores. `weekSummary.sessions`
contiene las sesiones ya conciliadas de la semana sin títulos privados. No crear series diarias
desde totales. Los campos `sessions`/`daily` controlan listas y distribución por día. Gráficas
de km y de minutos van separadas. Los textos nuevos usan `WEEK_REFERENCE_COPY` (ES/EN);
`open({lang})` determina la exportación, sin equivaler todavía a traducir toda la aplicación.
