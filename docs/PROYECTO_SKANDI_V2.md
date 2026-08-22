# Proyecto Skandi Fit v2 — "Del registro a las decisiones"

> Documento de planeación. Fecha: 2026-08-22. Dueño: Joseph.
> Este archivo es la fuente de verdad del proyecto: se actualiza conforme avanzan las fases.
> Para la estructura del entrenamiento (calendario, periodización, triatlón, HIIT) ver
> `PLAN_ENTRENAMIENTO_SKANDI.md`, que absorbe y amplía lo que aquí era la Fase 3.

---

## 1. El problema

Skandi Fit hoy **registra bien** y **decide poco**. Sabes qué hiciste; no sabes qué hacer.
Además hay una mitad de la ecuación que simplemente no existe en la app: lo que comes. Sin
ingesta calórica, ningún consejo sobre fuerza, carrera o recuperación puede ser honesto —
un estancamiento en press de banca y un estancamiento por comer 1,600 kcal se ven idénticos
en los datos actuales.

**Objetivo v2:** que la app conteste tres preguntas cada mañana, con datos, no con vibras:

1. ¿Qué entreno hoy y con cuánta intensidad?
2. ¿Voy bien de comida para lo que estoy entrenando?
3. ¿Qué está funcionando y qué llevo semanas repitiendo sin resultado?

---

## 2. Punto de partida real (auditoría del repo)

Lo que **ya existe** y no hay que reconstruir:

| Pieza | Dónde | Estado |
|---|---|---|
| Catálogo de ejercicios + media (GIF/MP4) | `skandi_exercises`, migraciones 037/041/044/058/071 | Sólido |
| Rutinas, semana, programas | `skandi_templates`, `skandi_program*` (069) | Sólido |
| Sesiones y series con RIR | `skandi_sessions`, `skandi_sets` (040, 064) | Sólido |
| Motor de fatiga muscular | `skandi-recovery.js` — decaimiento exponencial por músculo | Sólido, y es la joya del proyecto |
| Figura corporal 11 regiones | `body-figure.js` | Sólido |
| Actividades externas (correr, bici, **nadar**, remo, caminar) | `skandi_external_activities` (046) + FC y plan (063) | Existe, captura pobre |
| Planes de cardio recurrentes ("miércoles 5 km Z2") | `skandi_activity_templates` (063) | Existe, poco explotado |
| Bloques de carga + descarga | `skandi_training_blocks` (066) | Existe |
| Peso corporal | `skandi_bodyweight_logs` (067) | Existe |
| Alertas de estancamiento y dolor repetido | `progressionStallWarnings()`, `repeatedSorenessWarnings()` | Existe, aislado |

Lo que **no existe**:

- ❌ Nutrición. Ni una tabla, ni un campo, ni una pantalla.
- ❌ HIIT como tipo de actividad (hoy caería en `other`, que fatiga "Core 40 / Hombros 20 / Cuádriceps 20 / Pecho 20" — es decir, mal).
- ❌ Detalle de las actividades: no hay splits de carrera, ni largos/estilo de nado, ni rondas de intervalos.
- ❌ Cualquier integración de IA. No hay `ANTHROPIC_API_KEY` ni ningún endpoint que hable con un modelo.
- ❌ Un único puntaje que junte fuerza + cardio + comida + descanso.
- ❌ PWA: `skandi.html` no tiene `manifest`, ni service worker, ni `APP_VERSION`. Es una página web suelta — no se instala y no funciona sin señal.

**Deuda técnica a vigilar:** `skandi.html` son 4,448 líneas / 274 KB en un solo archivo. Ya existe
el patrón correcto para crecer sin reventarlo (`skandi-recovery.js` y `body-figure.js` son módulos
puros, sin DOM ni Supabase, cargados por `<script>`). Toda la lógica nueva de este proyecto sigue
ese patrón: **matemáticas en su propio archivo, UI en `skandi.html`**.

También: `CLAUDE.md` no menciona Skandi Fit. Hay que arreglarlo (tarea de Fase 0).

---

## 3. Decisiones ya tomadas

| Decisión | Elección | Consecuencia |
|---|---|---|
| Análisis de comida | **Claude Vision + catálogo propio** | Endpoint nuevo `api/analyze-meal.js`; lo que corriges se guarda en `skandi_foods` y la próxima vez es instantáneo y gratis |
| Datos de cardio | **Garmin vía Strava** (ver §3.1) | OAuth de Strava + webhook en Fase 4; captura manual mejorada desde Fase 3 |
| Alcance | **Solo Joseph primero** | Nutrición privada por RLS estricta; feature-flag para abrir al crew después |
| Prioridad | **Nutrición con foto primero** | Fase 1 = comida; el motor de decisiones (Fase 2) ya nace con ese dato |

### 3.1 Garmin: la respuesta corta es no (directo)

Investigado hoy: el **Garmin Connect Developer Program exige una entidad legal y rechaza
explícitamente las solicitudes de uso personal** ("quiero mis propios datos" es causal de rechazo),
y además en 2026 las altas nuevas están en pausa, sin formulario público ni fecha de reapertura.
No hay atajo self-service.

**La ruta que sí funciona, y es de un solo switch:** Garmin Connect ya sincroniza automáticamente
a Strava (Strava lee de la API de Garmin; se activa desde Strava → *Connect an App or Device* →
*Garmin*). Nosotros integramos **Strava**, y tu reloj sigue siendo la fuente. Es sincronización de
una vía (Garmin → Strava), que es exactamente lo que necesitamos.

