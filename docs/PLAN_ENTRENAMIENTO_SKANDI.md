# Skandi Fit — Plan de entrenamiento integral

> Documento de planeación. Fecha: 2026-08-22. Dueño: Joseph.
> Complementa `PROYECTO_SKANDI_V2.md` (que cubre nutrición y el motor de decisiones).
> Este archivo es la fuente de verdad de **cómo se estructura, se planea y se ve el entrenamiento**.

---

## 1. El problema

Skandi Fit hoy planea la semana con **una sola herramienta: el día de la semana**.
`skandi_templates.weekday` dice qué rutina de fuerza toca el martes, y
`skandi_activity_templates.weekday` dice qué cardio toca el miércoles. Nada más.

Eso funciona perfecto para la fuerza —el press de banca del martes es el mismo martes tras
martes durante seis semanas, y esa repetición *es* el método— y falla completo para la
resistencia, donde el punto es justamente que **la semana 7 no se parece a la semana 1**:

| Semana | Correr | Bici | Nadar |
|---|---|---|---|
| 1 (base) | 5 km Z2 | 40 min Z2 | 800 m técnica |
| 5 (build) | 8 km + 6×400 Z4 | 75 min con 3×8' Z4 | 1,500 m con series |
| 9 (peak) | 12 km progresivo | 2 h + brick 15' | 2,000 m ritmo |
| 11 (taper) | 5 km con 4×1' | 45 min suave | 1,000 m suave |

Con el modelo actual, "correr el miércoles" es **un solo registro** que tienes que reescribir a
mano cada semana, y al reescribirlo **pierdes lo que decía la semana pasada**. No hay historia del
plan, no hay progresión, no hay taper, no hay forma de ver el bloque completo, y no hay manera de
contestar la pregunta que importa cuando entrenas para un triatlón: *¿voy adelantado o atrasado
respecto a lo que el plan decía?*

Además hay tres modalidades que la app hoy no sabe nombrar: **natación** existe en el catálogo pero
sin nada específico (piscina, estilo, series por 100 m), **bici** no distingue rodillo de carretera,
y **HIIT / Hyrox** simplemente no existe como tipo — se registran como `other`, lo que además le
miente a la figura muscular.

---

## 2. La idea central

Tres capas, y cada una responde una pregunta distinta. Hoy están colapsadas en una.

```
  PLANTILLA          →  lo que se repite         (rutina de fuerza, plan de cardio recurrente)
       ↓ se estampa
  CALENDARIO         →  lo que toca ese día      (fecha concreta, editable, con historia)
       ↓ se ejecuta
  SESIÓN REGISTRADA  →  lo que de verdad hiciste (skandi_sessions / skandi_external_activities)
```

**La regla que resuelve el conflicto fuerza-vs-resistencia:**

- La **plantilla** sigue siendo la fuente de verdad de lo que se repite. Editar la rutina de
  fuerza del martes se propaga a todos los martes futuros que nadie haya tocado.
- El **calendario** es la fuente de verdad de *un día concreto*. En cuanto editas el miércoles de
  la semana 5, ese día queda **congelado** (`is_edited = true`) y la plantilla ya no lo pisa jamás.
- Por eso la fuerza se planea una vez y vive de la plantilla, y la resistencia se planea semana a
  semana editando días concretos — **con el mismo mecanismo, sin dos sistemas paralelos**.

El precedente ya existe en este repo: `ensure_coaching_week_from_template` en HABIT materializa la
semana del socio desde su plantilla. Aquí es la misma idea, con la diferencia de que sí soporta
edición por día y sabe qué día editaste.

**Lo que NO cambia:** `skandi_sessions`, `skandi_sets`, `skandi_templates`, `skandi_template_items`
y el motor de recuperación se quedan exactamente como están. El calendario es una capa **encima**,
no un reemplazo. Ninguna sesión histórica se migra.

---

## 3. Modelo de datos

