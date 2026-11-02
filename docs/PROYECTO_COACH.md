# Coaching 1:1 de skills — la app entrega el plan, WhatsApp lleva la relación

> Documento de planeación. Fecha: 2026-11-02 (reescrito el mismo día). Dueño: Joseph.
> Relacionados: `HABIT_PARA_TODOS.md` (Entrenar es de cualquier cuenta, migración 127),
> `migrations/078_skandi_skill_lines.sql` y `079_skandi_skill_depth.sql` (escalones de un skill:
> el antecedente que ya corre, en Skandi).
> Bitácora al final.

---

## 0. Lo que cambió, y por qué este documento se reescribió

La primera versión proponía una app aparte (`coach.html`) con subida de video, cola de revisión y
notas de voz. **Eso ya no aplica**: la revisión de videos y el trato con el alumno van por
WhatsApp. En la app va *el plan*: rutina, drills, cues a analizar y videos muestra.

Con el video fuera, una app aparte es la decisión equivocada: tendría que reconstruir programas,
semana, rutinas y la hoja de entreno —lo más caro que hay en este repo— para entregar
exactamente lo que **Entrenar ya entrega**.

**La decisión es la contraria: los alumnos son cuentas de HABIT Crew y tú asignas desde el panel
de coach que ya tienes.** Lo que se construye son tres piezas que faltan, no una app.

---

## 1. Lo que ya está construido (puedes empezar esta semana, sin código)

Esto existe hoy y corre en producción:

| Lo que quieres poner | Dónde ya vive |
|---|---|
| **La rutina** | `boards` — una rutina por alumno o del gym, con color que la distingue |
| **El programa de varias semanas** | `coaching_programs` + `coaching_program_days` con `start_date` y `weeks`: un ciclo con fases, estampado al calendario semana por semana (migración 115) |
| **La semana del alumno** | `coaching_week_templates` + `coaching_schedule`; el alumno lo ve en Entrenar marcado **«de tu coach»** y su lista se parte en «De tu entrenador» / «Rutinas básicas» |
| **Los drills** | son ejercicios de la rutina: series, reps, rango, **pirámide**, tiempo, descanso y RIR por ejercicio |
| **Los cues** | el campo **«Indicaciones (opcional)»** de cada ejercicio (`exercises[].note`) |
| **Videos muestra** | **dos videos con nombre por ejercicio** en el editor, más el `video_url` del `exercise_catalog`; el visor respeta la forma (YouTube 16:9, Shorts y Drive 9:16) y abajo muestra músculos y «cómo se hace» |
| **Dónde asignas** | HABIT (`/`) como admin → panel del coach: programa → semana → rutinas del cliente, con buscador y vista previa del contenido antes de asignar |
| **Lo que el alumno ya obtiene gratis** | la hoja de entreno (palomear sin escribir, el peso se copia, **«La vez pasada»**), el reloj con intervalos, el mapa de fatiga muscular, Progreso y PRs, Actividad, y los stickers para historias |

**Cómo se usa hoy, tal cual:** el alumno abre cuenta en HABIT Crew (`/crew`, queda
`joined_as='app'` — no da puerta ni reservas, migración 127). Tú entras a HABIT como admin, le
armas el programa, y en cada ejercicio escribes las indicaciones y pegas el video muestra.

**Ojo con una cosa**: el panel de admin **no existe en Crew** (ahí el staff entra como miembro).
Asignas desde `/`, el alumno lo ve en `/crew`. Es la misma base de datos, así que funciona — pero
es bueno saberlo antes de buscar el panel en el lugar equivocado.

---

## 2. Lo que falta (y es todo lo que hay que construir)

### Hueco 1 — Los cues no llegan al entreno. **El más importante y el más barato.**

Hoy `exercises[].note` se pinta en la lista de la rutina (`renderExerciseListHtml`, `.ex-note`)
**pero no en la hoja de entreno**: `wsExerciseHtml` lleva los videos y las `instructions` del
catálogo, y el único «note» que conoce es `exerciseNotesMap` — que es la nota **privada del
alumno** (tabla `exercise_notes`), no tu indicación. O sea: tus cues desaparecen justo en el
momento en que el alumno los necesita.

Y aparte son un párrafo. Para "cues a analizar" quieres 3 o 4 puntos numerados, para poder
decirle por WhatsApp *«se te fue el 2»* y que los dos vean lo mismo.

**Arreglo, sin migración**: partir el mismo campo `note` por líneas (o por `;`) y pintarlo como
cues numerados en la cabeza del ejercicio de la hoja y en la ficha. El campo no cambia, así que
lo que ya escribiste sigue sirviendo y una sola línea se sigue viendo como una sola.

No juntar tus cues con `exercise_notes`: esa es la nota privada del alumno y esa asimetría está
bien — tú pones qué mirar, él apunta lo suyo.

### Hueco 2 — No hay escalones de skill. **Lo único que pide tablas nuevas.**

