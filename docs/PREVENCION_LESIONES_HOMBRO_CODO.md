# Prevención de lesiones de hombro y codo — plan de implementación

> Documento de planeación. Fecha: 2026-09-10. Dueño: Joseph.
> Fuente: *Lesiones de Hombro y Codo en Streetlifting (Biomecánica, Clínica y Prevención)*,
> Lucas Torino y Francisco Carrillo, 2026 (PDF fuera del repo, en `~/Downloads`). Las
> secciones del libro se citan como §N. Lo que aquí aparece está parafraseado y convertido en
> reglas que la app puede evaluar; el libro no se reproduce.
> Alcance: **Skandi Fit primero** (ahí vive tu plan: dominada lastrada, fondos lastrados,
> muscle-up, front lever, curls) y **HABIT Entrenar** en la última fase, con el mismo motor.

---

## 1. El problema

El libro se resume en una idea: en calistenia lastrada el músculo progresa más rápido que el
tendón, y la lesión casi nunca es un accidente, sino una **tendinopatía por sobreuso** que se
arma con semanas de "solo un poco más" (§1.1, §2.4). Lo que la provoca rara vez es un día duro.
Es la suma de cuatro cosas que nadie anota (§2.6, §5.0):

1. **Torque**: la posición (fondo profundo, hombro que se va adelante, agarre supino pesado).
2. **Velocidad**: los picos (rebote, excéntrica rápida, singles, transición peleada).
3. **Volumen efectivo**: las series que de verdad cuentan, no las totales.
4. **Recuperación**: sueño, estrés y el dolor que ya venía acumulado.

Si tres de las cuatro se disparan a la vez, el tejido protesta. Y el libro insiste en que no
hace falta registrar mucho: basta con **cuatro datos** (§5.5):

| Dato mínimo (§5.5) | ¿Skandi lo tiene? |
|---|---|
| Lastre del top set | ✅ `skandi_sets.weight_kg` |
| RPE del top set | ✅ `skandi_sets.rir` (RPE ≈ 10 − RIR, igual que `SkandiLoad.strengthRpe`) |
| Series efectivas **del patrón** | ⚠️ derivable, pero los ejercicios no tienen patrón |
| Síntomas a las 24 h (0–10) + zona | ❌ solo un booleano al terminar y una zona en texto libre |

Tres de los cuatro datos ya se registran. Falta el que más pesa: **cómo amaneció la
articulación al día siguiente**. Toda la lógica de ajuste, rehabilitación y retorno del libro
gira alrededor de esa regla de 24 h (§7.-2, §7.0, §8.0).

---

## 2. La idea central

```
  REGISTRO (4 datos)        →   DETECTORES                  →   DECISIÓN
  lastre del top set            ACWR / EWMA por patrón           semáforo de riesgo (3 de 4)
  RIR del top set               regla de 24 h                    ajuste ordenado:
  series efectivas/patrón       "una variable a la vez"            rango → volumen → intensidad
  dolor 24 h + zona             señales de alarma                puerta de progresión / singles
  (+ banderas técnicas)         calidad de la última rep         fase de retorno (RTP)
```

**La app no diagnostica, orienta.** Las zonas siguen el mapa del propio libro (dónde duele y
qué patrón suele alimentarlo, §1.4, §3.0, §4.0), sin nombres clínicos en la interfaz. Ante
una señal de alarma la app no ofrece ajustes: dice que hoy no toca PR y que conviene una
valoración profesional (§3.0.1, aviso legal del libro).

---

## 3. Lo que Skandi ya tiene y lo que le falta

### Ya existe (y se reusa, no se reimplementa)