**Plan B si Strava estorba:** Garmin Connect exporta `.FIT`/`.TCX`; un importador de archivos en la
app cubre el caso sin depender de nadie. Queda como opción de respaldo, no como camino principal.

---

## 4. Arquitectura objetivo

```
skandi.html                 UI (tabs: Home · Entrenar · Comida · Progreso · Cuerpo · Crew · Librería)
├── skandi-recovery.js      [existe]  fatiga muscular por músculo
├── body-figure.js          [existe]  figura corporal SVG
├── skandi-nutrition.js     [nuevo]   TDEE, metas, macros, sumas del día  — matemáticas puras
└── skandi-load.js          [nuevo]   carga aguda/crónica, readiness diario — matemáticas puras

api/
├── analyze-meal.js         [hecho]   foto y/o texto → Claude Vision → JSON de alimentos
├── lookup-barcode.js       [hecho]   código de barras → Open Food Facts → alimento (sin IA)
└── (Strava)                [hecho]   NO son archivos: son seis acciones dentro de skandi.js
                                      (connect · callback · webhook · sync · disconnect ·
                                      subscription). El techo de 12 funciones no daba para
                                      un archivo nuevo; las dos rutas que Strava necesita
                                      con URL fija salen de rewrites en vercel.json

migrations/073..078         nutrición, HIIT, detalle de actividades, check-in diario, integraciones
```

**Regla de oro:** `skandi-nutrition.js` y `skandi-load.js` no importan Supabase ni tocan el DOM.
Reciben arreglos de filas y devuelven números. Se prueban con
`node -e "const N=require('./skandi-nutrition.js'); ..."` igual que el motor de recuperación.

---

## 5. Modelo de datos

### Migración 073 — Nutrición (Fase 1)

```
skandi_foods              catálogo personal + global
  id, user_id (null = global), name, brand, barcode,
  serving_label ('1 taza', '1 pieza'), serving_grams,
  kcal_100g, protein_100g, carbs_100g, fat_100g, fiber_100g,
  source ('ai'|'manual'|'off'), times_used, created_at
  RLS: select where user_id is null or user_id = auth.uid(); write solo propios

skandi_meals              una comida = una foto (o entrada manual)
  id, user_id, eaten_at, meal_type ('desayuno'|'comida'|'cena'|'snack'),
  photo_path, note,
  kcal, protein_g, carbs_g, fat_g,          -- totales cacheados (trigger)
  analysis_status ('pending'|'ready'|'failed'|'manual'), ai_confidence,
  created_at
  RLS: solo el dueño. Sin visibility 'crew' — la comida no entra al feed.

skandi_meal_items         renglones editables de esa comida
  id, meal_id, user_id, food_id (nullable), label, grams,
  kcal, protein_g, carbs_g, fat_g,          -- absolutos, ya multiplicados
  source ('ai'|'manual'|'catalog'), ai_confidence, sort_order

skandi_nutrition_targets  una fila por usuario
  user_id (PK), mode ('deficit'|'mantenimiento'|'superavit'),
  kcal_target, protein_g_target, carbs_g_target, fat_g_target,
  activity_factor, auto (bool: recalcular solo con el peso), updated_at

skandi_ai_usage           tope de gasto
  user_id, day (date), calls int, PK (user_id, day)
```

Detalles que importan:

- **Los macros del renglón se guardan absolutos**, no por 100 g. Editar "eran 150 g, no 200 g"
  recalcula en el cliente y guarda el resultado. Así una comida vieja no cambia si mañana corriges
  el alimento del catálogo — el histórico es inmutable, que es lo correcto para un diario.
- **Un trigger recalcula los totales de `skandi_meals`** en cada insert/update/delete de items. La
  app nunca escribe totales a mano; ese fue el bug clásico de todos los diarios de comida.
- **Bucket `skandi-meals` PRIVADO**, carpeta por `user_id/`, acceso con signed URL. Ojo: el bucket
  de ejercicios (`skandi-exercise-media`, migración 058) es público a propósito; este **no** debe
  serlo, y no se copia esa policy.

### Migración 076 — HIIT y detalle de actividades (Fase 3)

- Ampliar el `check` de `activity_type` en `skandi_external_activities` y
  `skandi_activity_templates`: agregar `'hiit'` y `'strength_class'`.
- Columnas nuevas en `skandi_external_activities`:
  `rounds`, `work_sec`, `rest_sec` (intervalos), `elevation_m`, `splits jsonb` (parciales por km),
  `pool_length_m`, `stroke` (estilo de nado), `perceived_effort_after` (RPE de sesión de Foster).
- `ACTIVITY_MUSCLE_MAP` en `skandi-recovery.js` gana `hiit` (reparto realista: cuádriceps/glúteos/
  core/hombros según el patrón dominante) — sin esto, un HIIT de 20 min miente en la figura corporal.

### Migración 077 — Check-in diario (Fase 2)

```
skandi_daily_checkin
  user_id, day (date), PK (user_id, day),
  sleep_hours, sleep_quality (1-5), stress (1-5), resting_hr,
  soreness_note, energy (1-5), created_at
```

Complementa (no duplica) los `report_*` de `skandi_sessions`, que solo existen los días que entrenas.

