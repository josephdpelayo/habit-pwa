# Skandi Fit — Las capas de Entrenar: ejercicio → rutina → programa

Auditoría de la pestaña **Entrenar**, y en particular de **Rutinas**, contra el modelo mental que
debería tener: *el programa es la capa más grande; adentro va una rutina por día; adentro de la
rutina van los ejercicios*.

Complementa `PLAN_ENTRENAMIENTO_SKANDI.md`, que resolvió la capa **calendario** (fase T1,
migración 080). Este documento resuelve la capa **plan**, que quedó a medias.

---

## 1. El diagnóstico en una línea

**El modelo está invertido: la rutina es la dueña del día y el programa es solo una fotografía
de eso.** Todos los síntomas que se sienten en la pantalla salen de ahí.

Hoy la fuente de la verdad de "qué toca el martes" es `skandi_templates.weekday` — una columna
que vive en la RUTINA. `skandi_programs` + `skandi_program_days` (migración 069) guardan una copia
de esa columna. Cargar un programa (`applyProgram`, skandi.html:3021) no "aplica" nada: recorre
**todas** mis rutinas y les reescribe `weekday` hasta que la foto vuelve a ser cierta.

La migración 069 lo dice explícitamente y con honestidad: *"programs are deliberately NOT a second
scheduling system"*. Fue la decisión correcta para no romper nada en su momento. Ya no alcanza.

---

## 2. Los síntomas, con su causa

| Lo que se ve en la pantalla | La causa en el código |
|---|---|
| La tarjeta del programa no se puede tocar | `programCardHtml()` (2880) es un `<section class="card">` **sin `onclick`**. El único camino es el botón «Cambiar». Compárala con `trainingBlockCardHtml()` (2429), que sí es `click-card` |
| No existe «crear un programa» | El único camino es `openProgramForm()` → guarda `currentWeekSnapshot()`. Un programa **solo puede nacer de una semana que ya armaste a mano**. No hay pantalla donde digas "lunes esto, martes lo otro" |
| No se pueden editar los días del programa | `programDayRowsHtml()` (2871) pinta `<span>`, sin `onclick`. Para cambiar el martes del programa hay que: cargarlo → mover la rutina en la semana real → «Actualizar el programa con esta semana». **Editas el mundo para editar el plan** |
| El programa no dice cuántas semanas dura | `skandi_programs` no tiene columna de semanas. La duración vive en `skandi_training_blocks.build_weeks`, se pregunta **una sola vez** al cargar (`openProgramLoadConfirm`, 3003) y se guarda en otra fila ligada por `program_id` (migración 100). Un programa que nunca cargaste no tiene periodicidad ninguna |
| «Semana 3 de 6» no aparece junto al programa | `trainingBlockCardHtml()` se renderiza en **Hoy** (3357) y en **Inicio** (2821), nunca en Rutinas. La periodicidad y el programa viven en pestañas distintas |
| La semana 1 no puede ser distinta de la semana 4 | `skandi_program_days` tiene `unique(program_id, weekday)`: 7 filas, una semana, punto. No hay índice de semana |
| Una rutina solo puede vivir en un día | `weekday` es una sola columna en la rutina. "Pierna A" no puede ser lunes en un programa y jueves en otro sin reescribirse |
| Rutinas que se caen del día solas | Cada camino de asignación (`saveTemplate`, `assignOwnRoutineToDay`, `forkTemplateToDay`) **empuja** a `weekday = null` la rutina que ya ocupaba el día, sin avisar. No hay índice único en `(user_id, weekday)`: la regla "una rutina por día" es una convención del cliente, no de la base |
| La semana de descarga solo baja los kilos | `deloadAdjustedWeight()` (2333) multiplica por 0.7 y ya. No hay forma de decir "en la descarga entreno estas otras rutinas" o "las mismas con menos series" |

---

## 3. Los tres verbos están escondidos, y el botón más grande miente