### Migración 080 — El calendario (`skandi_planned_sessions`)

Una fila = un entrenamiento planeado en una fecha concreta. **Todas las disciplinas en la misma
tabla**, porque el calendario tiene que poder mostrarlas juntas y ordenarlas en el día; separar
fuerza de cardio aquí obligaría a hacer un merge en el cliente en cada render.

```
skandi_planned_sessions
  id, user_id, day (date), sort_order int,           -- sort_order permite dos sesiones el mismo día
  discipline text check in
    ('strength','run','bike','swim','row','walk','hiit','hyrox','mobility','rest'),

  -- de dónde salió (para saber qué se puede re-estampar y qué no)
  source text check in ('template','manual','program','season'),
  template_id uuid  → skandi_templates (on delete set null),          -- fuerza
  activity_template_id uuid → skandi_activity_templates (set null),   -- cardio recurrente
  is_edited boolean default false,   -- lo tocaste a mano: la plantilla ya no lo pisa

  -- la prescripción
  title text,
  structure jsonb,                   -- pasos estructurados, §4
  target_duration_min int, target_distance_km numeric(6,2),
  target_zone int check 1..5, target_load int,       -- carga estimada (sRPE), §6
  is_brick boolean default false,    -- va pegado a la sesión anterior del mismo día
  notes text,

  -- la conciliación con lo que de verdad pasó
  status text default 'planned' check in ('planned','done','partial','skipped','moved'),
  session_id uuid  → skandi_sessions (on delete set null),
  activity_id uuid → skandi_external_activities (on delete set null),
  completed_at timestamptz,

  created_at, updated_at
  unique(user_id, day, sort_order)
  index (user_id, day)
  RLS: auth.uid() = user_id
```

Detalles que importan:

- **`is_edited` es el corazón de todo.** Sin él, o la plantilla pisa tus ajustes de la semana 5, o
  nunca se propaga un cambio de rutina. Con él, la propagación es segura: el estampado sólo toca
  filas `source='template' and is_edited = false and status='planned'`.
- **Nada se materializa a futuro infinito.** El RPC `skandi_ensure_week(week_start)` estampa una
  semana la primera vez que la abres (o la primera vez que la app arranca en una semana nueva) y
  es **idempotente**. Materializar 52 semanas por adelantado sería un desastre de mantenimiento: un
  cambio de rutina tendría que reescribir un año de filas.
- **`status='moved'`** conserva la fila original en lugar de borrarla. "Corrí el jueves lo del
  miércoles" es información: sin ella, la adherencia semanal miente.
- **El pasado no se materializa.** `skandi_ensure_week` se niega a estampar semanas anteriores a la
  actual — un plan retroactivo inventado no es historia.

### Migración 081 — Zonas y disciplinas de verdad

Sin umbrales, "Z4" es una palabra. Con umbrales, la tarjeta del día dice *4:35/km* y el plan se
puede seguir.

```
skandi_athlete_zones          -- una fila por usuario
  user_id (PK),
  max_hr int, resting_hr int, lthr int,          -- FC umbral (correr)
  run_threshold_sec_km int,                      -- ritmo umbral, seg/km
  swim_css_sec_100m int,                         -- Critical Swim Speed, seg/100 m
  bike_ftp_w int,                                -- si algún día hay potenciómetro
  updated_at
```

Y las columnas que faltan para capturar bien cada deporte
(sobre `skandi_external_activities` y `skandi_activity_templates`):

```
activity_type: agregar 'hiit', 'hyrox', 'strength_class'   -- amplía el check existente
+ rounds int, work_sec int, rest_sec int        -- intervalos / HIIT
+ elevation_m int
+ splits jsonb                                  -- parciales por km / por 100 m
+ pool_length_m int, stroke text                -- natación
+ perceived_effort_after int                    -- sRPE de Foster, 1-10, a los 30 min
+ avg_power_w int, avg_cadence int
```