### Migración 078 — Integraciones (Fase 4)

```
skandi_integrations
  user_id, provider ('strava'), access_token, refresh_token, expires_at,
  athlete_id, scope, connected_at, last_sync_at, last_error
  RLS: activa y SIN NINGUNA POLÍTICA = niega todo. Solo la service-role la toca.
  unique (provider, athlete_id): un atleta de Strava, un solo miembro.
  El cliente pregunta por skandi_strava_status(), que nunca devuelve tokens.

skandi_external_activities += external_source, external_id, external_type,
  elevation_gain_m, max_heart_rate, calories, intensity_source
  unique (user_id, external_source, external_id) — NO parcial: un índice parcial no
  puede arbitrar un ON CONFLICT que no repita su predicado.

skandi_settings
  user_id, max_heart_rate. Fuera de `profiles` a propósito: profiles lo lee cualquier
  usuario autenticado del gimnasio, y esto es un dato de salud.
```

**Se quedó en 081, no en 078:** la numeración del roadmap se escribió antes de las migraciones
073-080. La de Strava es `081_skandi_strava.sql`.

---

## 6. Fases

| Fase | Qué entrega | Migraciones | Tamaño |
|---|---|---|---|
| **0** | ✅ **Hecha** (2026-08-22) — `CLAUDE.md` documenta Skandi, `SKANDI_VERSION` + manifest + iconos + service worker: instalable y con shell offline propio | — | — |
| **1** | **Nutrición: foto, texto, código de barras** — registrar, analizar, corregir, metas, resumen del día | 073 ✅ · 074 ✅ · 075 | 3–4 sesiones |
| **2** | **Motor de decisiones** — readiness diario, ACWR, balance energético, recomendación en Home | 077 | 2–3 sesiones |
| **3** | **Cardio y HIIT de primera clase** — intervalos, splits, nado, mapa muscular correcto | 076 | 2 sesiones |
| **4** | ✅ **Strava (Garmin vía Strava)** — OAuth, webhook, deduplicación, backfill | 081 ✅ | hecha |
| **5** | **Pulido analítico** — tendencias, correlaciones, exportar CSV, apertura al crew | 079+ | continuo |

El orden 1 → 2 no es negociable: el motor de decisiones sin datos de comida da consejos ciegos.
El 3 puede adelantarse si te urge capturar bien un bloque de carreras antes que la comida.

---

## 7. Fase 1 en detalle — Nutrición con foto

### 7.1 Las cuatro maneras de registrar

Ninguna comida se registra igual. El diseño acepta cuatro entradas y las tres primeras acaban en
la misma pantalla de renglones editables:

| Entrada | Cuándo | Qué pasa | Costo |
|---|---|---|---|
| **Foto** | Plato servido enfrente | `analyze-meal` con vision | ~2-3 ¢ |
| **Foto + contexto** | Cuando la cámara no alcanza: "lleva crema", "es mitad porción" | Igual, y **el texto manda sobre lo que el modelo cree ver** | ~2-3 ¢ |
| **Solo texto** | Comiste sin foto: "dos huevos con frijoles y una tortilla" | `analyze-meal` sin imagen | ~1 ¢ |
| **Código de barras** | Producto empaquetado | `lookup-barcode` → Open Food Facts → tú eliges la porción | **0** |

El código de barras no pasa por la IA a propósito: un empaque ya trae sus macros impresos, y pagar
por adivinar un dato que existe es tirar dinero. Lo que el escaneo **no** sabe es cuánto te
serviste — por eso el endpoint devuelve los macros por 100 g y la porción del empaque, y la app te
pregunta la cantidad.

### 7.1.0 La regla de oro: la IA es el último recurso

La comida real se repite. El mismo desayuno cuatro veces por semana, el mismo pollo con arroz de
la tarde. Volver a mandarle esa foto al modelo cada vez es pagar por una respuesta que ya tenemos
—y peor, es tirar las correcciones que hiciste a mano la primera vez, porque una estimación nueva
no las recuerda.

Por eso la app ofrece **tres niveles, en este orden**, y sólo baja al siguiente si el anterior no
aplica:

| Nivel | Qué es | Costo | Funciona sin señal |
|---|---|---|---|
| 1. **Platillo guardado** | "Avena de la mañana" → copiar y escalar la porción | **0 tokens** | Sí |
| 2. **Alimento del catálogo** | "180 g de pechuga" → una multiplicación, no un modelo | **0 tokens** | Sí |
| 3. **Foto o descripción** | Algo que no habías comido antes | ~1-3 ¢ | No |

El truco está en **cuándo** se guarda el platillo: **después de corregirlo**. El snapshot no es lo
que la IA adivinó, es lo que tú dejaste bien — incluida tu decisión sobre el aceite. A las tres
semanas de uso, la mayoría de tus comidas deberían entrar por el nivel 1 o 2, y la IA quedar para
los restaurantes nuevos.

`skandi_quick_picks` (vista, migración 076) es una sola consulta que devuelve platillos y alimentos
ordenados por uso: es la lista que la app enseña al abrir el tab, antes de encender la cámara.

**Decisión deliberada:** no le mandamos los platillos guardados al modelo para que él los
reconozca. Eso engordaría cada prompt para ahorrar sólo en los casos donde de todas formas no
hacía falta llamarlo. El ahorro está en **no llamarlo**, no en llamarlo mejor informado.