| Pieza | Dónde | Qué aporta al plan |
|---|---|---|
| RIR por serie + RIR objetivo | `skandi_sets.rir`, `target_rir` (064, 068) | RPE del top set; definir serie efectiva |
| Calidad técnica 1–10 | `skandi_sets.form_quality`, solo si `track_quality` (078) | Calidad de la última rep en habilidades |
| Tempo + metrónomo | `skandi_exercises.tempo_seconds` (079), `tempoButtonHtml()` | Excéntrica controlada de 2–4 s (§3.0.2) |
| Clip por serie | `skandi_sets.clip_path` (079) | Ver si el agarre cambia cerca del fallo (§4.0.0.1) |
| ACWR de cuerpo entero | `skandi-load.js` (sRPE, 7 vs 28 días) | Misma matemática, otra serie |
| ACWR por articulación | `skandi-joint-load.js` (muñeca/codo/hombro) | Base del detector por zona |
| Aviso de articulación en el brief | `brief.caution.joint` en `skandi-brief.js` | El canal donde aparecerán los avisos |
| Sueño, HRV, pulso en reposo | `skandi_daily_wellness` (085) | La variable "recuperación" del §2.6 |
| Bloques y descargas | `skandi_training_blocks`, programas con fases (103) | Periodizar la ambición (§6.0 capa 3) |

### Falta

- **G1 — Bug de la moneda (Fase 0).** `setStimulusUnits()` en `skandi-recovery.js` usa
  `weight > 0 ? weight : BODYWEIGHT_KG_PROXY`: el lastre **sustituye** al peso corporal en vez
  de sumarse. Una serie de fondos +15 kg × 8 vale 15·8/500 = **0.24 SU**; la misma serie sin
  lastre vale 70·8/500 = **1.12 SU**. Meter lastre divide la carga calculada entre 4.7. El
  libro define la carga como *peso corporal + lastre* (§5.0). Esto contamina la figura de
  recuperación y el ACWR por articulación justo en los ejercicios que el libro estudia.
- **G2 — Los ejercicios no tienen patrón.** Sin `movement_pattern` no se pueden contar series
  efectivas de tracción o de empuje (§5.5, §8.3). `skandi-joint-load.js` adivina por regex
  sobre el slug.
- **G3 — El dolor no se mide.** `report_soreness` es un booleano, `report_soreness_area` es
  texto libre (`repeatedSorenessWarnings()` compara cadenas), no hay escala 0–10 ni seguimiento
  a las 24 h. Además mezcla agujetas musculares con dolor articular, que el libro separa (§3.0).
- **G4 — Bandas incompletas.** El ACWR solo conoce 0.8 y 1.5. El libro añade una zona de
  alerta de 1.30–1.50 (§5.1) y propone EWMA para quien entrena 4–5 días (§5.2).
- **G5 — La exposición de riesgo no queda registrada**: supino pesado, fondo profundo, inicio
  desde colgado pasivo, rebote, lastre en péndulo, transición peleada (§5.0, capa 4).
- **G6 — La calidad de la última rep solo existe para habilidades.** En dominada, fondos y
  muscle-up la fila muestra RIR, y el libro dice que lo que predice tolerancia es la última
  repetición, no el top set (§8.0.4, §6.0 capa 1).
- **G7 — No hay prevención.** En las migraciones solo encontré `cable-face-pull` y
  `scapular-pull-up`; faltan rotación externa, Y-raise y flexores/extensores de muñeca (§6.4).
- **G8 — No hay reglas de decisión**: ni regla del dolor, ni señales de alarma, ni ajuste
  ordenado, ni estado de retorno progresivo.

---

## 4. Reglas del libro traducidas a parámetros

La columna "Origen" distingue lo que el libro dice textualmente (**libro**) de lo que es
nuestra traducción a un número (**nuestro**). Lo nuestro son valores iniciales y se pueden
ajustar.