`ACTIVITY_MUSCLE_MAP` en `skandi-recovery.js` gana `hiit`, `hyrox` y `strength_class`. Un Hyrox de
60 minutos que hoy cae en `other` (`Core 40 / Shoulders 20 / Quads 20 / Chest 20`) le miente a la
figura corporal: en realidad es cuádriceps, glúteos, espalda y hombros a partes casi iguales, con
carga excéntrica de piernas que tarda 72 h en irse.

### Migración 103 — Periodización dentro del programa

```
skandi_program_days.week_index                  -- 102: contiene la prescripción de S1…Sn y D

skandi_program_weeks
  id, program_id, week_index,
  phase text ('build','peak','taper','race','recovery'), note text,
  unique(program_id, week_index)

skandi_planned_sessions
  + program_id, program_week_index              -- instancia fechada e historia de adherencia
```

La prescripción no se duplica en una temporada separada: programa + `week_index` ya es el ciclo.
`skandi_training_blocks` permanece como compatibilidad para bloques sin programa; cuando hay un
programa activo, duración, descarga y fase se leen del programa. Una futura carrera puede sumar
fecha/meta a estos mismos metadatos sin crear otra colección de semanas que pueda contradecirlos.

---

## 4. Entrenamientos estructurados (`structure` jsonb)

Un entrenamiento de resistencia serio no es "40 minutos Z2". Es esto:

```json
[
  {"kind":"warmup",   "min":10, "zone":1},
  {"kind":"interval", "reps":6, "dist_m":400, "zone":4,
                      "rest":{"min":1.5,"zone":1}},
  {"kind":"steady",   "min":10, "zone":2},
  {"kind":"cooldown", "min":10, "zone":1}
]
```

`kind`: `warmup · steady · interval · tempo · recovery · cooldown · station`.
Un paso tiene **duración o distancia**, nunca las dos como obligatorias. `station` es para Hyrox
(`{"kind":"station","name":"sled push","dist_m":50}`).

**`skandi-plan.js`** (módulo puro, sin DOM ni Supabase, como los otros tres) expone:

| Función | Qué hace |
|---|---|
| `expand(structure)` | → `{duration_min, distance_km, load, steps[]}` — el total del entrenamiento |
| `label(structure)` | → `"6×400 Z4 · 45 min"` — la línea de una celda del calendario |
| `paceFor(zone, discipline, zones)` | → `"4:35/km"` / `"1:52/100m"` — convierte zona a número real |
| `estimateLoad(step, zones)` | → sRPE planeado, §6 |
| `buildSeason(opts)` | → semanas + sesiones planeadas, §7 |

Se prueba desde Node igual que `skandi-recovery.js`. La regla de oro del proyecto se mantiene:
**si es matemática, no vive en `skandi.html`.**

Por qué jsonb y no una tabla `skandi_workout_steps`: un entrenamiento estructurado siempre se lee y
se escribe completo, nunca se consulta "todos los pasos tipo interval de mi historia". Una tabla
hija aquí sólo agrega joins y un modo de quedar inconsistente.

---

## 5. La interfaz

### 5.1 Dónde vive (el tab bar ya está lleno)

La barra tiene 7 columnas a 375 px y no cabe una octava. **El calendario no es un tab nuevo:**
`train` se subdivide, con el mismo patrón que ya usa Progreso (`setProgressTab`):

```
Entrenar    [ Hoy ]  [ Calendario ]  [ Rutinas ]
```

- **Hoy** — lo que hoy es la parte de arriba del tab: la sesión de hoy (fuerza *y* cardio en una
  sola tarjeta, no dos), el botón de empezar, la carga de la semana.
- **Calendario** — la vista nueva.
- **Rutinas** — la biblioteca de rutinas propias y del crew, y los planes de cardio recurrentes.
  Es decir: **las plantillas**, que ahora tienen un nombre honesto.

### 5.2 El calendario