| Quiero… | Dónde está hoy |
|---|---|
| **Crear un ejercicio** | Solo en **Catálogo** → «+ Ejercicio» (`openExerciseBuilder`, 7783). Desde Rutinas no se llega |
| **Crear una rutina** | Botón chico «+ Nueva rutina» junto al encabezado «Mis rutinas», o «Mejor crear una rutina nueva» al fondo del selector de día |
| **Crear un programa** | Solo dentro de «Cambiar» → hasta abajo del modal: «Guardar esta semana como programa» |

Y el botón grande, azul, arriba a la derecha — **«+ Rutina»** — no crea una rutina: llama
`openDayPicker(todayDow())` (trainView, 3279), que abre un selector de rutinas **que ya existen**
para asignarlas a un día. El botón más visible de la pantalla es el único que no hace lo que dice.

Tres verbos, tres nombres distintos, tres lugares distintos, y ninguno donde se busca.

---

## 4. Los números se contradicen a dos centímetros de distancia

- **«Tu semana — 19 rutinas · 0 planes»**: `routinesTab()` (4071) le pasa a `combinedWeekCard()`
  **todas** mis rutinas, no las 6 que están en la semana. Una tarjeta que se llama "Tu semana"
  cuenta cosas que no están en la semana.
- Justo arriba, el programa dice **«6 rutinas · 0 de resistencia · 6 días»**.
- «0 **planes**» y «0 **de resistencia**» son el mismo concepto con dos nombres, en la misma pantalla.
- Debajo, 19 tarjetas de rutina en una lista plana, sin separar las que están en la semana de las
  que solo están guardadas.

---

## 5. Hay dos formas de aplicar un programa y no se distinguen

| | `applyProgram` (3021) | `applyProgramToWeek` (3615) |
|---|---|---|
| Dónde | Rutinas → Cambiar → Cargar | Calendario → menú de la semana → «Cargar programa en esta semana» |
| Qué hace | Reescribe `weekday` de **todas** las rutinas, cambia `is_active`, **inserta una fila nueva** en `skandi_training_blocks` (reinicia el conteo de descarga desde hoy) | Escribe filas en `skandi_planned_sessions` con `source='program'` **solo para esos 7 días**. No toca `is_active` ni el bloque |
| Alcance | Para siempre | Una semana |

Las dos son correctas y contestan preguntas distintas. El problema es que nada en la interfaz dice
cuál estás usando, y la segunda está enterrada en otra pestaña.

---

## 6. El modelo que hace falta

```
ejercicio            skandi_exercises            un movimiento
   ↓
rutina               skandi_templates            el entrenamiento de UN día
   + ejercicios      skandi_template_items       series, reps, descanso, RIR
   ↓
programa             skandi_programs             el plan: N semanas + descarga
   + días            skandi_program_days         qué rutina toca cada día de cada semana
   ↓
calendario           skandi_planned_sessions     qué toca el martes 9 de septiembre
   ↓
sesión               skandi_sessions / _sets     lo que de verdad hiciste
```

Las cinco tablas ya existen. **Lo único que falta es invertir quién manda entre la rutina y el
programa**, y darle al programa las dos columnas que le faltan (duración y semana).

---

## 7. La propuesta

### 7.1 Migración 102 — el programa se vuelve el plan

```sql
alter table public.skandi_programs
  add column if not exists weeks       integer not null default 4 check (weeks between 1 and 16),
  add column if not exists deload_week boolean not null default true,
  add column if not exists start_date  date;   -- cuándo arrancó el ciclo activo

alter table public.skandi_program_days
  add column if not exists week_index integer not null default 0,  -- 0 = todas las semanas
  add column if not exists sort_order integer not null default 0;  -- dos sesiones el mismo día

-- la unicidad deja de ser "7 filas" y pasa a ser "una ranura por semana/día/orden"
alter table public.skandi_program_days drop constraint if exists skandi_program_days_program_id_weekday_key;
create unique index if not exists idx_skandi_program_days_slot
  on public.skandi_program_days(program_id, week_index, weekday, sort_order);
```