| # | Regla | Parámetro por defecto | § | Origen |
|---|---|---|---|---|
| R1 | Carga total | peso corporal × `bodyweight_share` + lastre | 5.0 | libro (el reparto por ejercicio es nuestro) |
| R2 | Serie efectiva | hecha y RIR ≤ 3; los holds de habilidad cuentan siempre | 5.0 | nuestro |
| R3 | Bandas ACWR | < 0.80 pierdes base · 0.80–1.30 ok · 1.30–1.50 alerta · > 1.50 pico | 5.1 | libro |
| R4 | EWMA | λ aguda = 2/(7+1), λ crónica = 2/(28+1); vigilar bloques de 3–4 días | 5.2 | libro (fórmula estándar) |
| R5 | Una variable a la vez | alerta si en la semana suben ≥ 2 de: e1RM del top set ≥ +2.5 %, series efectivas del patrón ≥ +20 %, exposiciones de riesgo | 5.3, 8.0.3 | regla del libro, umbrales nuestros |
| R6 | Dolor durante | tolerable hasta 3/10 **si la técnica no empeora** | 7.-2 | libro |
| R7 | Dolor a las 24 h | igual o mejor que el anterior → sigue; peor → recorta dosis y repite | 7.-2, 7.0 | libro |
| R8 | "Vas tarde" | dolor > 48 h que sube sesión a sesión; reps que caen con una carga antes fácil; dolor puntual en inserción | 5.4 | libro |
| R9 | Señales de alarma | dolor nocturno que despierta, pérdida aguda de rango o fuerza, inestabilidad, dolor que sube pese a bajar carga, hormigueo/entumecimiento, chasquido doloroso, inflamación marcada | 3.0.1, aviso | libro |
| R10 | Orden del ajuste | 1) rango agresivo → 2) volumen efectivo → 3) intensidad | 5.7 | libro |
| R11 | Semáforo | torque, velocidad, volumen, recuperación: 2 = ámbar, 3+ = rojo | 2.6 | libro |
| R12 | Antes de subir lastre | 5–10 reps idénticas sin balanceo, lastre estable, top set sin grind temprano, regla de 24 h | 2.8 | libro |
| R13 | Singles pesados | dolor basal bajo y estable (≤ 2), técnica sin compensaciones, 2–3 semanas sin picos (ACWR ≤ 1.30) | 8.5 | libro (el ≤ 2 es nuestro) |
| R14 | e1RM seguro | Epley sobre carga total con reps limpias; back-offs al 50–60 % × 8–12 | 8.1, 8.2 | libro |
| R15 | Retorno por fases | F1 2–7 días · F2 1–3 semanas · F3 2–6 semanas · F4 singles con volumen bajo | 8.4 | libro |
| R16 | Prevención mínima | 2–3 días por semana, 10–12 min: rotación externa 2×15–25, face pull o Y 2×12–20, flexores 2×12–20, extensores 2×12–20 | 6.4 | libro |
| R17 | Equilibrio de patrones | límite semanal de series efectivas por patrón + no vivir solo en tracción vertical y empuje profundo | 8.3 | regla del libro, límites nuestros |
| R18 | Excéntrica en fondos | 3 s (rango 2–4 s) | 3.0.2, 9.2 | libro |

### Mapa de zonas (el del libro, en lenguaje de la app)

| Zona (UI) | Figura | Qué patrón suele alimentarla | Primer ajuste (§) |
|---|---|---|---|
| Hombro — delante | A | fondo profundo, tracción supina pesada, escápula perdida | recortar profundidad, excéntrica 2–4 s, active hang, 1–2 semanas sin supino pesado ni fondo profundo (3.0.2, 3.5) |
| Hombro — lado | C, D | mecánica escapular pobre con volumen y fatiga | bajar volumen efectivo, menos agarre ancho, control escapular (3.1, 3.2) |
| Hombro — profundo / pinchazo | B, F | estructura pasiva; inicio desde colgado pasivo con lastre | conservador: pausar la variante; con chasquido doloroso o pérdida de fuerza → profesional (3.4) |
| Hombro — arriba | E | poco frecuente en fondos | observar; no hay receta específica en el libro |
| Codo — dentro | — | dosis de agarre: frecuencia de tracción + volumen + picos (singles, colgados, fallo) | 1–2 semanas sin singles, submáximo con tempo 5–8 reps, agarre neutro, sin colgados largos lastrados (4.0.2, 4.1) |
| Codo — detrás | — | fondos con excéntrica rápida, rebote, bloqueo agresivo, subidas bruscas | excéntrica controlada, sin rebote, bloqueo suave; subir carga **o** rango, no ambos (4.0.0.2, 4.2, 7.3) |
| Codo — fuera | — | accesorio de antebrazo o extensores, agarres extra | reducir ese accesorio (4.0) |
| Muñeca | — | *(el libro no la trata)* handstand, planche | se mantiene porque `skandi-joint-load.js` ya la mide |