TrainingPeaks pone un mes completo en pantalla porque es una app de escritorio. En un teléfono a
375 px eso son celdas de 50 px donde no cabe nada legible. La versión minimalista que sí funciona
es **la semana como renglón, cuatro semanas visibles, scroll infinito hacia adelante**:

```
┌─────────────────────────────────────────────────────────┐
│  ‹  AGOSTO 2026                            [ Hoy ]      │
├─────────────────────────────────────────────────────────┤
│ SEM 5 · BUILD                        4.5 / 6.0 h   ▓▓▓░ │
│  L      M      X      J      V      S      D            │
│ ┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐              │
│ │ ●  ││ ▲  ││ ●  ││ ■  ││    ││ ▲  ││ ●  │              │
│ │Push││ 8km││Pull││1500││desc││ 60'││Legs│              │
│ │45' ││ Z2 ││45' ││ m  ││    ││bici││50' ││             │
│ │ ✓  ││ ✓  ││ ✓  ││    ││    ││    ││    ││             │
│ └────┘└────┘└────┘└────┘└────┘└────┘└────┘              │
├─────────────────────────────────────────────────────────┤
│ SEM 6 · BUILD                        0 / 6.5 h          │
│  ...                                                    │
└─────────────────────────────────────────────────────────┘
```

Reglas de diseño, todas por la misma razón (que quepa y se lea de un vistazo):

- **Un glifo por disciplina**, no iconos a color de 24 px: `●` fuerza, `▲` correr, `◆` bici,
  `≈` nadar, `■` nadar-piscina/remo, `✦` HIIT/Hyrox. Color sólo para el estado, no para el deporte.
- **Tres renglones por celda como máximo**: qué, cuánto, y una palomita si se hizo. Todo lo demás
  vive un tap adentro.
- **Dos sesiones el mismo día** se apilan (celda partida). Un **brick** se dibuja con las dos
  pegadas y sin separación — visualmente *es* una sola sesión.
- **El encabezado de la semana es la fase y la adherencia**: `4.5 / 6.0 h`. Ese número es el que
  contesta "¿voy bien?" sin abrir nada.
- **Verde = hecho, gris = planeado, ámbar = parcial, tachado = saltado.** Nada más. Un calendario
  con doce colores no se lee, se descifra.
- El día de hoy tiene borde, no relleno — el relleno se reserva para "hecho".

### 5.3 El día (hoja inferior al tocar una celda)

```
Miércoles 27 de agosto · BUILD semana 5

  ▲  Correr — series               planeado
     10' Z1 · 6×400 Z4 (1:30 rec) · 10' Z1
     45 min · ~8 km · Z4 = 4:35/km
     [ Empezar ]  [ Registrar hecho ]

  ●  Pull A                        ✓ hecho 06:40
     8 ejercicios · 52 min · RPE 8

  [ + Agregar ]   [ Mover a otro día ]   [ Copiar a… ]
```

`Copiar a…` es lo que hace usable la planeación de resistencia: copias el miércoles de la semana 5
a la 6 y le subes 10%, en vez de escribirlo desde cero. Es la operación que más vas a repetir.

**No hay drag & drop.** En un teléfono, arrastrar entre celdas de 45 px falla más de lo que acierta;
"Mover a otro día" con un selector de fecha es dos taps y siempre funciona.

### 5.4 La conciliación planeado ↔ hecho

Al terminar una sesión de fuerza (`finishWorkout`) o registrar una actividad (`openLogActivity`),
la app busca una fila planeada **del mismo día y disciplina, sin conciliar**, y la marca `done`
enlazando el `session_id` / `activity_id`. Si no hay ninguna, la sesión existe igual y aparece en
el calendario como **extra** (borde punteado) — entrenar algo que no estaba planeado no es un error
que haya que capturar en un formulario.

Esto es lo que convierte al calendario en algo más que una agenda: sin conciliación no hay
adherencia, y sin adherencia el plan es decorativo.