**`week_index = 0` significa "se repite todas las semanas".** Un programa normal son 7 filas con
`week_index = 0` y ya. Uno ondulante agrega filas con `week_index = 2` para los días donde la
semana 2 se aparta del patrón. La regla de resolución es de una línea: *para la semana N, una fila
con `week_index = N` gana sobre la de `week_index = 0`; si no hay ninguna, ese día es descanso.*

Eso permite las tres cosas que hoy no se pueden expresar, sin inventar un cuarto nivel:
duración, semanas distintas entre sí, y descarga con contenido propio (`week_index = weeks + 1`).

### 7.2 Quién estampa el calendario

`skandi_ensure_week` (migración 080) hoy lee `skandi_templates.weekday`. Pasa a leer, **en este
orden**:

1. si hay un programa activo con `start_date`, la semana que le toca a esa fecha
   (`floor((lunes - start_date)/7) + 1`, hasta `weeks + (deload_week ? 1 : 0)`; al terminar,
   se detiene y pide arrancar el ciclo siguiente, no se repite solo);
2. si no, `weekday` — exactamente como hoy.

Así, quien nunca hizo un programa sigue funcionando igual, y "inyectar el programa al calendario"
deja de ser una acción aparte: **el programa activo es lo que el calendario estampa**, semana por
semana al abrirla. No se materializan N semanas de golpe — eso ya está descartado en
`PLAN_ENTRENAMIENTO_SKANDI.md` §10 y sigue siendo lo correcto: un cambio en una rutina tendría que
reescribir todas las semanas por delante.

### 7.3 Qué pasa con `skandi_templates.weekday`

Se queda, y deja de ser la fuente de la verdad para quien tenga programa activo. En Rutinas pasa a
leerse como **"día sugerido"** de una rutina suelta. Se retira en una migración posterior, cuando
nada la lea — nunca en la misma que cambia quién la lee (misma regla que el documento del
calendario aplicó a `skandi_training_blocks`).

Ganancia inmediata: se acaban los "empujones" silenciosos. Una rutina puede estar en el lunes de un
programa y en el jueves de otro, porque el día ya no es un atributo de la rutina.

### 7.4 Qué pasa con `skandi_training_blocks`

`weeks` + `deload_week` + `start_date` en el programa contienen todo lo que
`trainingBlockWeekInfo()` necesita. La tabla se queda como está para los bloques sueltos (sin
programa detrás) y para la historia; `trainingBlockWeekInfo()` prefiere el programa activo cuando
tiene `start_date`. Esto además le quita a la migración 100 su rareza: el enlace deja de ser un
parche y el bloque pasa a ser lo que siempre fue, un ciclo sin plan.

> **Decisión pendiente:** `PLAN_ENTRENAMIENTO_SKANDI.md` §3 reserva la fase T3 para
> `skandi_seasons` + `skandi_plan_weeks`, que también modela semanas con fase. `week_index` en el
> programa es la **plantilla** del ciclo; `skandi_plan_weeks` sería la **instancia fechada** con
> fase y horas objetivo. Construir las dos es garantía de que un día se contradigan. Recomendación:
> construir la del programa, y que T3 —si algún día llega una carrera con fecha— lea estas mismas
> filas en vez de duplicarlas.

---

## 8. La interfaz que sale de eso

**Rutinas se reordena para que se lean las tres capas, de arriba abajo.**

Un solo botón arriba: **«+ Crear»**, con las tres opciones, en este orden y con esta explicación:

| | |
|---|---|
| **Programa** | Un plan de varias semanas. Eliges qué toca cada día y cuánto dura |
| **Rutina** | El entrenamiento de un día. Eliges los ejercicios, series y reps |
| **Ejercicio** | Un movimiento nuevo para el catálogo |

Y desaparece el «+ Rutina» que abría el selector de días — esa acción («poner una rutina que ya
tengo en un día») vive dentro del editor del programa, que es donde tiene sentido.

**1 · Programa** — tarjeta tocable (`click-card`, como la del bloque). Abre la hoja del programa:

- nombre y notas;
- **«Semana 3 de 6 · descarga en 3 semanas»** — la información que hoy está en otra pestaña;
- selector de semana `S1 · S2 · S3 · S4 · D` (oculto mientras el programa sea igual todas las
  semanas, que es el caso normal);