---

## 5. Modelo de datos

La 117 (HABIT) sigue sin commitear ni publicar. Las migraciones de este plan solo tocan tablas
`skandi_*` y no dependen de ella, así que el orden de publicación da igual; el número sí va
después.

**Ya escrita: `118_skandi_bodyweight_share.sql`** (Fase 0) — la columna `bodyweight_share` y su
siembra. Ver §8.

### Migración 119 — `skandi_injury_prevention.sql`

**5.1 Ejercicios: patrón y exposición.**

```sql
alter table public.skandi_exercises
  add column if not exists movement_pattern text check (movement_pattern is null or movement_pattern in (
    'vertical_pull','horizontal_pull','dip','vertical_push','horizontal_push',
    'muscle_up','straight_arm','grip','prehab')),
  -- Exposición fija del ejercicio (§5.0 capa 4). La variante "segura" es la que no la trae.
  add column if not exists risk_tags text[] not null default '{}'
    check (risk_tags <@ array['supine_grip','wide_grip','deep_range','ballistic','long_grip_iso']::text[]);
```

El etiquetado de tus ejercicios va en la misma migración, con `update ... where slug in (...)`
literal. Por la nota de memoria sobre `pg_temp.ex()`, se verifica cada slug contra un
`insert` literal antes de etiquetarlo, no contra una referencia difusa.

**5.2 Banderas técnicas por serie (G5, G6).**

```sql
-- null = nadie la revisó · '{}' = limpia · con elementos = "serie deuda" (§6.0 capa 1)
alter table public.skandi_sets
  add column if not exists technique_flags text[]
    check (technique_flags is null or technique_flags <@ array[
      'passive_start','shrug','grip_shift','pendulum','path_change',
      'bounce','fast_eccentric','shoulder_forward','hard_lockout',
      'fought_transition','asymmetric']::text[]);
```

Que sea nullable con tres estados es a propósito: "no marqué nada" no significa "fue limpia".
Solo una serie revisada y sin banderas cuenta para la puerta de progresión (R12).

**5.3 El registro de 24 h (G3).**

```sql
create table if not exists public.skandi_joint_checkins (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid references public.profiles(id) on delete cascade not null,
  day         date not null,                -- día local que se reporta
  timing      text not null check (timing in ('during','next_day')),
  zone        text not null check (zone in ('shoulder_front','shoulder_side','shoulder_deep',
                'shoulder_top','elbow_inner','elbow_outer','elbow_back','wrist')),
  side        text not null default 'both' check (side in ('left','right','both')),
  pain        smallint not null check (pain between 0 and 10),
  session_id  uuid references public.skandi_sessions(id) on delete set null,
  red_flags   text[] not null default '{}' check (red_flags <@ array['night_pain','range_loss',
                'strength_loss','instability','numbness','painful_click','swelling']::text[]),
  note        text,
  created_at  timestamptz not null default now(),
  unique (user_id, day, timing, zone, side)
);
-- RLS: solo el dueño. El dolor es dato de salud: nunca visible para la tripulación,
-- igual que las comidas (073).
```

Un `pain = 0` también se guarda: la regla de 24 h compara contra el valor anterior, y sin los
ceros no hay línea base. `report_soreness` / `report_soreness_area` se quedan como están, para
las agujetas; el dolor articular es otra cosa y tiene su propia tabla.

### Migración 120 — `skandi_joint_episodes.sql` (Fase 4)