---

## 6. Una sola moneda de carga

Hoy hay dos monedas y no se pueden sumar: la fuerza produce **unidades de estímulo (SU)** en
`skandi-recovery.js`, el cardio produce nada. Para que el calendario pueda decir "esta semana
llevas 4.5 de 6 horas" y para que el ACWR de la Fase 2 sea honesto, hace falta **un número que
signifique lo mismo en las cinco disciplinas**.

**Decisión: sRPE de Foster (`minutos × RPE`) para todo.** Es la métrica con más validación en
deporte real, no necesita potenciómetro ni banda de FC, y ya la capturas parcialmente
(`intensity` en las actividades, `report_difficulty` en las sesiones).

| Fuente | RPE de sesión |
|---|---|
| Actividad externa | `intensity` (ya existe, 1-10) o `perceived_effort_after` si se llenó |
| Sesión de fuerza | `10 − RIR promedio de las series`, acotado a 4-10; si no hay RIR, `report_difficulty` → 5/7/9 |
| Sesión planeada | tabla zona→RPE: Z1=3, Z2=4, Z3=6, Z4=8, Z5=9.5 |

Las **SU por músculo no se tocan**: siguen alimentando la figura corporal, que es una pregunta
distinta ("¿qué músculo está fatigado?") de la que contesta el sRPE ("¿cuánto entrené?"). Dos
métricas, dos preguntas, sin mezclarlas.

`skandi-load.js` (el módulo que la Fase 2 del otro documento ya pedía) recibe sesiones + actividades
y devuelve carga diaria, aguda (7 d), crónica (28 d) y ACWR. El calendario consume la misma función
para pintar planeado vs hecho.

---

## 7. El triatlón

`SkandiPlan.buildSeason()` genera la temporada completa y determinista, sin IA:

```js
buildSeason({
  raceDate: '2026-11-15',
  sport: 'triathlon_sprint',        // 750 m · 20 km · 5 km
  weeklyHours: 6,
  strengthDays: ['mon','thu'],      // la fuerza NO se sacrifica, se acomoda
  swimDays: 2, bikeDays: 2, runDays: 3,
  startFrom: '2026-08-24'
})
```

Reglas que codifica (estándar de la literatura de resistencia, no invento):

- **Progresión 3:1** — tres semanas de carga creciente (~+8% de volumen) y una de recuperación
  (−40%). Con `strengthDays` la semana de recuperación coincide con el deload de fuerza: es la
  misma semana, no dos descargas distintas en semanas distintas.
- **Fases:** base (técnica y Z2) → build (umbral y series) → peak (simulacros y bricks) →
  taper (2 semanas, volumen −40% y −60%, **intensidad intacta**) → carrera.
- **Nunca dos días duros seguidos**, y el día siguiente a piernas pesadas no lleva la sesión larga
  de correr.
- **Brick** desde la fase build: bici larga + 15' corriendo, una vez por semana.
- La fuerza **no se elimina en el taper**, se reduce a mantenimiento (menos series, mismo peso).
  Es el error clásico de los planes de triatlón y cuesta justo lo que llevas años construyendo.

Lo que genera son filas `source='season'` en `skandi_planned_sessions`, es decir **exactamente las
mismas filas que crearías a mano**. Se editan igual, y editarlas las marca `is_edited`. Regenerar
la temporada respeta todo lo editado y todo lo hecho.

Por qué determinista y no IA: la temporada se va a regenerar cada vez que cambie la fecha de la
carrera, te lesiones o te embarques. Una salida que cambia sola entre corridas no se puede
auditar, cuesta dinero por corrida, y no funciona a bordo sin señal.

---

## 8. HIIT y Hyrox

No son cardio ni fuerza, y tratarlos como cualquiera de los dos rompe algo:

- Como **cardio** (`other`), la figura muscular no ve el trabajo de piernas y el ACWR subestima.
- Como **fuerza**, no hay cómo registrar rondas ni tiempos, y `skandi_sets` pide series/reps/peso.

Se modelan como disciplina propia con `structure` de tipo `station`:

```json
[{"kind":"station","name":"burpee broad jump","dist_m":80},
 {"kind":"station","name":"sled pull","dist_m":50},
 {"kind":"interval","reps":8,"work_sec":40,"rest_sec":20,"zone":5}]
```

Se registran en `skandi_external_activities` (con `rounds`, `work_sec`, `rest_sec`), producen sRPE
como cualquier actividad, y aportan a la figura muscular con su propio reparto en
`ACTIVITY_MUSCLE_MAP`. Un Hyrox completo dura ~70 min con RPE 9: eso son 630 unidades de carga, más
que cualquier sesión de fuerza — si no se cuenta, el ACWR de esa semana es ficción.

---

## 9. Fases de implementación

| Fase | Qué entrega | Migración | Tamaño |
|---|---|---|---|
| **T1** | **Calendario fechado.** `skandi_planned_sessions`, RPC `skandi_ensure_week`, subtabs de Entrenar, vista de 4 semanas, hoja del día, conciliación automática | 080 | 3 sesiones |
| **T2** | **Resistencia estructurada.** `structure` jsonb, `skandi-plan.js`, zonas y umbrales, disciplinas nuevas (hiit/hyrox), captura rica de actividad (splits, piscina, intervalos) | 081 | 2–3 sesiones |
| **T3 / P3** | **Periodización del programa.** Semanas distintas, descarga propia, fase y adherencia por ciclo, sin temporada paralela | 103 | terminada |
| **T4** | **Carga unificada.** `skandi-load.js`, sRPE en todo, ACWR, planeado vs hecho en la tarjeta de Home. Es la Fase 2 del otro documento, que aquí ya tiene todos sus insumos | 083 | 2 sesiones |

**El orden no es negociable.** T1 sin T2 ya sirve (un calendario con lo que hoy existe). T2 sin T1
no tiene dónde vivir. T3 sin T2 genera semanas que no saben describir un entrenamiento. T4 sin T3
no tiene con qué comparar.

Se puede intercalar con la Fase 1 de nutrición del otro documento sin conflicto: no comparten
tablas ni pantallas. T4 sí depende de que la nutrición ya registre, porque el consejo diario cruza
carga con déficit calórico.

**Ninguna de estas fases agrega una función serverless.** Todo es cliente + RPC de Postgres. El
proyecto sigue en 12 de 12 en el plan Hobby, que es un límite duro.

---

## 10. Lo que deliberadamente no hacemos

| No hacemos | Por qué |
|---|---|
| Materializar el año completo por adelantado | Un cambio de rutina tendría que reescribir 52 semanas. Se estampa la semana al abrirla |
| Tabla `skandi_workout_steps` | Los pasos siempre se leen completos. Una tabla hija sólo agrega joins y estados inconsistentes |
| Drag & drop en el calendario | A 375 px falla más de lo que acierta. "Mover a otro día" son dos taps y siempre funciona |
| Vista de mes completo | Celdas de 50 px donde no cabe el nombre del entrenamiento. La semana-renglón sí se lee |
| Generar la temporada con IA | Se regenera seguido, tiene que ser auditable y gratis, y a bordo no siempre hay señal |
| TSS/NP con potencia | No hay potenciómetro. Prometer una métrica que se alimenta de datos que no tienes es peor que no tenerla |
| Un tab nuevo | La barra ya está en 7 columnas a 375 px. Entrenar se subdivide |
| Borrar `skandi_training_blocks` en la misma migración que cambia quién la lee | Deja el rollback sin salida |

---

## 11. Definición de terminado