- **las 7 filas del día, cada una tocable**: `LUN → Front Lever A + Pull` → cambiar rutina /
  agregar plan de resistencia / dejar en descanso;
- acciones: activar, duplicar, renombrar, borrar.

**2 · Tu semana** — el grid de 7 días que ya existe, con el contador arreglado (los días ocupados,
no todas mis rutinas) y una línea que diga qué programa la está generando.

**3 · Mis rutinas** — agrupadas en «En tu programa» / «Sueltas» / «De la tripulación», en vez de 19
tarjetas planas.

---

## 9. Fases

| Fase | Qué entrega | Migración | Tamaño |
|---|---|---|---|
| **P1** | **Hacer visible y editable lo que ya existe.** Botón «+ Crear» con los tres verbos; arreglar «+ Rutina»; tarjeta del programa tocable; editor de los 7 días del programa **escribiendo directo** `skandi_program_days`; semana/descarga visibles en Rutinas; contadores arreglados; «Mis rutinas» agrupadas | ninguna | 1 sesión |
| **P2** | **Invertir la propiedad.** `weeks`/`deload_week`/`start_date`/`week_index`/`sort_order`; `skandi_ensure_week` estampa desde el programa activo; `weekday` pasa a "día sugerido" | 102 | 2 sesiones |
| **P3** | **Periodización de verdad.** Semanas distintas entre sí, descarga con contenido propio, adherencia por ciclo, fase por semana en el calendario | 103 | 1–2 sesiones |

**P1 no espera a P2 y no la estorba.** Mientras el modelo siga invertido, el editor de días del
programa **activo** escribe los dos lados (`skandi_program_days` y el `weekday` correspondiente),
que es exactamente lo que hoy hace activar el programa, pero un día a la vez. Cuando P2 invierta la
propiedad, esa segunda escritura se borra y la pantalla no cambia.

---

## 10. Lo que deliberadamente no hacemos

| No hacemos | Por qué |
|---|---|
| Materializar las N semanas del programa en el calendario al activarlo | Cambiar una rutina obligaría a reescribir el ciclo entero. Se estampa la semana al abrirla, como ya hace `skandi_ensure_week` |
| Un cuarto nivel (mesociclo / temporada) encima del programa | `weeks` + `week_index` ya expresan un mesociclo. Un nivel más es una pantalla más que nadie abre |
| Borrar `skandi_templates.weekday` en la 102 | Deja el rollback sin salida, y toda la app sin programa activo depende de esa columna |
| Copiar la rutina al meterla a un programa | Dos programas que usan "Pierna A" deben ver la MISMA rutina. Si se copiara, arreglar un ejercicio habría que hacerlo dos veces |
| Índice único en `(user_id, weekday)` | Es la restricción del modelo viejo. En el modelo nuevo el día no es de la rutina, así que la restricción correcta es la del programa (`idx_skandi_program_days_slot`) |

---

## 11. Bitácora

**2026-08-25 — P2 implementada y migración 102 ejecutada en Supabase.**

- `skandi_programs` ya contiene `weeks`, `deload_week` y `start_date`; `skandi_program_days`
  contiene `week_index` y `sort_order`, y la unicidad ahora es por ranura de semana/día/orden.
- `skandi_week_slots()` concentra la resolución de una semana: una excepción de la semana N
  reemplaza el día base completo. `skandi_ensure_week()` usa el programa activo y conserva
  `weekday` como respaldo cuando no hay uno.
- El ciclo no se repite solo. Al pasar su última semana, tanto el cliente como el RPC dejan de
  estampar sesiones; esto conserva la decisión que ya existía desde la migración 066.
- Cargar un programa ya no recorre ni reescribe las rutinas. Activa el programa, guarda su
  duración y fecha de inicio, y el calendario se actualiza desde ese plan.
- La duración y la descarga se pueden definir al crear, editar o reiniciar un programa. El
  cálculo compartido de semana/descarga prefiere el programa activo; los bloques sueltos siguen
  funcionando para quien no tenga programa.