```sql
create table if not exists public.skandi_joint_episodes (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid references public.profiles(id) on delete cascade not null,
  zone        text not null,               -- mismo dominio que skandi_joint_checkins.zone
  side        text not null default 'both',
  phase       smallint not null default 1 check (phase between 1 and 4),
  opened_on   date not null,
  phase_since date not null,
  closed_on   date,
  note        text
);
create unique index if not exists skandi_joint_episodes_one_open
  on public.skandi_joint_episodes(user_id, zone, side) where closed_on is null;
```

El episodio lo abre **la persona**, a sugerencia de la app, nunca solo. Un índice parcial sirve
aquí porque nadie hace `ON CONFLICT` contra él (a diferencia de `external_id`, 081).

---

## 6. El motor: `joint-guard.js`

Un módulo puro, sin DOM y sin Supabase, como `skandi-load.js` y `skandi-joint-load.js`, y
**compartido desde el primer día** por Skandi y HABIT (por eso no lleva prefijo `skandi-`).
Cada app adapta sus filas a una forma común: `{day, pattern, bodyweightShare, weightKg, reps,
seconds, rir, done, flags}`. Reusa `SkandiLoad.acwr()` tal cual.

| Función | Qué contesta | Regla |
|---|---|---|
| `totalLoadKg(set, ex, bwKg)` | peso corporal × share + lastre | R1 |
| `isEffective(set, ex)` | ¿la serie cuenta? | R2 |
| `patternSeries(...)` / `patternReadout(pattern)` | series efectivas por día; ACWR con 4 bandas | R3 |
| `ewma(series)` | razón EWMA y bloque de 3–4 días | R4 |
| `e1rm(totalKg, reps)` | Epley sobre carga total; lastre equivalente = e1RM − peso | R14 |
| `oneVariableCheck(week, prevWeeks)` | qué subió a la vez: intensidad, volumen, exposición | R5 |
| `painVerdict(checkins, zone)` | `better` / `same` / `worse` / `over` (durante > 3) | R6, R7 |
| `redFlags(checkins, series)` | reportadas + "sube pese a bajar carga", que se deriva sola | R9 |
| `lateSignals(...)` | dolor > 48 h que sube; reps que caen a igual carga | R8 |
| `semaphore(ctx)` | 4 booleanos, cada uno con su motivo legible | R11 |
| `adjustments(zone, verdict)` | lista ordenada rango → volumen → intensidad, con la receta de la zona | R10 |
| `progressionGate(pattern, ctx)` | `{ok, reasons[]}` para subir lastre y, aparte, para singles | R12, R13 |
| `rtpPhase(episode, ctx)` | la prescripción de la fase y si ya se puede avanzar | R15 |
| `prehabAdherence(...)`, `patternBalance(...)` | sesiones de prevención; reparto de patrones | R16, R17 |

**La velocidad, sin sensores.** El libro habla de velocidad del top set, y no vamos a medir la
velocidad de la barra. Se usan tres sustitutos honestos: banderas de rebote / excéntrica rápida
/ transición peleada, reps que caen con la misma carga, y RIR más bajo con la misma carga y las
mismas reps.

**Experimental: el calentamiento que se alarga** (§4.0.1, §5.4, §8.0.2). Los minutos entre
`started_at` y la primera serie efectiva marcada podrían servir de sustituto sin pedirle nada a
nadie. Hay que validarlo con datos reales antes de convertirlo en aviso, porque `updated_at` de
una serie también cambia si se edita después.

### Fase 0: el arreglo de G1

`setStimulusUnits(set, opts)` acepta `opts = {bodyweightShare, bodyweightKg}`. Sin `opts` se
comporta **exactamente igual que hoy**, porque HABIT también carga `skandi-recovery.js` y no
debe cambiar sin querer. Skandi pasa `bodyweight_share` del ejercicio y `latestWeightKg()` (70
si no hay pesaje). Como la carga se deriva y no se guarda, el historial se recalcula entero y
de forma coherente: la aguda y la crónica cambian juntas, así que el cociente sigue siendo
comparable. La que sí cambia a la vista es la figura de recuperación. Las dos cosas son
correctas.