### 7.1.1 El aceite es una palomita, no una suposición

Cocinando en casa no usas aceite; en restaurante no lo controlas. Un estimador que siempre asume
grasa de cocción te miente en casa, y uno que nunca la asume te miente en la calle. La solución no
es adivinar mejor, es **hacerlo visible y reversible**:

- El modelo devuelve la grasa de cocción **siempre como su propio renglón** (`is_cooking_fat`),
  nunca sumada dentro del guisado. Los demás renglones llevan solo la grasa propia del alimento
  (la del aguacate, la de la carne), jamás la del sartén.
- Cada comida se marca con un **lugar** (`venue`): casa, restaurante, fonda. Eso decide dos cosas:
  cuánta grasa estima el modelo, y si el renglón llega **palomeado o no**. En casa llega apagado;
  en restaurante, encendido.
- Quitar la palomita **no borra el renglón**: `included = false` lo saca de la suma pero lo
  conserva, así lo puedes volver a prender. Un diario donde "quitar" destruye el dato no deja
  corregirse, y el aceite es justo el renglón que se prende y se apaga.

### 7.1.2 El flujo de la foto

```
1. Tocas "+" en el tab Comida  →  cámara / galería
2. La foto se comprime en el cliente (canvas, lado largo 1024 px, JPEG q0.8, ~150 KB)
3. Sube a Supabase Storage: skandi-meals/{user_id}/{uuid}.jpg  (privado)
4. Se crea skandi_meals con analysis_status='pending' → la UI ya muestra la tarjeta
5. POST /api/analyze-meal { meal_id }  con el JWT de Supabase
6. El endpoint: valida JWT → verifica dueño de la comida → cuota diaria →
   descarga la foto con service-role → Claude Opus 5 con vision →
   escribe skandi_meal_items → status='ready'
7. La UI hace polling ligero (o realtime) y pinta los renglones con su nivel de confianza
8. Tú corriges gramos o nombres; al guardar, cada corrección se vuelve/actualiza un skandi_foods
9. La próxima vez que aparezca ese platillo, el prompt ya lo incluye como referencia → mejor tino
```

**Por qué la foto se sube primero y el análisis va después:** si el modelo tarda 6 segundos o falla,
la comida ya quedó registrada. Un diario de comida que pierde entradas por un timeout no se usa
dos semanas. `analysis_status='failed'` deja reintentar sin perder nada, y siempre existe la
salida manual.

### 7.2 El endpoint `api/analyze-meal.js`

Patrón de auth idéntico al que ya usa `api/request-door-open.js`:

```js
const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '').trim();
const { data: authData, error } = await supabase.auth.getUser(token);
```

Llamada al modelo (SDK oficial `@anthropic-ai/sdk`, nueva dependencia):

- **Modelo:** `claude-opus-5`.
- **Salida estructurada:** `output_config: { format: {...} }` con JSON Schema estricto, no
  "pídele que responda JSON y crucemos los dedos". Cada item trae
  `label, grams, kcal, protein_g, carbs_g, fat_g, confidence (0-1), catalog_match_id|null`.
- **Esfuerzo:** `output_config.effort: "low"` — estimar comida no requiere razonamiento profundo,
  y baja el costo. Thinking se queda en adaptativo (el default de Opus 5); **no** desactivarlo.
- **Prompt caching:** el system prompt + tus 50 alimentos más usados van al frente con
  `cache_control: {type:'ephemeral'}`. Es el bloque estable; la foto va después. Baja ~40% el costo.
- **Contexto mexicano en el prompt:** tacos, guisados, tortillas, porciones de casa. Un modelo sin
  ese contexto estima en tazas y onzas y falla en la comida real de Mazatlán.
- **Devuelve rangos, no falsa precisión:** si el modelo no ve el aceite del sartén, que lo diga.
  La confianza por renglón se pinta en la UI y es lo que te dice qué corregir.

**Variables de entorno nuevas en Vercel:** `ANTHROPIC_API_KEY` (server-side; jamás en `skandi.html`),
`MEAL_AI_DAILY_LIMIT` (default 25) y `MEAL_AI_MODEL` (default `claude-opus-5`, para poder comparar
modelos midiendo en vez de adivinando). `maxDuration: 60` ya quedó declarado en `vercel.json`.

### 7.3 Costo real

Con Opus 5 ($5 / $25 por millón de tokens): una foto de 1024 px ≈ 1.1k tokens de entrada, el prompt
con catálogo ≈ 1.5k, la respuesta ≈ 600 tokens. **≈ 2–3 centavos de dólar por foto**, y ≈ 2 centavos
con el caché activo. Cuatro fotos al día ≈ **$2.50–3.50 USD al mes**. El tope de 25 llamadas diarias
existe para que un bug en un `useEffect` no te cueste $50 en una noche, no porque el uso normal
se acerque.

Si en la práctica el tino de Opus 5 resulta idéntico al de Sonnet 5 en tus platillos, bajar el
modelo corta el costo a la mitad — pero eso se decide **midiendo**, no de entrada.

### 7.4 La UI (tab nuevo "Comida")

- **Arriba:** anillo de kcal del día (consumidas / meta) + tres barras de macros. Verde no significa
  "poco", significa "en tu rango".