HABIT no sabe qué es un front lever tuck ni que va antes del advanced tuck. Skandi sí
(`progression_group`, `progression_rank`, `progression_criteria`, y el nivel como
`rank + min(1, marca/objetivo)` — una curva, no un peldaño). Para calistenia 1:1 esto es la
columna vertebral: es la respuesta a *«¿cómo voy?»*.

Lo mínimo:

```
coach_skills         slug, name_es/en, family, (el orden de la escalera)
coach_skill_levels   skill_id, rank, name_es/en, criteria, hold_sec | reps
                     -- criteria es el estándar de forma DE ESE escalón: "limpio" no significa
                     -- lo mismo en tuck que en straddle
coach_student_skills student_id, skill_id, rank, mark, target_rank, updated_at
                     -- el número de progreso es DERIVADO, no columna
```

El alumno lo lee; tú lo mueves cuando el video de WhatsApp te lo demuestra. **Nada se sube ni se
valida solo**: la decisión es tuya y se escribe a mano, que es exactamente como funciona un
coaching 1:1.

La lógica pura va en `coach-skills.js` (sin DOM y sin Supabase, patrón de `skandi-recovery.js`),
probada desde Node con `scripts/check-coach.js` dentro de `npm run check`.

### Hueco 3 — El alumno no tiene una portada de su bloque. **Chico.**

Que al abrir vea: en qué escalón va cada skill, qué toca hoy, y los cues del bloque. Hoy lo tiene
repartido entre Inicio y Entrenar. Una tarjeta en Inicio para quien tiene coach, no una sección
nueva.

Y falta marcar quién es tu alumno. `coaching_beta` ya existe pero es la asesoría de David, con su
chat y hábitos apagados (`COACHING_SECTION_ON = false`): reusar ese flag mezcla dos cosas. Una
columna propia (o `coach_students`, si vas a tener más de un coach) deja claro de quién es cada
alumno sin encender nada de lo viejo.

---

## 3. Qué NO se construye

- **Nada de subir video, cola de revisión, notas de voz ni correcciones por segundo.** Eso es
  WhatsApp, y mientras sean pocos alumnos WhatsApp le gana a cualquier cosa que hagamos: ya está
  instalado, manda video sin pensar y no hay que enseñarlo.
- **App aparte.** Ver §0.
- **Chat dentro de la app.** Duplicaría WhatsApp y partiría la conversación en dos lugares, que es
  peor que tenerla en uno.
- **IA que analice técnica.** No con el video fuera de la app.
- **Cobrar el 1:1 dentro de la app.** Por fuera no bloquea nada.

---

## 4. Fases

| Fase | Qué entra | Cuánto es |
|---|---|---|
| **0** | **Nada de código.** Arrancas con 1 o 2 alumnos sobre lo que ya existe: cuenta en Crew, programa armado desde HABIT admin, indicaciones y video pegados en cada ejercicio | Esta semana |
| **1** | ✅ **Hecho (2 nov 2026)**: los cues numerados en la hoja de entreno, más el criterio de forma del escalón | — |
| **2** | ✅ **Hecho (2 nov 2026)**: migración 141, `habit-skills.js` + `scripts/check-skills.js`, pestaña Skills, la escalera con animaciones y el panel del coach | — |
| **2b** | ✅ **Hecho (2 nov 2026)**: entrenar sin coach — elegir tu escalón, entrenarlo con un toque y subir tú cuando cumples el estándar (migración 144) | — |
| **3** | Portada del bloque en Inicio y la marca de alumno 1:1 | Chico |
| **4** | *Si lo piden los alumnos*: sticker de «subí de escalón» (`habit-share.js`, `kind:'skill'`) y push de «te toca grabar» | Opcional |

**La Fase 0 es de verdad una fase.** Dos semanas dando coaching sobre lo que ya hay te van a decir
qué construir mucho mejor que este documento — y si resulta que los cues en papel bastan, te
ahorraste la Fase 1.

---

## 5. A cuidar

- **Entrar aquí no es ser socio.** El candado real es `book_my_slot` (migración 120): un alumno
  de `/crew` no tiene puerta ni reservas y eso ya está resuelto. No inventarle permisos.
- **Dos capas, dos reglas.** Lo que decide es la base (RLS); la app solo avisa. Si hay tabla nueva
  de alumnos, el RLS de `coach_student_skills` se cuelga de ahí, no de un filtro en el cliente.
- **Español e inglés** (requisito permanente, CLAUDE.md): los textos nuevos de cues y escalones
  nacen con las dos traducciones, incluido `criteria` de cada escalón.
- **Nada de esto toca `app.html`** salvo subir la versión. Lo de la hoja de entreno va a
  `crew.html`; si lo quieres también en HABIT, se saca como módulo compartido igual que
  `habit-share.js` y `habit-activity.js`.
- **Subir la versión** al tocar cualquier app: `APP_VERSION` en las dos, `SKANDI_VERSION`,
  `CACHE_VERSION` y los `?v=`, todos al mismo valor.

---

## 6. Preguntas abiertas