---

## 7. La interfaz (Skandi)

Cada dato nuevo cuesta **un toque o es opcional**. El único pedido diario nuevo es el de 24 h,
y solo aparece cuando hace falta.

1. **Durante la sesión**
   - En la hoja de opciones de la serie (`setOptionsHtml`, donde ya están lado y clip):
     banderas **del patrón**, no la lista entera:
     - tracción vertical: inicio pasivo, hombros subieron, agarre cambió, péndulo, trayectoria.
     - fondos: rebote, bajada rápida, hombro adelante, péndulo, bloqueo agresivo.
     - muscle-up: transición peleada, un lado cargó más, hombros subieron, bloqueo agresivo.
   - Al marcar la **última serie** de un básico lastrado (`vertical_pull`, `dip`, `muscle_up`):
     "¿La última rep se pareció a la primera?" **Sí** guarda `'{}'`. **No** abre las banderas
     (§8.0.4).
   - Tempo por defecto: fondos 3 s, dominada lastrada 2 s de bajada. Usa el metrónomo que ya
     existe.
   - Cues en `coach_tips`, parafraseados del §6.1, §6.2 y §9: active hang y "hombros al
     bolsillo"; intención de romper la barra; subir con el pecho. Fondos: anchura donde la
     escápula aguante, bajada de 2–3 s, rango útil sin rebote, bloqueo suave, costillas
     controladas. Muscle-up: tirón alto hacia el esternón, codos arriba y alrededor, transición
     simétrica, soporte estable.
   - Con un episodio abierto o un ajuste activo para ese patrón, franja arriba de la tarjeta
     del ejercicio: "Hoy: rango controlado · bajada 3 s · sin singles".
2. **Al terminar** (`finishWorkout`): "¿Dolor articular durante?" Primero aparecen las zonas
   que tocaron los ejercicios de hoy, con escala 0–10. "Ninguno" es un toque.
3. **Al día siguiente** (Inicio, tarjeta de arriba): aparece solo si ayer hubo una sesión que
   cargó hombro o codo, si ayer se reportó dolor, o si hay un episodio abierto. Trae una fila
   por zona relevante (0–10, arranca en el último valor), "Todo bien" en un toque y las señales
   de alarma plegadas. **Es la medición más importante del plan** (§7.0, regla 1).
4. **Brief** (`skandi-brief.js`, `cautions()`), siempre con la regla de "solo cuando hay algo
   que hacer":
   - `brief.caution.pain24`: el codo por dentro amaneció peor que la última vez; recorta
     primero X.
   - `brief.caution.redflag`: hoy no toca PR, y conviene que lo vea un profesional.
   - `brief.caution.pattern`: tracción a 1.4× de tu promedio, en zona de alerta.
   - `brief.caution.oneVar`: esta semana subiste lastre y series de tracción a la vez.
   - `brief.caution.semaphore`: 3 de 4 variables arriba (y cuáles).
5. **Pestaña Carga** (crece la tarjeta de articulaciones que ya existe): series efectivas por
   patrón y semana (8 semanas), ACWR con sus cuatro bandas, EWMA, y **el dolor de 24 h por zona
   sobre la misma línea de tiempo**. Ver el pico de carga que coincide con el dolor es lo que
   hace útiles los cuatro datos (§5.5). Abajo, adherencia a la prevención y equilibrio de
   patrones.
6. **Historial del ejercicio**: calidad de la última rep y e1RM sobre carga total.

### Ejemplo: la plantilla del §5.6, leída por la app