- **En medio:** lista de comidas del día, cada una con su foto miniatura, kcal y hora.
- **Abajo:** botón grande de cámara. Un tap desde la pantalla principal a la foto — si toma tres
  taps, no lo vas a usar en un restaurante.
- **Metas:** calculadas de tu peso más reciente (Mifflin-St Jeor × factor de actividad, ajustado por
  el modo déficit/mantenimiento/superávit), editables a mano. Se recalculan solas cuando registras
  peso nuevo, si dejaste `auto = true`.
- **Historia:** las últimas 4 semanas con promedio semanal de kcal y proteína, que es la única
  escala en la que la comida se interpreta honestamente.

### 7.5 Definición de "terminado" para la Fase 1

- [x] Migración 073 corrida en Supabase (falta verificar RLS con un segundo usuario de prueba)
- [ ] Bucket privado + signed URLs funcionando (una foto no debe abrirse sin sesión)
- [ ] Foto → renglones editables en menos de 10 segundos, con fallback manual si falla
- [ ] Corregir un renglón crea/actualiza el alimento en `skandi_foods`
- [ ] El día suma correcto y la meta se calcula del peso real
- [ ] `npm run check` pasa con el endpoint nuevo
- [ ] Tope diario probado (llamada 26 devuelve error claro, no 500)

---

## 8. Fase 2 en detalle — El motor de decisiones

`skandi-load.js`, matemáticas puras, cuatro entradas y una salida:

| Entrada | De dónde | Cómo se mide |
|---|---|---|
| Carga de fuerza | `skandi_sets` | Unidades de estímulo (SU) que ya calcula `skandi-recovery.js` |
| Carga de cardio/HIIT | `skandi_external_activities` | sRPE de Foster: `minutos × RPE` = unidades arbitrarias |
| Recuperación | motor de fatiga + `skandi_daily_checkin` | frescura por músculo, sueño, estrés, FC en reposo |
| Balance energético | `skandi_meals` + peso + actividad | kcal in vs. TDEE estimado |

Salidas:

- **ACWR** (carga aguda 7 días ÷ crónica 28 días). Debajo de 0.8 estás desentrenando; arriba de 1.5
  es zona de lesión. Es la métrica que evita que "me siento bien" te meta en un pico de 40%.
- **Readiness diario (0–100)** y, más importante, **una frase**: "hoy sí pega piernas fuerte",
  "hoy Z2 suave, llevas 3 días con el ACWR alto y dormiste 5 h", "si vas a correr 10 km hoy, comiste
  400 kcal de menos ayer".
- **Recap semanal accionable**: qué subió, qué lleva 3 semanas plano, y si el estancamiento coincide
  con déficit calórico — la correlación que hoy es imposible de ver.

Se pinta como **una sola tarjeta en Home**. El objetivo no es un dashboard más; es una frase al día.

---

## 9. Riesgos y decisiones abiertas

| Riesgo | Mitigación |
|---|---|
| El tino de la IA en comida casera es mediocre al principio | El catálogo personal es el mecanismo de aprendizaje. Medir el error los primeros 30 días contra pesaje real de 10 platillos frecuentes |
| `skandi.html` sigue engordando | Toda la matemática nueva sale a módulos; si la UI de Comida pasa de ~600 líneas, se extrae también |
| Strava puede caducar el token sin avisar | Refresh proactivo + banner de "reconecta Strava" cuando el webhook falle 2 veces |
| Registrar comida es un hábito difícil | La foto ES el registro. Si el flujo pide más de 2 taps antes de la foto, está mal diseñado |
| Costo de IA descontrolado | Tope diario en BD, no en el cliente |

**Decisiones abiertas** (no bloquean la Fase 1):

1. ¿Códigos de barras para productos empaquetados (Open Food Facts) en Fase 5? Cero costo de IA y
   datos exactos para suplementos y barritas.
2. ¿La comida entra alguna vez al feed del crew? Por default, no.
3. ¿Recordatorios push si no registraste comida a las 3 pm? Existe infraestructura de push en HABIT
   (migración 010) pero Skandi no la usa todavía.

---

## 10. Convenciones de trabajo

- Migraciones numeradas y en orden, corridas a mano en el SQL Editor de Supabase. La siguiente es la **074**.
- **Una sola cadena de versión para todo el proyecto** (hoy `20260822-01`): un service worker sirve las
  dos apps, así que tocar Skandi obliga a bumpear también `APP_VERSION` de HABIT. Los siete lugares:
  `app.html` (`APP_VERSION` + `<link>`/`<script>`), `skandi.html` (`SKANDI_VERSION` + `<head>`),
  `sw.js` (`CACHE_VERSION`), `index.html`, `manifest.json` y `skandi-manifest.json`.
- Cada migración empieza con un comentario que explica **por qué** existe, como las 072 anteriores.
- `npm run check` antes de cada push (valida sintaxis de `api/*.js` y `sw.js`).
- Deploy = push a git; Vercel publica solo.
- Los módulos puros se prueban desde Node, sin navegador.
- Al terminar cada fase: actualizar este documento y `CLAUDE.md`.

---

## 11. Bitácora

**2026-08-22 — Fase 0 cerrada y migración 073 escrita.**

Fase 0:
- `CLAUDE.md` ahora documenta que el repo publica **dos** front-ends del mismo proyecto de Vercel y
  la misma base: HABIT (`/`) y Skandi Fit (`/skandi`). Incluye las tablas `skandi_*` y la convención
  de versión compartida.