- Todos los caminos de asignación de una rutina o un plan de resistencia escriben la ranura del
  programa activo. `weekday` queda intacto como día sugerido y camino de compatibilidad.
- Verificado con el parser de PostgreSQL 17.7, sintaxis del JavaScript inline y 20 aserciones del
  motor de resolución para semana base, excepción semanal, descarga y ciclo terminado. En la
  base remota quedaron las cinco columnas, el índice y las dos funciones; la función devuelve
  6 ranuras para la semana base y 0 para un ciclo terminado.

El programa que ya estaba activo quedó sin `start_date` a propósito (no tenía bloque enlazado del
que recuperar una fecha): conserva la semana anterior hasta que el miembro toque «Iniciar ciclo».
Después sigue **P3** (editor de semanas distintas y descarga con contenido propio).

**2026-08-25 — P1 implementada (solo interfaz, sin migración).** En `skandi.html`:

- **«+ Crear»** sustituye al «+ Rutina» que abría el selector de días. Abre las tres capas en
  orden de tamaño: programa → rutina → ejercicio. Los tres verbos ya no viven en tres pantallas.
- **La tarjeta del programa es `click-card`** y abre `openProgramSheet()`: nombre, notas, en qué
  semana del ciclo va, y los siete días **editables uno por uno** (`openProgramDayEditor` →
  `setProgramDay`). Activar, renombrar, duplicar y borrar viven ahí.
- El ciclo (`programCycleLine`) **sustituye** al resumen en la tarjeta en vez de sumarse: a 375 px
  las dos líneas se partían en cuatro, y «4 rutinas · 1 de resistencia» ya está en «Tu semana».
- **`setProgramDay` escribe los dos lados** mientras el programa esté cargado: la ranura en
  `skandi_program_days` y el `weekday` de la rutina (`mirrorProgramDayToWeek`). Esa segunda mitad
  es el puente hasta P2 — sin ella, editar el programa activo dejaría la foto y la semana en
  desacuerdo y la tarjeta diría «tu semana ya no coincide» por un cambio hecho a propósito.
  Cuando el programa sea el dueño del plan, se borra y la pantalla no cambia.
- **Un programa ya puede nacer en blanco** (`programStartMode`), no solo copiando la semana. El
  blanco nace inactivo —activar un programa sin días vaciaría la semana— y se abre su hoja al
  guardar. El copiado de la semana sigue naciendo cargado, como antes.
- Crear una rutina desde un día del programa (`createRoutineForProgramDay` +
  `pendingProgramSlot`) la deja asignada a esa ranura al guardarla. La intención se cancela en
  `closeModal`.
- «Tu semana» cuenta **días ocupados**, no el catálogo (decía «19 rutinas» arriba de una
  cuadrícula de 7), y usa «de resistencia» en vez de «planes» — mismo nombre que el programa.
  `common.plans_*` quedó sin uso y se retiró, junto con `pgm.saveWeek` y `train.addRoutine`.
- «Mis rutinas» va agrupada en «En tu semana» / «Sin día asignado» / tripulación.
- Verificado con 44 aserciones corriendo el `<script>` de `skandi.html` en Node con `document` y
  Supabase falsos (mismo patrón que T1), más una revisión visual a 375 px de la pestaña, la hoja
  del programa, el editor de día, el selector de crear y el formulario nuevo.

Pendiente: **P2** (migración 102, invertir la propiedad) y la decisión sobre `week_index` vs
`skandi_plan_weeks` del §7.4.


**2026-08-25 — Auditoría de Entrenar / Rutinas.** El programa existe como tabla desde la 069 pero
nunca fue el dueño del plan: es una fotografía de `skandi_templates.weekday`. De ahí salen los seis
síntomas del §2 (tarjeta muerta, sin crear, sin editar, sin duración, una sola semana, rutinas que
se caen del día). Propuesta: invertir la propiedad en la 102 y, antes de eso, una fase de interfaz
sin migración que ya haga tocable y editable lo que hay. Pendiente de decidir contigo: si
`week_index` sustituye a `skandi_plan_weeks` de la fase T3 del otro documento.