> **Dominada lastrada** · top set +40 × 2 @ RIR 1 · 6 series efectivas ·
> exposición: supino, inicio pasivo · 24 h: codo por dentro 4/10 (antes 1/10)
>
> **Veredicto:** la sesión salió, pero el tendón la pagó (R7 → `worse`).
> **Ajuste, en orden:** 1) quitar el supino pesado y empezar cada rep desde active hang ·
> 2) si mañana sigue igual, bajar de 6 a 4 series efectivas · 3) solo después, bajar lastre.
> **Puerta de progresión:** cerrada hasta que el codo vuelva a ≤ 1 dos veces seguidas.

---

## 8. Fases de implementación

Cada fase termina con `npm run check`, `npm run check:sql` en la migración, el bump de versión
**en todos los lugares** (`APP_VERSION`, `SKANDI_VERSION`, `CACHE_VERSION`, `?v=` de
`index.html`, manifiestos y tags) y `joint-guard.js` agregado al `SHELL` de `sw.js`.

### Fase 0 — Arreglar la moneda (G1) · ✅ hecha el 2026-09-11
- `skandi-recovery.js`: `setLoadKg(set, opts)` nuevo y `setStimulusUnits(set, opts)` compatible
  hacia atrás; `buildStimulusEvents` y `computeMuscleRecovery` aceptan `bodyweightKg` y leen
  `ex.bodyweight_share`.
- `migrations/118_skandi_bodyweight_share.sql`: la columna y su siembra en 49 slugs literales
  (dominadas de todo agarre, fondos, muscle-up, front y back lever, planche, handstand y HSPU,
  L-sit, human flag). El bloque avisa por NOTICE de cualquier slug que no exista, en vez de
  dejar que una coincidencia difusa etiquete otro ejercicio.
- `skandi-joint-load.js` pasa el reparto y el peso; `skandi.html` pasa `latestWeightKg()` en los
  tres consumidores (recuperación, brief y tarjeta de Carga).
- `scripts/check-recovery.js` (21 aserciones) dentro de `npm run check`, que ahora también hace
  `node --check` de todos los módulos `skandi-*` y compila el script de `skandi.html`.
- **Verificado:** fondos +15 kg × 8 = 1.488 SU contra 1.248 sin lastre (antes 0.24 contra 1.12),
  en Node y en el navegador. Un curl con mancuerna no se mueve ni un decimal, y HABIT tampoco,
  porque sin `bodyweight_share` el cálculo es el de siempre.
- **Queda como límite conocido:** una flexión o una sentadilla lastradas siguen contando de
  menos. Necesitan una fracción por patrón que se pueda defender; no se inventó una.
- **Falta para darlo por cerrado:** publicar la 118 en Supabase. Hasta entonces la columna llega
  `undefined` al cliente y todo se comporta como antes, sin romperse.

### Fase 1 — Registro mínimo (§5.5) · G2, G3
- Migración 119 (patrón, riesgo, banderas, check-ins) y etiquetado de tu plan.
- `joint-guard.js` con `isEffective`, `patternSeries`, `painVerdict` y `redFlags`, más
  `scripts/check-joint-guard.js` (aserciones en Node, como `scripts/check-training.js`) dentro
  de `npm run check`.
- Dolor al terminar + tarjeta de 24 h + `brief.caution.pain24` / `redflag`.
- **Terminado cuando:** tres días seguidos de uso real dejan una serie de check-ins sin huecos
  en tus zonas, y el brief cambia cuando un valor sube.

### Fase 2 — Detectores · G4, G5, G6
- ACWR por patrón con la banda de 1.30, EWMA y bloque de 3–4 días.
- `oneVariableCheck`, `semaphore`, `lateSignals`.
- Banderas en la hoja de la serie + pregunta de la última rep.
- Pestaña Carga: patrones, bandas y dolor en la misma línea de tiempo.
- La puerta de progresión sale como **texto** ("todavía no subas lastre porque…"), sin bloquear
  nada.

### Fase 3 — Prevención activa · G7
- Crear en el catálogo rotación externa, Y-raise y curl de muñeca (flexores y extensores) con
  `movement_pattern = 'prehab'`, y una rutina "Prevención hombro y codo (10–12 min)" (R16).