1. **¿Qué skills al arrancar?** Con 3 o 4 (front lever, planche, handstand, muscle up) los
   escalones se siembran a mano en la migración y no hace falta pantalla para crearlos.
2. **¿Cuántos alumnos?** Con menos de 5, la Fase 0 puede durar bastante.
3. **¿Los alumnos son socios del gym o gente de fuera?** Si son de fuera, todos viven en Crew y el
   alta es la de cualquiera; si son socios, ya tienen cuenta y no hay nada que hacer.
4. **¿Más de un coach?** Decide si la marca de alumno es una columna en `profiles` o una tabla
   `coach_students`.

---

## Bitácora

- **2 nov 2026** — Primera versión: app aparte con revisión de video dentro. **Descartada el mismo
  día**: la revisión y el trato van por WhatsApp.
- **2 nov 2026** — Reescrito. Los alumnos viven en HABIT Crew y se asignan desde el panel de coach
  que ya existe. Tres huecos reales (cues en el entreno, escalones de skill, portada del bloque) y
  una Fase 0 sin código. Nada construido todavía.
- **2 nov 2026** — **Construidas las fases 1 y 2.** Migración `141_coach_skills.sql`: la escalera vive
  en `exercise_catalog` (`progression_group/rank/target/target_sets/criteria` + `animation_url`),
  las líneas en `coach_skills`, el escalón del alumno en `coach_student_skills` (solo lo mueve el
  admin; un trigger lo historia en `coach_skill_events`) y las animaciones en el bucket público
  `skill-media`. Siete líneas sembradas con 35 escalones, criterios en ES y EN, y los 11
  ejercicios que la 071 no trajo. `habit-skills.js` (puro, 105 aserciones en
  `scripts/check-skills.js`) tiene la curva continua, el estándar de dos sesiones seguidas y el
  parseo de cues. En Crew: pestaña **Skills** en Entrenar, la hoja de la escalera (una sola para
  alumno y coach) y los cues numerados + el criterio del escalón en la hoja de entreno.
- **2 nov 2026** — **Las animaciones de las dos primeras escaleras.** 15 SVG animados
  (`skill-anim/`, generados por `scripts/make-skill-anim.py`) para front lever y parada de manos,
  enlazados por la migración 142 y servidos desde el repo, sin bucket. La pose va quieta porque
  en una escalera se comparan ocho posiciones de un vistazo; solo se mueve donde el movimiento es
  el ejercicio. Revisadas en el navegador a tamaño de hoja y a 58 px. El video real de cada
  escalón las pisa en cuanto se suba desde Admin: la 142 solo escribe donde está vacío.
- **2 nov 2026** — **Las siete escaleras dibujadas**: 20 animaciones más (planche, elevaciones a
  front lever, muscle-up, back lever y curl nórdico) y la migración 143 que las enlaza. Se añadió
  la marca de orientación —sin ella un front lever y un back lever son el mismo monigote— y los
  brazos que se doblan, que es lo que distingue los escalones del muscle-up. Revisadas las 35 en
  el navegador: ahí se vieron y se corrigieron un nórdico que pasaba el ciclo de pie en vez de
  bajando, y un muscle-up negativo que giraba 150° sobre el hombro.
- **2 nov 2026** — Corridas en Supabase la 140, la 142 y la 143 (la 141 ya estaba). Las 35
  animaciones y las 7 portadas quedaron enlazadas.
- **2 nov 2026** — **Entrenar sin coach (Fase 2b).** En Crew nadie tenía escalón (cero filas en
  `coach_student_skills`), así que la pestaña Skills decía «tu coach todavía no te ha puesto
  un escalón» en las siete líneas. Ahora:
  · **Elegir tu escalón**: la escalera se vuelve botones («Toca el escalón en el que vas») con
    la regla de en cuál empezar: el más difícil que ya haces limpio; si dudas, el de abajo.
  · **Entrenar este escalón**: un entreno libre con el nombre del skill y el estándar como
    objetivo (mín. 3 series, 120 s), o el ejercicio agregado al entreno que ya está abierto.
  · **Subir tú**: con el estándar cumplido dos sesiones seguidas aparece «Subir a …». La app
    sigue sin mover nada sola; lo que cambió es quién puede tocar el botón.
  · Lo que puso el coach sigue siendo del coach: migración 144, `set_by` decide de quién es
    la fila. Si el coach pone un escalón sobre una línea que el alumno eligió, pasa a ser suya.
  Dos arreglos de paso, que eran la razón de que entrenar un escalón no contara: las series de
  un ejercicio agregado en vivo (`cat-<slug>`) no llegaban a la escalera, y un aguante agregado
  desde el catálogo pedía kg y reps en vez de segundos.
  **La 144 ya corrió en Supabase** y se probó como alumno, en un bloque que se revirtió:
  elige, sube y hace upsert de lo suyo; no puede escribirse una nota «de tu coach», ni
  ponerle escalón a otra persona, ni firmar como otro; y una vez que el coach toma la línea,
  sus update y delete no tocan nada y su upsert falla. El historial registró los cuatro
  movimientos.