**T1**
- [ ] Abrir una semana futura la estampa desde las plantillas, y abrirla otra vez no duplica nada
- [ ] Editar el miércoles de la semana 5 no altera la rutina del miércoles ni las demás semanas
- [ ] Editar la rutina de fuerza sí se propaga a los días futuros sin tocar
- [ ] Terminar una sesión marca la fila planeada como hecha, sola
- [ ] Una sesión no planeada aparece como extra, no se pierde
- [ ] El calendario carga en una sola consulta por rango de fechas

**T2**
- [ ] `SkandiPlan.expand()` y `label()` probados desde Node, sin navegador
- [ ] "Z4" se muestra como ritmo real cuando hay umbrales, y como "Z4" cuando no
- [ ] Un HIIT registrado mueve la figura muscular de forma creíble

**T3**
- [x] Una semana puede apartarse de la base sin alterar las demás
- [x] La descarga tiene contenido propio y fase de recuperación por defecto
- [x] El calendario conserva programa/semana y calcula adherencia histórica del ciclo

**T4**
- [ ] ACWR calculado con fuerza + cardio + HIIT en la misma unidad
- [ ] Home muestra una frase, no un tablero

---

## 12. Bitácora

**2026-08-22 — Costura con Strava (081).**

Una actividad importada de Strava marca sola el día planeado como hecho: esa conciliación vive
en `skandi_ensure_week`, y el RPC no se vuelve a llamar mientras la semana siga en
`state.ensuredWeeks`. `syncStrava()` ahora limpia ese set antes de recargar — sin eso había que
reiniciar la app para ver el plan actualizarse. Ojo con el alcance: el jalón de Strava trae 30
días por default, pero el RPC se niega a materializar semanas pasadas (§3), así que importar un
mes de historia **no** rellena la adherencia de semanas anteriores. Es lo correcto: un plan
inventado hacia atrás no es historia.

**2026-08-22 — T1 implementada (migración 080 + calendario en `skandi.html`).**

- `migrations/080_skandi_planned_sessions.sql`: la tabla, sus políticas y el RPC
  `skandi_ensure_week`. **Falta correrla a mano en el SQL Editor de Supabase** — hasta
  entonces la app detecta que no existe (`plannedReady=false`) y Entrenar se cae a las
  tarjetas de siempre en vez de romperse.
- El RPC hace tres cosas: borra los estampados obsoletos que nadie tocó, inserta los que
  faltan, y **concilia de arrastre** — al encender el calendario a media semana, las sesiones
  ya registradas se ligan solas a su día. Sin ese tercer paso la primera pantalla diría 0/4
  habiendo entrenado tres días, y una métrica que arranca mintiendo no se vuelve a mirar.
- `skandi.html`: Entrenar se subdividió en **Hoy · Calendario · Rutinas**, con la cuadrícula
  de 4 semanas, la hoja del día, mover/copiar/saltar y la conciliación automática enganchada
  en `finishWorkout()` y `saveExternalActivity()`.
- La adherencia semanal cuenta **solo filas planeadas**. Sumarle los entrenamientos extra
  daba "3 / 3" en una semana donde se hizo una de tres cosas planeadas y dos improvisadas.
- Verificado corriendo el `<script>` de `skandi.html` en Node con `document` y Supabase
  falsos (20 aserciones de render). El RPC pasa `npm run check:sql` pero **no se ha ejecutado
  contra Postgres**.
- Ojo con la numeración: mientras se escribía esto, otra sesión tomó la **081** para Strava,
  así que T2 (zonas y resistencia estructurada) aterriza en 082 o después.

**2026-08-22 — Documento creado.** Auditoría del modelo actual: la planeación entera descansa en
`weekday`, que es correcto para fuerza e insuficiente para resistencia periodizada. Decisión
central: capa de calendario fechado con `is_edited` como árbitro entre plantilla y día concreto.
Pendiente de decidir contigo antes de escribir la 080: si la temporada arranca con una fecha de
carrera real o si T3 se pospone hasta tener inscripción.