- Adherencia semanal (2–3) en Carga; recordatorio en el brief de un día de fuerza si vas en 0.
- Tempo por defecto y cues en `coach_tips` de dominada lastrada, fondos y muscle-up.
- "Aplicar ajuste de hoy" al iniciar la sesión: RIR objetivo +1, una serie menos en el patrón
  afectado y la franja de rango y tempo. **No toca la rutina**: es un sembrado distinto solo
  para esa sesión.

### Fase 4 — Retorno progresivo (RTP) · G8
- Migración 120 (episodios). La app sugiere abrir un episodio cuando R7 da `worse` dos veces
  seguidas o aparece R9; lo abre la persona.
- Prescripción por fase en la sesión y criterio de avance con la regla de 24 h (§8.4), más la
  puerta de singles (R13).
- Back-offs al 50–60 % del e1RM sobre carga total en F2 y F3 (§8.2).

### Fase 5 — HABIT Entrenar
- El mismo `joint-guard.js`. `coaching_session_sets` ya trae `weight`, `rir`, `target_rir` y
  `actual_seconds` (031, 070, 117); a `exercise_catalog` le faltan `movement_pattern` y
  `bodyweight_share`.
- El check-in de 24 h entra en el feedback post-entreno que ya lee David.
- Alertas al coach por la bandeja de la 117 (`coaching_alert_actions.signal_key`, p. ej.
  `joint:elbow_inner:worse`), con resolver y posponer, que ya existen.

---

## 9. Lo que deliberadamente no hacemos

- **No diagnosticar.** Nada de "SLAP" o "subacromial" en la interfaz: zonas y el patrón que
  suele alimentarlas, como el mapa del libro.
- **No bloquear el registro.** Las puertas aconsejan. Nunca impiden anotar una serie.
- **No abrir episodios ni editar rutinas solos.** Todo ajuste se confirma.
- **No medir velocidad con sensores** (VBT). Se usan los sustitutos del §6.
- **No inventar repartos por ejercicio** más finos que los de `skandi-joint-load.js`.
- **No compartir dolor con la tripulación.**
- **No mezclar agujetas con dolor articular.** Son dos preguntas y dos tablas.

---

## 10. Decisiones abiertas

1. ~~**Orden.**~~ Resuelto el 2026-09-11: **solo Skandi** por ahora. HABIT queda para después,
   sin fecha.
2. **Fricción de las 24 h.** ¿La tarjeta aparece después de cada sesión que carga hombro o
   codo, o solo si ya hubo dolor > 0 o la carga de la articulación está en alerta?
3. ~~**`bodyweight_share` de los fondos.**~~ Resuelto en la 118: **1.00**, como el resto de la
   familia donde el cuerpo entero cuelga o se sostiene sobre los brazos. Lo que sigue abierto es
   la otra mitad: qué fracción usar en flexiones, sentadillas a peso corporal y nordic curls, que
   hoy se quedan en NULL.
4. **Muñeca.** El libro no la trata. Se queda en la lista porque ya la medimos para handstand y
   planche.

---

## 11. Bitácora

- 2026-09-10 — Plan escrito a partir del PDF completo (52 págs.) y de revisar
  `skandi-recovery.js`, `skandi-load.js`, `skandi-joint-load.js`, `skandi-brief.js`, el reporte
  de `finishWorkout()`, las migraciones 040/064/068/078/079/085/106 (Skandi) y 029/031/070/117
  (HABIT). Encontrado el bug del lastre (G1). Nada implementado todavía.
- 2026-09-11 — **Fase 0 hecha** y alcance acotado a Skandi. Migración 118, arreglo en
  `skandi-recovery.js` y `skandi-joint-load.js`, cableado en `skandi.html`, pruebas en
  `scripts/check-recovery.js` y versión al `20260911-1` en todo el proyecto (incluye el bump de
  la release 117, que todavía no se publicaba). Falta correr la 118 en Supabase.