- Skandi Fit es instalable: `skandi-manifest.json`, iconos (`icons/skandi-{180,192,512}.png`,
  generados del logo DOF sobre navy #012456, dentro de la zona segura de un icono maskable), metas
  de `apple-mobile-web-app-*` y `SKANDI_VERSION`.
- Service worker: **no** se creó uno nuevo. Dos service workers en la raíz comparten alcance `/` y
  se desalojan entre sí, así que Skandi registra el mismo `/sw.js` y este aprendió a distinguir las
  dos apps (`shellFor()`). Efecto secundario: se corrigió un bug real que ya existía — abrir
  `/skandi` sin señal servía el shell de HABIT, es decir, la app equivocada.
- El handler de navegación ahora **refresca el shell cacheado** con cada respuesta buena de la red.
  Antes la copia offline se congelaba en la versión del último `install` y podía servir HTML de
  semanas atrás.
- Verificado en navegador: SW activo y controlando, caché con los dos shells, y con el servidor
  apagado `/skandi` sirve Skandi y `/app.html` sirve HABIT.

Migración 073 (`migrations/073_skandi_nutrition.sql`): **corrida en Supabase.** Incluye catálogo de
alimentos, comidas, renglones, metas, cuota de IA, trigger de totales, RLS, bucket privado
`skandi-meals` y el RPC transaccional `skandi_save_meal_items`.

**2026-08-22 — `api/analyze-meal.js` escrito.**

- Modelo `claude-opus-5` con vision y **salida estructurada por JSON Schema**
  (`output_config.format`), no "pídele JSON y cruza los dedos". `effort: 'low'` porque estimar una
  porción no necesita razonamiento profundo; el thinking adaptativo se queda encendido.
- El prompt lleva contexto mexicano explícito (tortilla de maíz ≈ 30 g, plato estándar 26 cm,
  fondas, guisados) y una instrucción que resultó ser la más importante: **contar el aceite de
  cocción aunque no se vea**. Es el error más caro en cualquier estimación por foto.
- Caché de prompt: system + catálogo son el prefijo estable entre comidas del mismo usuario, la
  foto va después. El `cache_control` va en el último bloque estable.
- Migración **074** nueva (`074_skandi_ai_quota_rpc.sql`): el conteo de cuota que la 073 dejaba
  implícito tenía una carrera (leer-sumar-escribir deja rebasar el tope con dos fotos casi
  simultáneas). Ahora es un `insert ... on conflict do update where calls < limite returning`, y
  hay un RPC de reembolso para no cobrarle al usuario una llamada que falló por nuestra culpa.
- Validaciones antes de gastar un token: dueño de la comida, cuota, formato de imagen soportado
  (HEIC no lo acepta la API de vision), tamaño < 4.5 MB.
- Los `catalog_id` que devuelve el modelo se verifican contra el catálogo que le mandamos: un id
  inventado rompería la llave foránea y tiraría el insert completo.
- Probado: rutas de guarda (405, 500 sin API key, 401 sin sesión, orden de validaciones).
  **La llamada real al modelo no está probada** — no hay `ANTHROPIC_API_KEY` en el entorno local.

**2026-08-22 — Entradas de texto y código de barras, y el aceite como palomita.**

- `analyze-meal` acepta ahora **foto, texto, o las dos**. Con las dos, la instrucción explícita es
  que la descripción manda sobre lo que el modelo cree ver: la cámara no distingue si el guisado
  lleva crema, tú sí. Sin foto el costo baja a ~1 ¢ porque la imagen es la mitad de los tokens.
- **El aceite dejó de ser una suposición.** Va siempre en su propio renglón `is_cooking_fat`, nunca
  sumado dentro del guisado, y `venue` (casa / restaurante / fonda) decide cuánto estima el modelo
  y si llega palomeado. Quitar la palomita no borra: `included=false` lo saca de la suma y lo
  conserva (migración 075, y el trigger de totales ahora suma solo lo incluido).
- `api/lookup-barcode.js`: código de barras → Open Food Facts → alimento guardado en `skandi_foods`.
  **Sin IA y sin cuota** — un empaque ya trae sus macros impresos. Lo que el escaneo no sabe es
  cuánto te serviste, así que devuelve macros por 100 g + porción del empaque y la app pregunta la
  cantidad. La segunda vez que escanees el mismo producto ni siquiera sale a internet.
- Probado contra la API real de Open Food Facts con cuatro productos (incluido Gamesa, mexicano):
  el parseo de kcal (con respaldo de kJ→kcal), marca y porción funciona, y un producto ausente
  devuelve el mensaje correcto en vez de un 500.

**2026-08-22 — Platillos guardados: que la IA deje de hacer falta.**

Migración 076. Tres RPC y una vista, cero cambios en el endpoint — porque el ahorro no está en
llamar mejor al modelo, está en no llamarlo:

- `skandi_save_meal_as_dish(meal_id, nombre)` — congela una comida **ya corregida** como platillo
  reutilizable, con el estado de cada palomita. Re-guardar con el mismo nombre actualiza la receta
  en vez de duplicarla.
- `skandi_create_meal_from_dish(dish_id, tipo, escala, cuándo, nota)` — registra el platillo
  escalando todo por un factor (0.5 = media porción, 2 = doble). Una transacción, cero tokens,
  funciona sin señal.
- `skandi_add_food_to_meal(meal_id, food_id, gramos)` — "180 g de pechuga" es una multiplicación,
  no un problema de visión artificial.
- Vista `skandi_quick_picks` — platillos y alimentos ordenados por uso, para enseñarlos antes de
  abrir la cámara. Hereda la RLS de las tablas base vía `security_invoker`.
- `skandi_meals.dish_id` / `dish_scale` guardan de qué platillo salió cada comida: con eso se puede
  medir después qué tanto repites y cuánto te ahorró.

**Herramienta nueva: `npm run check:sql`.** Las migraciones se pegan a mano en el SQL Editor, donde
un error de sintaxis te deja media migración aplicada. El script parsea cada archivo con
libpg_query —el parser del propio PostgreSQL (17.7)— incluidos los cuerpos plpgsql, que el parser
SQL trata como cadenas opacas. Las 78 migraciones del repo pasan.

**2026-08-22 — El tab Comida, y la Fase 1 queda funcional.**

- `skandi-nutrition.js`: metas, sumas del día, escalado de porciones y la conversión de un
  renglón corregido a alimento del catálogo. Módulo puro, probado desde Node.
- **La meta calórica NO usa Mifflin-St Jeor.** Mifflin pide estatura, edad y sexo: tres datos que
  la app no tiene y que habría que pedir en un formulario antes de dejarte registrar tu primera
  comida. Usamos una estimación por peso corporal (`peso × 22 × factor de actividad`), que es menos
  precisa en el papel y prácticamente igual de útil, porque una meta calórica no se acierta de
  entrada: se ajusta contra la tendencia del peso a las 2-3 semanas. Siempre es editable a mano.
- El tab pinta el anillo de kcal restantes, las tres barras de macros, las comidas del día y la
  fila de "repetir algo". El selector de alta ordena las opciones por costo, con el precio a la
  vista: gratis arriba, IA abajo.
- Corregir los gramos de un renglón lo **reescala conservando su densidad** (el modelo acertó qué
  era, se equivocó en cuánto) y guarda la corrección como alimento del catálogo. Ese es el
  mecanismo por el que la app deja de necesitar IA con el uso.
- Escáner de código de barras con `BarcodeDetector` donde exista; donde no, el número a mano.
  Sin permiso de cámara no hay error: el camino manual siempre está ahí.
- **El nav pasó de 6 a 7 pestañas.** Para que las etiquetas no se cortaran a 375 px hubo que
  acortar dos en español: "Tripulación" → "Crew" y "Biblioteca" → "Catálogo". Verificado en
  navegador: las siete caben sin elipsis.
- Verificado con estado simulado en el navegador a 375 px: la vista y los siete modales renderizan
  sin errores de consola, la sugerencia de metas da 2320/160/265/70 para 80 kg en déficit, y la
  porción de 180 g de pechuga da 297 kcal — el mismo número que el módulo en Node.

**Lo que sigue sin probarse:** la llamada real al modelo. Todo el camino hasta `fetch` está
ejercitado, pero la respuesta del endpoint solo se habrá visto de verdad con la primera foto en
producción.

**2026-08-22 — Azúcar como macro propio, y la comida que depende de lo que entrenas.**

Migración 077. El azúcar toca cinco tablas porque un macro nuevo viaja por toda la cadena: el
alimento lo guarda por 100 g, el renglón absoluto, la comida lo suma, el platillo lo congela y la
meta lo compara. Dos decisiones:

- **El azúcar es un techo, no una meta.** Se pinta distinto (gris que se vuelve rojo al pasarte,
  nunca verde al "llegar") y dejar el campo vacío significa "no me lo vigiles", que no es lo mismo
  que un techo de cero. El default sugerido es el 10% de las calorías, la recomendación de la OMS.
- **No suma calorías aparte**: sus kcal ya están dentro de los carbohidratos. Contarlo dos veces
  sería el bug obvio, y el prompt se lo dice al modelo explícitamente.

**La recomendación por entrenamiento del día.** Aquí había una trampa fácil de pisar: el factor de
actividad de la meta **ya incluye que entrenas**. Sumarle a la meta las calorías del entrenamiento
de hoy las cuenta dos veces — es el error que hace que una app te diga que te comas 3,400 kcal por
haber corrido 5 km. Lo correcto es ajustar por la **diferencia contra tu día promedio de la
semana**: hoy entrenas más que tu promedio, te faltan calorías; hoy descansas, te sobran; un día
promedio no ajusta nada. El ajuste va todo a carbohidratos: la proteína es por kilo de peso y no
cambia porque hoy corras, y la grasa tiene un piso hormonal que no conviene mover a diario.

La estimación usa METs por tipo de actividad, modulados por el RPE (o por la zona de FC cuando es
un plan sin RPE), y las series de la rutina para calcular la duración de una sesión de fuerza.
Si ya registraste la actividad de hoy, manda lo hecho sobre lo planeado — un plan no es un hecho.
Verificado: correr 10 km a RPE 7 con 80 kg da 611 kcal (~60 kcal/km, que es la referencia real).

**Ojo con esto:** el ajuste es relativo a **tu** semana, así que solo tiene sentido cuando la
semana está armada en Entrenar. Con un solo día programado, ese día parece enorme contra un
promedio de casi cero.

**2026-08-22 — El consejo, no solo el número.**

"Hoy te faltan 700 kcal" no le dice a nadie qué hacer. Lo accionable es el **timing**, así que la
tarjeta del día ahora dice cuánto comer, de qué, y cuándo, para cada sesión programada:

- **Antes**: ~1 g/kg de carbos unos 75 min antes (0.6 g/kg si es fuerza).
- **Durante**: 45 g/hora, y **solo** en cardio de más de 75 min. Comer carbos a media sesión de
  pesas no es una recomendación real, es ruido con cara de consejo experto.
- **Después**: ~1 g/kg de carbos y ~0.3 g/kg de proteína en los primeros 90 min.

La regla que evita el consejo tonto: **una sesión corta y suave no lleva carga previa**. Decirle a
alguien que se coma 80 g de carbos antes de trotar 25 minutos es empujarlo a comer de más con cara
de rigor. Debajo de 45 min y RPE ≤ 6, el consejo es "no necesitas cargar antes" y la recuperación
se reduce a la mitad.

Dos casos que costaron más de lo que parecen:

- **Registrar algo no es haber terminado el día.** Si corriste en la mañana pero falta la sesión de
  pesas, la meta del día no debe encogerse ni deben desaparecer los consejos de lo que falta. El
  día vale lo mayor entre lo hecho y lo planeado, y solo se considera terminado cuando queda menos
  del 30% de lo planeado.
- **La ventana de recuperación usa la sesión que coincide con lo registrado**, no la primera de la
  lista: una carrera suave pide la mitad de carbos que un día de pierna, y dar el número del otro
  es dar un número casi correcto, que es la peor clase de número.

**Nota de proceso:** durante la verificación el service worker me sirvió una copia cacheada de
`skandi-nutrition.js` y estuve depurando código viejo. Es exactamente la regla del versionado de
`CLAUDE.md` aplicándose a quien la escribió: **editar un módulo compartido sin bumpear la versión
sirve código rancio**. Vale la pena recordarlo antes de perseguir un fantasma.

**2026-08-22 — El build de producción falló: tope de 12 funciones.**

`No more than 12 Serverless Functions can be added to a Deployment on the Hobby plan.` El proyecto
ya estaba justo en 12 y mis dos endpoints nuevos lo pusieron en 14. La app nunca se cayó —
producción siguió sirviendo el deployment anterior— pero nada de nutrición llegó a estar vivo.

Arreglado sin tocar comportamiento, plegando dos pares en routers por `action`:

- `analyze-meal.js` + `lookup-barcode.js` → **`api/nutrition.js`** (`action: 'analyze' | 'barcode'`).
  Cada rama conserva sus propias guardas: la de código de barras no necesita `ANTHROPIC_API_KEY` ni
  toca la cuota.
- `get-user-email.js` → una acción más en **`search-users.js`**, que ya tenía router (`create`,
  `reception-active`). Era el endpoint más chico del repo (41 líneas), es admin, es sobre usuarios y
  tenía un solo punto de llamada.

De 14 a 12. Verificado: el despachador enruta bien, rechaza acciones desconocidas, `analyze` es el
default, y no quedaron referencias muertas a las rutas viejas.

**Regla nueva para el futuro:** un archivo en `api/` = una función. Cada endpoint nuevo se pliega en
un router existente, no agrega archivo. **Strava serán cuatro acciones en un solo `api/strava.js`**,
no cuatro archivos — si no, el build vuelve a fallar. La alternativa es Pro, y esa es decisión tuya.

## 12. Siguiente paso

1. ✅ Migraciones 073-075 corridas y `ANTHROPIC_API_KEY` cargada en Vercel (2026-08-22).
   Falta correr `076_skandi_dishes.sql`. **Nada está vivo todavía: el código no se ha empujado.**
3. ✅ Tab "Comida" completo (2026-08-22).
4. Correr `077_skandi_sugar_and_targets.sql` en Supabase.
5. **Primera foto real en producción**: es la única prueba que falta del camino IA.
6. Primera medición de tino: pesar 10 platillos frecuentes y comparar contra la estimación.
7. **Fase 4 (Strava)**: código escrito. Para encenderla faltan tres cosas, en este orden:
   1. Crear la app en strava.com/settings/api. **Authorization Callback Domain** =
      `habittraininghub.app` (el dominio pelón, sin `https://` y sin ruta), o el redirect se
      rechaza sin explicar por qué.
   2. Cargar en Vercel `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET` y
      `STRAVA_WEBHOOK_VERIFY_TOKEN` (esta última es una cadena larga cualquiera, la inventas
      tú; Strava solo la repite de vuelta para probar que el endpoint es nuestro).
   3. Correr `081_skandi_strava.sql`, desplegar, conectar desde Ajustes → Strava, y **desde
      una cuenta admin** dar de alta la suscripción del webhook una sola vez:
      `POST /api/skandi {action:'strava-subscription', op:'create'}`. Con `op:'list'` se
      verifica y con `op:'delete'` se da de baja.

   El webhook no se puede probar en local: Strava tiene que poder llamar a la URL pública.
   Mientras tanto, "Sincronizar ahora" en Ajustes hace el mismo trabajo a mano — y sigue ahí
   después como red de seguridad, porque un webhook perdido no avisa que se perdió.
8. Fase 2 — el motor de decisiones. La recomendación por entrenamiento del día ya es su primer
   ladrillo, puesto por adelantado (§8).
