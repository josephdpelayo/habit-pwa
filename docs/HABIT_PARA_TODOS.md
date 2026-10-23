# HABIT para todos — de la app del gym a la app donde entrena cualquiera

> Documento de planeación. Fecha: 2026-10-19. Dueño: Joseph.
> Este archivo es la fuente de verdad del proyecto: se actualiza conforme avanzan las fases
> (bitácora al final).
> Relacionados: `PLAN_ENTRENAMIENTO_SKANDI.md` (calendario, resistencia estructurada, Hyrox),
> `CAPAS_ENTRENAR_SKANDI.md` (programa → semana → rutina), `PROYECTO_SKANDI_V2.md` (nutrición).

---

## 0. En cinco líneas

1. Hoy hay **dos apps que entrenan** y ninguna hace todo. HABIT tiene la fuerza, el coach, el
   catálogo con videos y el registro offline; Skandi tiene el cardio estructurado, la calistenia
   por niveles, Strava/Garmin, la carga y la comida.
2. **HABIT se queda como la app.** Skandi deja de recibir funciones de entrenamiento; no se borra
   nada.
3. **Lo que es de la persona** (actividades de cardio, integraciones, zonas, peso, bienestar) ya
   vive en tablas por usuario y HABIT las lee tal cual. **Lo que es del modelo de entrenamiento**
   (rutinas, calendario, series, PRs) se queda en el de HABIT y crece.
4. El primer candado es una línea: Entrenar exige membresía del gym (`MEMBER_LOCKED_VIEWS`,
   `app.html:5619`). Quitarlo es fácil; quitarlo **seguro** exige que la migración 120 esté en
   producción primero.
5. **Hito 1 (9 nov):** tu bloque en tierra —semanas 4–6 de Carlos más la calistenia de Alge— se
   lleva en HABIT, no en Skandi.

---

## 1. Qué queremos

Dos objetivos que se resuelven con el mismo trabajo:

- **Tú manejas todo tu entrenamiento desde HABIT.** Calistenia de Alge, carrera de Carlos, Hyrox
  suelto, piernas de gym, movilidad, y lo que registra el Garmin. Hoy eso vive en Skandi más
  Intervals.icu más PDFs.
- **Cualquiera puede usar HABIT para entrenar**, vaya o no al gym de Mazatlán: seguir una rutina o
  un programa, registrar sus pesos, ver su progreso. Pesas, funcional, calistenia, carrera.

### Las cuatro personas que la app tiene que servir

| Persona | Qué necesita | Hoy |
|---|---|---|
| **Socio del gym** | Reservar, abrir la puerta, su rutina, su progreso | ✅ Cubierto |
| **Cliente de coaching** (David) | Lo anterior + plan del coach, chat, hábitos, ayuno | ✅ Cubierto (`coaching_beta`) |
| **Atleta híbrido** (tú) | Fuerza + calistenia por niveles + carrera estructurada + reloj, con **dos coaches distintos** | ❌ Partido en dos apps |
| **Alguien que nunca pisará Mazatlán** | Entra, elige un programa según su equipo y nivel, entrena, registra, ve progreso | ❌ No puede ni abrir Entrenar |

El principio: **una app, tres puertas** — el gym, el coach, y tú solo. Ninguna puerta debe
estorbarle a las otras.

---

## 2. Punto de partida real (auditoría del repo, 19 oct 2026)

### 2.1 Qué tiene cada app

| Capacidad | HABIT | Skandi | Nota |
|---|---|---|---|
| Rutinas propias, del gym y del coach | ✅ `boards` | ✅ `skandi_templates` | HABIT es más maduro: versiones (117), básicas (116/122), color por origen |
| Semana + programa por ciclos con fases | ✅ 114/115 | ✅ 102/103 | Mismo diseño, ya convergieron |
| **Dos programas activos a la vez** (fuerza + carrera) | ❌ uno solo (`idx_coaching_programs_one_active`, 070) | ✅ pistas (110) | Tu caso exacto: Alge + Carlos |
| **Más de una sesión el mismo día** en el plan | ⚠️ el calendario sí (034); la plantilla no (`unique(user_id, dow)`, 039) ni el programa (`(program_id, week_index, dow)`, 115) | ✅ `sort_order` (080) | |
| Registro de series: peso, reps, tiempo, RIR | ✅ 117 (`metric_type` reps/time/distance) | ✅ | |
| Offline: series pendientes que se sincronizan | ✅ `habit-training.js` | ✅ `skandi-outbox.js` | |
| Pirámides, superseries | ✅ | ❌ | |
| Catálogo con videos, duplicados, fusión | ✅ Admin → Ejercicios (123–125) | ⚠️ | 071 ya trajo la calistenia de Skandi al catálogo de HABIT |
| Figura de recuperación muscular | ✅ (usa `skandi-recovery.js`) | ✅ | HABIT le pasa `activities:[]` (`app.html:9079`): el cardio no cuenta |
| PRs, volumen por músculo, gráficas | ✅ Progreso | ✅ | |
| Coach: chat, hábitos, ayuno, feedback, alertas | ✅ | ❌ | Solo HABIT |
| **Calistenia por niveles** (tuck → straddle → full), calidad de forma, lados, clips, tempo | ❌ | ✅ 078/079/107/108 | La lógica vive inline en `skandi.html` (`skillLevel`, `progressionReadiness`…), no en un módulo |
| **Cardio**: correr, bici, nadar, remo, HIIT, Hyrox | ❌ | ✅ `skandi_external_activities` (046/104) | |
| **Sesiones estructuradas** (6×400 Z4, zonas → ritmo) | ❌ | ✅ `skandi-plan.js` (104) | |
| **Strava / Intervals.icu (Garmin)** | ❌ | ✅ 081/082 | Strava entra por webhook (servidor); Intervals solo sincroniza al abrir Skandi |
| Carga aguda/crónica, readiness, el porqué del día, carga articular | ❌ | ✅ `skandi-load.js`, `skandi-brief.js`, `skandi-joint-load.js` | |
| Peso corporal, medidas, fotos de progreso | ❌ | ✅ 067/090 | |
| Nutrición | ❌ | ✅ | Fuera del alcance de este proyecto (§3, D7) |
| Idiomas | Solo español | es/en (`t()`) | |

**Lo que trabaja a favor:**

- Los módulos puros de Skandi (`skandi-plan.js`, `skandi-load.js`, `skandi-brief.js`,
  `skandi-joint-load.js`) **ya están en el `SHELL` de `sw.js`**. HABIT los puede cargar con un
  `<script>` y funcionan offline desde el primer día.
- `skandi-recovery.js` y `body-figure.js` ya los usa HABIT. Pasarle actividades al motor es
  cambiar un `[]`.
- Las tablas de Skandi que describen **a la persona** (no a la app) tienen RLS por `user_id`
  sobre el mismo `auth.users`. HABIT las puede leer y escribir hoy, sin migración.
- `api/skandi.js` ya es un router por `action`: HABIT puede llamar `intervals-sync` o
  `strava-connect` con el mismo JWT. Ninguna función nueva.

### 2.2 Los candados que hoy cierran HABIT a quien no es socio

| Candado | Dónde | Qué hace |
|---|---|---|
| Entrenar exige membresía | `MEMBER_LOCKED_VIEWS = ['book','rutinas','comunidad']` (`app.html:5619`) → `canUseMemberViews()` → `hasActive()` (créditos y vigencia) | Sin plan, tocar Entrenar te regresa a Inicio con un aviso |
| Los programas del gym no se ven | El socio carga solo `.eq('user_id', sbUser.id)` (`app.html:8928`); las plantillas (`user_id` null, 114) solo las ve el coach | No hay biblioteca que elegir |
| El registro habla de gym | `completeRegister()` manda push "👤 Nuevo socio" con código de acceso al admin; la bienvenida habla de reservas; los términos son el reglamento del gym (`#terms-modal`) | Con público abierto, el admin recibe una notificación por cada descarga |
| Rutinas básicas por trigger | 122 asigna las básicas a **cada perfil nuevo** | Pensadas para el equipo del gym; a quien entrena en casa no le sirven |
| Borrar la cuenta | `api/delete-user.js` exige rol admin | Apple pide borrado desde la propia app para publicar en la tienda |
| Inicio | Puerta, código, reservas, membresía | Para quien no es socio, la pantalla de entrada está vacía |

### 2.3 Lo que el modelo de HABIT asume y hay que aflojar

- **Una fila de `coaching_schedule` "es" una rutina.** 30 lugares en `app.html` y 17 migraciones
  la leen así (abrir la hoja de entreno, sembrar series, adherencia, panel del coach).
- **`coaching_program_days.board_id` null significa descanso** (115). Un día de carrera no tiene
  rutina, así que hoy se leería como descanso.
- **Un programa activo por socio**, una rutina por día en la plantilla, una por día en el
  programa (§2.1).

### 2.4 Trabajo en curso que condiciona esto

`git status` del 19 oct: la **120** (`bookings` del lado del servidor) y la 121 están sin
commitear, y `app.html` tiene cambios sin commitear. Según `CLAUDE.md`, desde la 120 el socio ya
no escribe `bookings`/`slot_occupancy`/`payments` y no puede tocar `credits`/`plan_*` de su perfil.
**Antes de la 120 sí podía.** Como la puerta se abre por reserva (`validate-access-code.js`,
`request-door-open.js`), una cuenta gratuita con acceso directo a la API podía darse una reserva o
créditos. Hoy el registro ya está abierto a cualquiera, así que el riesgo existe; promocionar la
app lo multiplica. **La 120 en producción es requisito de la Fase 0.**

---

## 3. Decisiones

✅ **Confirmadas el 19 oct 2026.** Si cambias alguna, se reescribe la sección que depende de ella.

| # | Decisión | Recomendación | Por qué |
|---|---|---|---|
| D1 | ¿Qué pasa con Skandi? | **Mantenimiento.** Sigue funcionando para quien lo use; no recibe funciones de entrenamiento nuevas; no se borra nada | Dos apps que entrenan son dos veces cada arreglo. La historia de Skandi se puede seguir consultando ahí |
| D2 | ¿HABIT lee las tablas de Skandi o reconstruye? | **Depende de qué describa la tabla** (§4.1): lo de la persona se comparte tal cual; lo del modelo de entrenamiento se queda en el de HABIT | Que HABIT lea `skandi_templates`/`skandi_sessions` sería tener dos modelos de la misma cosa, el tipo de bug que ya costó la 104 |
| D3 | ¿Renombrar las tablas `skandi_*` compartidas? | **No, por ahora.** Se documenta en `CLAUDE.md` que son "de la persona" | Renombrar toca el upsert de Strava, varios RPC y las dos apps a la vez, y no cambia nada para el usuario. Si algún día estorba, una vista `security_invoker` con el nombre nuevo |
| D4 | ¿Cómo se distingue a quien solo usa la app? | **Sin rol nuevo.** Entrenar queda abierto a cualquier cuenta; Reservar, puerta y Comunidad siguen detrás de `hasActive()`. Se agrega `profiles.joined_as` (`gym`/`app`) y una tabla privada `training_profiles` (§4.2) | El acceso al gym ya lo decide la membresía; un rol nuevo duplicaría esa regla. `joined_as` es para métricas y para no avisarle al admin de cada descarga |
| D5 | ¿Se cobra? | **Entrenar gratis.** Se cobran la membresía del gym (ya existe) y el **coaching en línea** (Stripe en web). Un plan premium "HABIT+" solo cuando haya uso que lo justifique | Lo gratis llena el embudo; lo que vale dinero es la persona (David, el gym). Ver §9.1 sobre las reglas de Apple |
| D6 | ¿Comunidad abierta al público? | ~~No en v1~~ → **reemplazada por D13 (23 oct)** | — |
| D7 | ¿Nutrición en HABIT? | **No en este proyecto.** Tú sigues usando Comida de Skandi; se evalúa en la Fase 8 | Comida es la mitad del código de Skandi y cuesta tokens por usuario. Abrirla al público es otro proyecto con su propio presupuesto |
| D8 | ¿Idioma? | **Español primero.** Inglés en la Fase 8 | HABIT no tiene `t()`; meterlo ahora toca cada pantalla y no ayuda a lanzar en México |
| D9 | ¿Dónde vive el código nuevo? | **Matemáticas en módulos puros, UI en `app.html`.** HABIT carga los módulos de Skandi como están; lo que hoy está inline en `skandi.html` (niveles de calistenia) se extrae primero a un módulo | Es la regla que ya funciona en el repo. `app.html` tiene 19,350 líneas; todo lo que se pueda probar en Node no debe crecerlo |
| D10 | ¿Endpoints nuevos? | **Ninguno.** Todo como RPC o como `action` en routers existentes | Techo de 12 funciones en Vercel Hobby (ver §9.2) |
| D11 | ¿Una app o dos? (23 oct) | **Dos apps, una cuenta, un código.** **HABIT** (el gym: reservar, la puerta, entrenar) y **HABIT Crew** (entrenar y la comunidad, para cualquiera). Las dos son el mismo `app.html`: Vercel reescribe `/crew` a ese archivo y la marca sale de la ruta. Misma base, así que la misma cuenta sirve en las dos | Entrenar son miles de líneas: copiarlo a otra app sería arreglar todo dos veces. Así cada mejora llega a las dos, y quien es del gym tiene todo lo de Crew sin registrarse otra vez |
| D12 | ¿Cómo se llama? (23 oct) | **HABIT Crew**, en `habittraininghub.app/crew`. Ícono: el de HABIT invertido (aro negro sobre blanco) | Cabe completo bajo el ícono del iPhone (≈12 caracteres; "HABIT Community" se cortaba), suena a grupo y funciona como #HABITcrew. La dirección dentro del dominio actual no cuesta y se puede cambiar después |
| D13 | ¿Comunidad abierta? (23 oct) | **Sí: una sola comunidad, abierta a toda cuenta, en las dos apps.** Reemplaza a D6 | Si Crew la abre, cerrarla en HABIT a la misma persona no tendría sentido. Pide **moderación** (reportar, bloquear) antes de promocionar: Apple la exige a toda app con contenido de usuarios. Hecha en la **128** (ver bitácora, 23 oct) |

### 3.1 Qué tiene cada app (D11–D13)

| | HABIT (`/`) | HABIT Crew (`/crew`) |
|---|---|---|
| Reservar, puerta, membresías, pagos, tienda | ✅ | — (una tarjeta en Inicio abre HABIT) |
| Entrenar: rutinas, semana, programas, progreso | ✅ cualquier cuenta | ✅ |
| Comunidad | ✅ cualquier cuenta | ✅ la misma |
| Coaching (clientes de David) | ✅ | ✅ |
| Admin y recepción | ✅ | — (entran como usuarios; administran desde HABIT) |
| Registro | `joined_as = gym`, reglamento del gym, aviso "Nuevo socio" al admin | `joined_as = app`, términos de la app, onboarding, sin aviso |
| Manifest e íconos | `manifest.json`, `icons/icon-*` | `crew-manifest.json` (`id: /crew`), `icons/crew-*` |

Cada registro manda a la otra app a quien llegó a la equivocada ("¿Entrenas por tu cuenta? Usa
HABIT Crew" / "¿Entrenas en HABIT Mazatlán? Reserva desde la app del gym"). La pregunta "¿Dónde
entrenas?" de la Fase 0 desapareció: la app en la que te registras ya lo dice.

---

## 4. Modelo de datos

### 4.1 La regla de propiedad

| Describe a… | Tablas | Quién la usa |
|---|---|---|
| **La persona** | `skandi_external_activities` (cardio), `skandi_integrations` (tokens), `skandi_settings` (FC máx., umbrales), `skandi_bodyweight_logs`, `skandi_body_measurements`, `skandi_progress_photos`, `skandi_daily_wellness`, buckets `skandi-set-clips` / `skandi-progress-photos` | **Las dos apps, sin copiar.** Una carrera es una carrera, la registre quien la registre |
| **El modelo de entrenamiento de HABIT** | `boards`, `coaching_schedule`, `coaching_session_sets`, `user_scores`, `coaching_programs` / `_days` / `_weeks`, `coaching_week_templates`, `exercise_catalog` | HABIT. Crecen para cubrir lo que hoy solo hace Skandi |
| **El modelo de Skandi** | `skandi_templates`, `skandi_sessions`, `skandi_sets`, `skandi_planned_sessions`, `skandi_programs`… | Solo Skandi. Tu historia se **copia** una vez a HABIT (Fase 6); no se lee en vivo |

**La consecuencia que más importa:** como `skandi_external_activities` es de la persona, lo que hoy
entra por el webhook de Strava **sigue entrando aunque dejes de abrir Skandi**, y HABIT lo ve el
mismo día que lo lea. Tu historial de carreras no se migra: ya está donde tiene que estar.

### 4.2 Migración 127 — Entrenar para todos (Fase 0)

```
profiles
  + joined_as text not null default 'gym' check in ('gym','app')
    -- no signup_source: profiles.source (055) ya existe y dice qué app creó el perfil
    -- los perfiles existentes son del gym; el registro nuevo pregunta

training_profiles                 privada, una fila por usuario (mismo criterio que skandi_settings:
  user_id (PK → profiles)         profiles la leen otros, esto no)
  goal text                       'fuerza' | 'masa' | 'perder_grasa' | 'resistencia' | 'calistenia' | 'salud'
  level text                      'principiante' | 'intermedio' | 'avanzado'
  equipment text[]                'gym_completo' | 'mancuernas' | 'barra_dominadas' | 'peso_corporal' | 'ligas' | 'caminadora'
  days_per_week smallint          1..7
  disciplines text[]              'pesas' | 'funcional' | 'calistenia' | 'carrera' | 'hyrox'
  onboarded_at timestamptz
  RLS: solo el dueño; el admin lee (para métricas y para el coach)
```

Y un cambio a la **122**: el trigger que asigna las rutinas básicas deja de dárselas a quien se
registra como `app` (ellos eligen programa en la biblioteca). Los socios del gym siguen igual.

### 4.3 Migración 128 — Biblioteca pública de programas (Fase 1)

Las plantillas del gym ya existen: un `coaching_programs` con `user_id` null (114). Lo que falta es
que un socio las vea, sepa para quién es cada una y se la pueda aplicar solo.

```
coaching_programs
  + is_public boolean not null default false     -- solo plantillas (user_id null) pueden serlo
  + discipline text                              'pesas' | 'funcional' | 'calistenia' | 'carrera' | 'hibrido'
  + level text, days_per_week smallint, equipment text[]
  + summary text, cover_url text, sort_order int
  RLS: select de user_id null and is_public para cualquier autenticado
       (las rutinas que referencia ya se leen: boards con owner_id null)

start_public_program(p_template_id uuid, p_start_date date)   security definer
  copia programa + días + semanas al usuario (user_id = auth.uid()) y llama a
  apply_coaching_program. Rechaza auth.uid() null; revoke explícito a anon (lección de la 124).
```

Las rutinas **no se copian**: el programa copiado apunta a las rutinas del gym, igual que las
básicas. Si el gym mejora "Empuje A", le llega a todos los que siguen el programa.

### 4.4 Migración 129 — Calendario multidisciplina (Fase 2)

Es la más delicada: toca las tablas que más código lee. Todo nace con un default que deja lo
existente igual (`discipline = 'strength'`, `slot = 0`), así que nada cambia hasta que alguien crea
una fila de cardio.

```
coaching_schedule
  + discipline text not null default 'strength'
      check in ('strength','run','bike','swim','row','walk','hiit','hyrox','mobility')
  + slot smallint not null default 0             -- orden dentro del día
  + structure jsonb                              -- formato de skandi-plan.js (§4 de PLAN_ENTRENAMIENTO_SKANDI)
  + target_duration_min int, target_distance_km numeric(6,2), target_zone smallint, target_rpe smallint
  + activity_id uuid → skandi_external_activities(id) on delete set null
      -- conciliación planeado ↔ hecho; la actividad vive en la tabla de la persona
  board_name sigue not null: para cardio guarda el título ("Q · 6×1 km Z3")

coaching_program_days
  + discipline (incluye 'rest'), slot, structure, title, target_*
  índice único: (program_id, week_index, dow) → (program_id, week_index, dow, slot)
  backfill: toda fila con board_id null pasa a discipline = 'rest'
  -- el marcador de descanso deja de ser "board_id null" y se vuelve explícito: un día de
  -- carrera tampoco tiene rutina, y con la regla vieja se leería como descanso

coaching_week_templates
  + discipline, slot, structure, title
  unique(user_id, dow) → unique(user_id, dow, slot)

coaching_programs
  + track text not null default 'mixed' check in ('strength','endurance','mixed')
  idx_coaching_programs_one_active → uno activo por pista
  + trigger: un 'mixed' activo excluye a los otros dos (mismo patrón que la 110 de Skandi)
```

**Reglas que no cambian de significado:**

- **Reemplazo, no mezcla**, ahora a nivel día: si la semana N tiene filas para el martes, esas
  filas son todo el martes (todos sus slots). `coaching_week_slots()` sigue siendo el único lugar
  donde vive la regla.
- `ensure_coaching_week_from_template` se **extiende desde su cuerpo vigente**, nunca desde una
  copia vieja. Es exactamente la lección de la 104 de Skandi (ver memoria
  `project_skandi_ensure_week_regression`): partir de una copia borró la resolución por programa
  durante semanas sin que nadie lo notara.
- `start_training_session` rechaza filas que no sean `strength`/`mobility`: una carrera no abre la
  hoja de series.

**El cardio se registra en `skandi_external_activities`** (ya acepta `hiit` y `hyrox` desde la
104). HABIT concilia del lado del cliente, igual que `reconcilePlanned()` en Skandi: al cargar la
semana, una actividad sin enlazar del mismo día y disciplina se enlaza a la fila planeada.

### 4.5 Migración 130 — Calistenia por niveles (Fase 3)

Los mismos conceptos de Skandi (078/079), en el catálogo de HABIT:

```
exercise_catalog
  + progression_group text, progression_rank smallint
  + progression_target numeric, progression_target_sets smallint, progression_criteria text
  + track_quality boolean, unilateral boolean

coaching_session_sets
  + form_quality smallint check 1..10
  + side text check in ('L','R')
  + clip_path text          -- bucket skandi-set-clips: es por persona, carpeta por uid (079)
```

El nivel sigue siendo **derivado, no guardado**: `skillLevel() = rank + min(1, marca / meta)`.
Antes de la migración se extraen de `skandi.html` a un módulo puro (`training-skills.js`) las
funciones `skillLevel`, `progressionReadiness`, `qualifyingSetCount`, `skillTutByWeek` y
compañía, y **las dos apps lo cargan**. Así no hay una segunda copia de la regla de subir de nivel.

Las escaleras que se agregaron después de la 071 (front lever half-lay en la 107, HSPU y back lever
en la 108) se importan al catálogo con el mismo criterio de la 071: traducir el nombre, dejar el
inglés como alias, no duplicar lo que ya existe (usar `exerciseSignature`).

Lastre: revisar cómo lo trata hoy `setStimulusUnits` (memoria `project_injury_prevention_plan`)
antes de agregar una columna; si ya se resuelve con el peso de la serie más el peso corporal, no
hace falta.

### 4.6 Migración 131 — Check-in diario (Fase 5)

`skandi_daily_wellness` (085) ya es de la persona. Se revisa si cubre las tres preguntas que usas a
bordo (sueño, piernas, ganas: bien/normal/mal) y las horas en cama; si no, se agregan columnas ahí,
no una tabla nueva.

### 4.7 Migración 132 — Tu mudanza (Fase 6)

Una migración tuya, con tu correo, como la 106 o la 119:

- `skandi_templates` + items → `boards` con `owner_id` = tú, ejercicios mapeados al
  `exercise_catalog` (alias en inglés de la 071, luego `exerciseSignature`). Lo que no case se
  lista en un `NOTICE`, no se inventa (memoria `feedback_skandi_exercise_slug_verification`).
- `skandi_programs` → `coaching_programs` con su pista, ciclo y semanas.
- `skandi_sessions` + `skandi_sets` → `coaching_schedule` (`status = 'done'`) +
  `coaching_session_sets` + `user_scores`, para que tus PRs y gráficas sigan donde iban.
- `skandi_progression_state` / eventos: no se copian; el nivel se deriva de las series (§4.5).
- Idempotente: correrla dos veces no duplica (anti-join por fecha y ejercicio).

---

## 5. Fases

Tamaños: **S** = una sesión de trabajo, **M** = dos a cuatro, **L** = cinco o más. Estimación
gruesa, sin contar la creación de contenido.

| Fase | Qué entrega | Migración | Tamaño | Depende de |
|---|---|---|---|---|
| **0** | Entrenar abierto a cualquier cuenta | 127 | M | 120 en producción |
| **1** | Biblioteca pública de programas | 128 | M + contenido | 0 |
| **2** | Calendario multidisciplina y cardio | 129 | L | 0 |
| **3** | Calistenia por niveles | 130 | M | 0 |
| **4** | Strava e Intervals desde HABIT; mandar entrenos al reloj | — | M | 2 |
| **5** | Carga, readiness, el porqué del día, peso/medidas/fotos | 131 | M | 2 |
| **6** | Tu mudanza y Skandi a mantenimiento | 132 | M | 2, 3 |
| **7** | Lanzamiento: landing, legal, tiendas, cobro, métricas | — | M + no-código | 0, 1 |
| **8** | Opcional: nutrición, inglés, comunidad abierta, retos | — | L | 7 |

### Hito 1 — 9 nov: tu bloque en tierra corre en HABIT

Lo mínimo para que dejes Skandi al bajar del barco:

- Fase 0 completa.
- Fase 2 sin Strava propio: calendario con slots y disciplinas, programas por pista, registro manual
  de cardio y lectura de lo que ya entra por Strava a la tabla compartida.
- Fase 4 reducida a un botón: "Sincronizar Intervals" en HABIT que llama la acción
  `intervals-sync` que ya existe en `api/skandi.js`.
- Fase 6 parcial: tus rutinas (las de Alge y las piernas de gym) y tus dos programas, sin la
  historia. La historia llega con la 132 completa; mientras, se consulta en Skandi.

La calistenia por niveles (Fase 3) **no** es requisito del hito: un hold se registra en segundos
desde ya (117). Lo que se pierde unas semanas es la tarjeta de "listo para subir de nivel".

**Este bloque a bordo (19 oct – 8 nov) se queda en Skandi + Intervals.** Partir los registros entre
dos apps a mitad de bloque te deja PRs y gráficas cortadas en dos.

### Fase 0 — Abrir Entrenar

**Objetivo:** que alguien que se registra hoy desde Monterrey pueda entrenar mañana sin pagar
nada, y que eso no le abra la puerta del gym ni le llene el celular de avisos al admin.

1. **Requisito:** 120 corrida en producción y commiteada; prueba de que una cuenta sin plan no
   puede insertar `bookings` ni tocar `credits` por la API.
2. Sacar `'rutinas'` de `MEMBER_LOCKED_VIEWS`. Reservar y Comunidad se quedan.
3. Registro: una pregunta nueva, "¿Dónde entrenas?" → `joined_as`. Si es `app`:
   - no se manda el push "Nuevo socio" (se cuenta en el dashboard);
   - términos de uso de la app (no el reglamento del gym; ese se acepta al comprar membresía);
   - onboarding de 5 toques: objetivo, nivel, equipo, días, disciplinas → `training_profiles`, y al final
     una recomendación de programa (llega con la Fase 1; antes, las rutinas básicas que casen con
     su equipo).
4. **Inicio para quien no es socio:** primero "Tu entreno de hoy" y la semana; la tarjeta de
   membresía baja y se vuelve invitación ("¿Estás en Mazatlán? Entrena con nosotros").
5. Barra de abajo: Reservar sigue visible para quien no es socio pero lleva a la invitación, no a
   un aviso de error.
6. **Borrar mi cuenta** desde Perfil: una `action` nueva en un router existente (`delete-user.js`
   acepta al propio usuario además del admin). Requisito de la tienda de Apple.
7. Dashboard del admin: separar socios del gym de usuarios de la app en conteos y reportes; hoy
   "socios" contaría cada descarga.

**Terminado cuando:** una cuenta nueva `app` registra un entreno completo, ve su progreso, no puede
reservar ni abrir la puerta (probado contra la API, no solo la UI), y el admin no recibió push.

### Fase 1 — Biblioteca pública de programas

**Objetivo:** que "cualquiera puede seguir una rutina" sea verdad el día uno sin que nadie tenga
que armársela.

- Pantalla **Entrenar → Programas** con filtros por disciplina, nivel, días y equipo, y una ficha
  por programa (semanas, días, qué rutinas trae, a quién le sirve).
- "Empezar este programa" → `start_public_program` → la semana se llena sola.
- En Admin, marcar una plantilla como pública y llenar sus metadatos.
- **Contenido inicial (lo hace una persona, no el código):** al menos un programa por casilla de
  esta tabla, revisado por David:

| | Gym completo | Mancuernas en casa | Solo peso corporal / barra |
|---|---|---|---|
| Principiante | Fuerza 3 días | Cuerpo completo 3 días | Calistenia base (dominada, fondo, lagartija, sentadilla) |
| Intermedio | Torso/pierna 4 días | Empuje/tirón/pierna | Calistenia 4 días con habilidad (handstand) |
| Funcional / Hyrox | Funcional 3 días + carrera | Funcional en casa | — |
| Carrera | 5 km desde cero (8 semanas) | ← misma | ← misma |

**Los planes de Alge y Carlos son suyos.** Entran a HABIT como tus programas privados, no a la
biblioteca pública, salvo que ellos quieran publicarlos (ver §10: coaches externos).

**Terminado cuando:** una cuenta nueva con "mancuernas, principiante, 3 días" ve al menos dos
programas que le sirven, empieza uno y tiene su semana sin haber tocado una rutina.

### Fase 2 — Calendario multidisciplina y cardio

**Objetivo:** que tu martes (HS + tirón + accesorios **y** Z1) quepa en un solo día de HABIT, con
cada parte de su coach.

1. Migración 129 (§4.4) y prueba contra una copia de tu semana real (§6).
2. Auditoría de los 30 lugares de `app.html` que leen `coaching_schedule`: cada uno decide qué
   hace con una fila que no es `strength`. Lista en la bitácora, uno por uno.
3. Entrenar → Hoy: el día muestra sus slots en orden; una sesión de cardio muestra la estructura
   (`SkandiPlan.label()`), ritmo por zona y **velocidad en km/h para caminadora** (tus zonas de
   Carlos están en km/h).
4. **Registrar cardio:** hoja propia (distancia, tiempo, ritmo calculado, FC media/máx, RPE; rondas
   para HIIT; estaciones para Hyrox), escribe en `skandi_external_activities` y enlaza la fila.
5. Crear/editar una sesión estructurada con el mismo parser de Skandi
   (`"6x1km Z3 rest 2min Z1"` → `SkandiPlan.parse`).
6. Programas por pista: aplicar uno de fuerza no quita el de carrera; Semana muestra de qué
   programa salió cada día.
7. **Sesión suelta** (tu Hyrox semanal): una fila manual en el calendario sin programa; el
   estampado nunca la pisa.
8. La figura de recuperación recibe las actividades (`activities:` deja de ser `[]`).
9. Coach: el panel de David ve cardio en la semana del cliente con la misma hoja de elegir (un
   destino más en `openCoachBoardPicker`, no un componente nuevo).

**Terminado cuando:** tu semana de §6 se arma completa en HABIT, una carrera de Strava aparece
sola enlazada a su día, y el cliente de David que no hace cardio no ve ningún cambio.

### Fase 3 — Calistenia por niveles

1. Extraer de `skandi.html` el módulo puro `training-skills.js` (§4.5); Skandi lo carga y sigue
   igual (prueba: mismos niveles antes y después).
2. Migración 130 e importación de las escaleras 107/108.
3. En el entreno: tarjeta de habilidad con el criterio del escalón, calidad 1–10 en lugar de RIR
   cuando `track_quality`, lados alternados para unilaterales, clip opcional por serie.
4. Progreso → **Habilidades**: curva continua por línea (front lever, planche, HSPU, back lever),
   meta semanal de tiempo bajo tensión.
5. Avisos de subir/bajar de nivel con la regla de Skandi: dos sesiones seguidas cumpliendo el
   estándar, no un récord suelto.

**Terminado cuando:** tus niveles de front lever / planche / HSPU en HABIT coinciden con los de
Skandi para la misma historia.

### Fase 4 — Integraciones desde HABIT

1. Perfil → **Conexiones**: Strava e Intervals.icu, llamando las acciones existentes de
   `api/skandi.js`. El `state` firmado de Strava lleva a qué app regresar (`/` o `/skandi`).
2. Sincronización automática de Intervals al abrir HABIT (copia de `autoSyncIntervals`).
3. Fuerza registrada en Garmin: enlazar a la sesión de HABIT (lo que hace `intervals-link-strength`
   con `skandi_sessions`, ahora con `coaching_schedule`).
4. **Mandar al reloj:** una sesión estructurada de HABIT se sube como evento a Intervals.icu, que
   la manda a Garmin. Hoy lo haces con `intervals_import/intervals.py subir … --commit`; pasa a ser
   un botón. Ids estables por fila para que volver a mandar actualice en vez de duplicar.

**Antes de anunciarlo a todos:** revisar el límite de atletas de la app de Strava (las apps nuevas
arrancan limitadas y hay que pedir revisión) y sus términos sobre mostrarle los datos de un atleta
a otra persona (el coach).

### Fase 5 — Inteligencia y cuerpo

- Cargar `skandi-load.js`, `skandi-brief.js` y `skandi-joint-load.js` en HABIT. `skandi-brief.js`
  devuelve llaves de i18n: HABIT necesita solo el mapa de esas llaves a español, no un sistema de
  idiomas.
- Inicio/Hoy: **el porqué del día** (qué toca, en qué semana del bloque vas, cómo llegas).
- Check-in de 30 segundos: tus tres preguntas + horas en cama (§4.6). Sin Garmin no se pide nada.
- Progreso → **Cuerpo**: peso, medidas y fotos, leyendo las tablas de la persona (067/090).
- Carga articular (muñeca, codo, hombro) para quien hace calistenia: es justo el riesgo de tu plan
  de prevención de hombro/codo.

### Fase 6 — Tu mudanza y Skandi a mantenimiento

- Migración 132 completa (§4.7), con un reporte antes/después: número de sesiones, series, PRs por
  ejercicio.
- Skandi: aviso en su Home de que el entrenamiento vive en HABIT, con un enlace. Comida sigue
  igual (D7).
- `CLAUDE.md`: qué tablas `skandi_*` son de la persona y las usa HABIT; que Skandi no recibe
  funciones de entrenamiento.
- El crew del Skandi Nomad: se les invita a HABIT cuando las Fases 2–3 estén estables; nadie pierde
  su app mientras tanto.

### Fase 7 — Lanzamiento

**Producto**

- **Landing pública** (`/entrena`): qué es, capturas, "empieza gratis", y la puerta al gym para
  quien está en Mazatlán. Página suelta como `competencia.html`: necesita su línea en `shellFor()`
  de `sw.js`, o pisa la copia offline de la app.
- Enlace para compartir un programa ("Hice esto en HABIT") que abre la ficha del programa.
- Estado vacío cuidado en cada pantalla: el usuario de la app llega sin coach, sin historia y sin
  reservas.

**Legal**

- Términos de uso de la app (distintos del reglamento del gym) y **aviso de privacidad**: peso,
  medidas, fotos, FC y lesiones son datos de salud; en México son datos personales sensibles y
  piden consentimiento expreso. Revisarlo con un abogado antes de promocionar.
- Descargo de responsabilidad por entrenar sin supervisión.

**Tiendas** (`ios/` ya existe con Capacitor, `app.habittraininghub.app`)

- Borrado de cuenta desde la app (Fase 0).
- Cobro dentro de la app iOS: ver §9.1.

**Métricas** (desde el día uno, sin herramienta externa: consultas sobre las tablas)

| Métrica | Definición |
|---|---|
| Activación | % de cuentas `app` con un entreno terminado en sus primeros 7 días |
| Retención semana 4 | % que entrenó en su cuarta semana |
| Programa terminado | % que llega a la última semana de un programa de la biblioteca |
| App → coaching | cuentas `app` que pasan a `coaching_beta` |
| App → gym | cuentas `app` que compran su primera membresía |

### Fase 8 — Opcional

Nutrición en HABIT (con tope de gasto por usuario), inglés, retos mensuales, coaches externos
publicando programas (§10). (La comunidad abierta con moderación ya se hizo: D13 y la 128.)

---

## 6. Tu semana, escrita en HABIT

El ejemplo que valida el modelo: si esto no cabe, la 129 está mal diseñada.

**Dos programas activos, uno por pista:**

- *Calistenia Alge* — pista `strength`, ciclo propio, incluye las piernas de gym partidas en dos.
- *Running Master Carlos* — pista `endurance`, `start_date` 19 oct, 6 semanas; cada semana tiene
  sus propias filas (`week_index` 1–6), porque la semana 5 de carrera no es la semana 1. Cargado
  completo: las semanas 1–3 quedan como historia y desde el 9 nov corren la 4–6.

| Día | slot 0 | slot 1 | slot 2 |
|---|---|---|---|
| Lun | HS + empuje + cadera (hip thrust, RDL, curl) + core · *Alge* | | |
| Mar | HS + tirón + accesorios + gemelo/sóleo · *Alge* | E · Z1 · *Carlos* | |
| Mié | HS + empuje + hombro sano + movilidad · *Alge* | Hyrox (sesión suelta, si toca esa semana) | |
| Jue | HS + cuádriceps y pantorrilla · *Alge* | J · Z1 · *Carlos* | |
| Vie | HS + tirón + accesorios + core + movilidad · *Alge* | | |
| Sáb | Q · calidad · *Carlos* | HS + ½ empuje · *Alge* | |
| Dom | Movilidad · *Alge* | L · largo · *Carlos* | |

Lo que este ejemplo exige y por qué está en la 129:

- **Dos sesiones el mismo día de coaches distintos** → `slot` en las tres tablas.
- **Dos programas activos sin pisarse** → `track`.
- **Una semana de carrera distinta a la anterior** → ya existe (`week_index`, 115).
- **Hyrox que cambia cada semana y lo colocas tú** → sesión suelta, fuera de los programas.
- **Correr en caminadora con zonas en km/h** → la conversión zona → velocidad del mismo módulo que
  da el ritmo.

---

## 7. Riesgos

| Riesgo | Mitigación |
|---|---|
| Una fila de cardio rompe un lugar que asumía rutina (30 en `app.html`) | Default `strength`; auditoría uno por uno (Fase 2, paso 2); el cardio solo aparece para quien lo crea |
| Reescribir `ensure_coaching_week_from_template` desde una copia vieja | Extender desde el cuerpo vigente (`pg_get_functiondef` en producción, no el archivo) |
| `app.html` sigue creciendo (19,350 líneas) | D9: toda matemática a módulos; la UI de cardio y de habilidades en funciones con prefijo propio para poder sacarlas a un archivo después |
| Más registros abiertos = más superficie de ataque | Requisito 120; repaso de cada función `security definer` y de los `grant` a `anon` (lección 123/124); revisar buckets; confirmación de correo y captcha en el registro de Supabase Auth |
| Costos con usuarios que no pagan | Revisar el plan de Supabase (usuarios activos, almacenamiento: los clips de video son lo caro; ponerles tope de tamaño). Sin IA en el entrenamiento: cero tokens por usuario |
| La biblioteca sale vacía o floja | El contenido es el cuello de botella, no el código: los programas de la Fase 1 se escriben en paralelo a las Fases 0–2 |
| El coach se satura si los usuarios de la app piden coaching | El coaching sigue siendo invitación (`coaching_beta` lo prende el admin); se abre con cupo |
| Datos de salud de terceros | Aviso de privacidad y consentimiento (Fase 7) antes de promocionar |

---

## 8. Lo que deliberadamente no hacemos

- **No portamos Skandi pantalla por pantalla.** Se porta lo que le falta al modelo de HABIT; las
  pantallas de HABIT se quedan con su lenguaje (rutina → semana → programa).
- **No hacemos que HABIT lea `skandi_templates` / `skandi_sessions` en vivo.** Tu historia se copia
  una vez.
- **No renombramos tablas `skandi_*`** (D3).
- **No creamos un rol "usuario de app".** El acceso al gym ya lo decide la membresía (D4).
- **No metemos nutrición** (D7) en este proyecto. (La Comunidad sí se abrió: D13.)
- **No integramos Garmin directo**: el programa de Garmin no acepta uso personal y tiene altas en
  pausa (`PROYECTO_SKANDI_V2.md` §3.1). Strava e Intervals ya lo cubren.
- **No borramos Skandi ni su historia.**

---

## 9. Cobro y plataforma

### 9.1 Cobrar dentro de la app de iPhone

La membresía del gym es un servicio físico y por eso Stripe dentro de la app es válido. Una
suscripción que **desbloquea funciones digitales** dentro de la app iOS (un "HABIT+") tendría que
ir por la compra dentro de la app de Apple, con su comisión. Hay una excepción para servicios
uno-a-uno en tiempo real entre personas (el ejemplo que da Apple incluye entrenamiento físico);
si el coaching en línea cabe ahí depende de cómo se entregue. **Verificar las guías vigentes antes
de poner un botón de pago digital en la app iOS.** En la PWA (web) no aplica.

### 9.2 Vercel

Los términos de Vercel dejan el plan Hobby para uso personal no comercial, y este proyecto ya
cobra con Stripe. Al promocionarlo, conviene pasar a Pro (verificar precios y límites actuales;
el techo de 12 funciones es del plan Hobby). Mientras no se cambie, D10 sigue: cero funciones
nuevas.

---

## 10. Preguntas abiertas para ti

1. **Cobro:** ¿confirmamos "entrenar gratis, cobrar gym y coaching" (D5)?
2. **Contenido:** ¿quién escribe los programas de la Fase 1 — David, tú, otro coach? ¿Cuántos para
   lanzar?
3. **Alge y Carlos:** ¿les interesaría publicar sus programas en HABIT (coaches externos, con su
   nombre)? Sería la primera versión de un catálogo de coaches.
4. **Crew del Skandi Nomad:** ¿alguien más lo usa hoy, o solo tú?
5. **Lanzamiento:** ¿tienda de Apple desde el día uno, o PWA primero y tienda después?
6. **Nombre:** ¿la app se sigue llamando "HABIT Training Hub" para quien no es del gym, o
   "HABIT" a secas con el gym como una de sus puertas?

---

## 11. Definición de terminado (proyecto)

- [ ] Una cuenta nueva sin membresía entrena, registra y ve progreso; no puede reservar ni abrir
      la puerta, probado contra la API.
- [ ] La biblioteca tiene al menos un programa por casilla de la tabla de la Fase 1.
- [ ] Tu semana de §6 vive en HABIT con dos programas activos, y tus carreras de Garmin llegan
      solas.
- [ ] Tus niveles de calistenia en HABIT coinciden con los de Skandi.
- [ ] Tu historia de fuerza de Skandi está en Progreso de HABIT, con los mismos PRs.
- [ ] Skandi muestra el aviso de mudanza; `CLAUDE.md` describe la regla de propiedad (§4.1).
- [ ] Landing, términos, aviso de privacidad y borrado de cuenta publicados.
- [ ] Las cinco métricas de la Fase 7 se pueden consultar.

---

## 12. Bitácora

- **2026-10-19** — Documento creado a partir de la auditoría del repo. Nada implementado.
  Pendiente: confirmar decisiones D1–D10 y contestar §10.
- **2026-10-19** — D1–D10 confirmadas. **Fase 0, código hecho; sin desplegar ni correr en
  Supabase.**
  - **120 revisada y corregida antes de correrla.** Probada contra Postgres real (PGlite, 20
    casos): con `plan_id` null, `v_unlimited` quedaba en NULL (`false or null`), el chequeo
    `NO_CREDITS` no entraba y **una cuenta nueva sin plan ni visitas reservaba** (créditos −1),
    y con eso abría la puerta. Mismo NULL en `cancel_my_booking`: quien tenía visitas sueltas
    sin `plan_id` cancelaba sin recuperar la visita. Arreglado con `coalesce` en los dos.
  - **127** (`127_training_for_everyone.sql`), probada igual (20 casos, dos corridas
    seguidas): `profiles.joined_as`, `training_profiles`, `handle_new_user` y
    `ensure_habit_profile` leen `joined_as`, y las rutinas básicas (122) solo a quien entra
    por el gym. Hallazgo: el perfil nace en `handle_new_user` (trigger sobre `auth.users`),
    no en `ensure_habit_profile`; por eso `joined_as` viaja en los metadatos del `signUp`.
    Se llama `joined_as` y no `signup_source` porque `profiles.source` ya existe.
  - `app.html`: Entrenar fuera de `MEMBER_LOCKED_VIEWS`; Reservar sin membresía lleva a
    Membresías; registro con "¿Dónde entrenas?"; términos de la app vs reglamento del gym
    (este último en `doPay` para quien entró por la app); onboarding; Inicio con "Entrenar
    hoy" para todos (antes solo Coaching) y sin tarjeta de puerta ni "Sin membresía" para
    quien entrena por su cuenta; Perfil con "Mi entrenamiento" y "Borrar mi cuenta"; admin con
    "Usuarios de la app" aparte de "Total socios" y chip **App** en Usuarios.
  - `api/delete-user.js`: `{self:true}` para que el socio borre su cuenta.
  - Commits separados: `d897457` (reservas en el servidor, 120/121, versión `20261019-1`) y
    el de la Fase 0 (versión `20261020-1`).
  - **No verificado:** el registro real y el borrado real (el servidor local apunta a la base
    de producción; no se crearon cuentas de prueba), y el dashboard del admin con datos.
  - **Orden de despliegue:** (1) correr la **127** en el SQL Editor — es segura con la app
    publicada hoy (su llamada de dos argumentos a `ensure_habit_profile` sigue funcionando), y
    así ninguna cuenta "Por mi cuenta" nace como `gym`; (2) commit + push de la app; (3) correr
    la **120** — después de la app, como dice su encabezado: la app usa los RPC si existen y
    si no el camino viejo, pero la app vieja no sabe usar los RPC; (4) probar una reserva y
    una cancelación reales, registrar una cuenta "Por mi cuenta" y otra "En HABIT Mazatlán", y
    revisar el admin.
- **2026-10-23** — Producción: 127 y 120 corridas, `1c0c7bc` desplegado (`20261020-1`);
  comprobado desde fuera que los RPC existen y que la llave pública no los puede usar.
  **HABIT Crew (D11–D13), commit y push el 23 oct:**
  - `/crew` reescrito a `app.html` en `vercel.json`; `crew-manifest.json` e `icons/crew-*`
    (el ícono de HABIT invertido); `sw.js` mapea `/crew` al mismo shell.
  - Un script en el `<head>` (`#brand-boot`) decide la marca por la ruta antes de que el
    navegador lea manifest, íconos y título; `IS_CREW` en el script principal.
  - En Crew: sin Reservar, Tienda, Membresía ni Historial; Inicio sin puerta, reservas ni
    pases de invitado (y sin sus relojes), con "Entrenar hoy" y una tarjeta que abre HABIT;
    admin y recepción entran como usuarios.
  - En las dos: la Comunidad se abre a toda cuenta (`MEMBER_LOCKED_VIEWS = ['book']`); la base
    ya lo permitía (las políticas de `posts` solo piden sesión).
  - Registro: sin "¿Dónde entrenas?"; `joined_as` sale de la app.
  - Verificado en el navegador local con la reescritura de `/crew`: título, manifest, íconos,
    registro, Inicio y barra de Crew; HABIT sin cambios salvo la Comunidad abierta.
  - Versión `20261023-1` (incluye la `v` del script `#brand-boot` y `crew-manifest.json`).
  - **Falta antes de promocionar Crew:** moderación de la comunidad (reportar, bloquear,
    cola del admin), y la app de Crew en la App Store (otro bundle id en Capacitor).
- **2026-10-23** — **Moderación de la comunidad** (D13), lo que pide la guideline 1.2 de Apple
  antes de promocionar Crew o subirla a la App Store. Parte del commit de HABIT Crew.
  - **128** (`128_community_moderation.sql`): `community_reports` (reportar una publicación o un
    comentario, con motivo y estado pendiente/resuelto/descartado) y `community_blocks`.
    El socio inserta reportes y no lee ninguno; el admin (`is_habit_admin()`) los lee y los
    resuelve. Lo reportado se copia al reporte (autor, texto, foto) en un trigger, así que la
    cola funciona aunque el autor lo borre, y el cliente solo escribe qué y por qué.
  - **Decisión: el filtro del bloqueo va en la RLS, no en `renderFeedSb`.** Una regla en un
    lugar para las dos apps (y la nativa, y cualquier pantalla futura que lea posts); PostgREST
    la aplica también a los comentarios embebidos en el feed; lo bloqueado no llega al
    teléfono, y el `limit(50)` cuenta lo que sí se ve. Son políticas `restrictive`, que se
    suman a las permisivas sin importar cuántas haya en producción. El bloqueo corre en los
    dos sentidos (si no, el bloqueado seguiría comentando bajo las publicaciones de quien lo
    bloqueó, a la vista de todos los demás) y no ciega al admin si alguien lo bloquea.
  - `api/delete-community-item.js`: al borrar, marca resueltos los reportes pendientes de eso
    (no es una función nueva: sigue el techo de 12).
  - `app.html`: ⋯ en las publicaciones y comentarios de otros (reportar con cinco motivos,
    bloquear; después de reportar ofrece bloquear), Perfil → Usuarios bloqueados con
    "Desbloquear", y en Admin → Comunidad la cola de reportes pendientes arriba del feed
    (agrupada por lo reportado, con quién reportó, cuánta gente bloqueó al autor, y Borrar /
    Descartar / Marcar resuelto si ya no existe); cada reporte manda un push al admin
    (`sendPush('admin', …)`, como las reservas). `choiceSheet()` nuevo junto a
    `confirmSheet`/`promptSheet`. Versión `20261023-2`.
  - **Probada contra Postgres real** (PGlite, esquema mínimo tipo Supabase con `anon` /
    `authenticated` / `service_role` y `auth.uid()` por `request.jwt.claim.sub`; 65 casos, la
    migración corrida dos veces seguidas): reportar, que nadie más lea los reportes, que el
    cliente no pueda escribir quién reporta ni la copia, el duplicado, resolver y descartar,
    borrar lo reportado sin que falle, bloquear en los dos sentidos, el admin exento,
    desbloquear, y `anon` sin acceso. **Hallazgo:** con las políticas para todo rol, la lectura
    de `posts` con la llave pública pasaba de vacía a error de permisos (anon no ejecuta la
    función de la política); se arregló con `to authenticated`.
  - Verificado en el navegador local, en `/crew` y en `/`, con el cliente de Supabase simulado en
    la página (el servidor local apunta a producción: ni sesión ni escrituras): el ⋯ solo en lo
    ajeno, el flujo de reportar (motivo → detalle → gracias → bloquear), el duplicado, bloquear
    y que el feed se repinte, Perfil con su lista y el estado vacío, la sección escondida sin la
    128, el menú del admin (solo bloquear) y la cola con sus tres botones y el badge.
  - **No verificado:** contra la base real (la 128 no está corrida) ni en el iPhone.
  - **Orden de despliegue:** cualquiera. Sin la 128, la app nueva esconde "Usuarios bloqueados"
    y reportar o bloquear dicen "todavía no está disponible"; la app publicada no lee estas
    tablas. Lo natural: correr la 128 y luego publicar.
  - **Falta para la guideline 1.2** (no es código de esta migración, son decisiones tuyas):
    (1) que los términos que se aceptan al registrarse digan que no se tolera contenido
    ofensivo ni usuarios abusivos — hoy los de la app no hablan de la comunidad; (2) un
    contacto publicado para quejas; (3) responder los reportes a tiempo (Apple espera ~24 h;
    cada reporte manda un push al admin y deja un aviso en Alertas, pero alguien tiene que
    atenderlos); (4) Apple también pide filtrar lo
    ofensivo antes de publicarlo, y no hay filtro de palabras.
  - **Feed lento por fotos en base64** (pedido de la sesión de planificación): la Comunidad
    tardaba ~6 s porque el feed bajaba `img_url` de todos los posts, y uno de mayo 2026
    (`b082c70a…`, de antes de la 017) trae su foto en base64 dentro de la tabla: 6.4 MB. El feed
    y Admin → Comunidad ya no piden `img_url` con la lista: las URLs del bucket van en un
    segundo select (`not like 'data:%'`), de las incrustadas solo el id, y esas muestran "Ver
    foto" y la bajan al tocarla. El trigger de la 128 tampoco copia una foto base64 al reporte.
    Verificado con el cliente simulado (las tres formas de post, y que la lista no pide
    `img_url`) y en PGlite (67 casos). Arreglo de fondo, pendiente y aparte: subir esa foto al
    bucket `community-images` y dejar su URL en `img_url`.
- **2026-10-23 (2)** — **Pulido de Entrenar, Fase A** (la sesión y los bugs). Auditoría hecha
  como usuario nuevo en `/crew` con la cuenta de prueba `1@habit.app`; propuesta en tres fases
  (A sesión y bugs, B Hoy, C Semana y Rutinas), aprobada A.
  - Bugs, verificados contra la base antes y después: cancelar dejaba los récords de la sesión
    huérfanos (2 → 0 ahora); palomear sin escribir guardaba la serie sin reps (ahora 10);
    "Última vez" tomaba la sesión en curso; el precargado rellenaba series ya hechas.
  - Velocidad: Entrenar pinta Hoy en 0.43 s (antes 1.5 s; las consultas van en paralelo y el
    cuerpo se completa después); abrir una sesión, 1.6 s con 4 consultas (antes ~5 s con 8).
  - La hoja: sin ✕ ni RIR por serie (RIR opcional), menú ••• flotante con "Marcar todas",
    "Cambiar", "Quitar una serie", "Registrar RIR" y "Quitar ejercicio"; campos y palomitas
    de 44 px; nada se mueve al palomear (medido: 0 px); descanso automático de 90 s visible.
  - La Comunidad lenta (una foto de 6.4 MB incrustada en `posts`) la arregló la sesión de
    moderación, que estaba tocando el feed (entrada de arriba).
  - Versión `20261023-2`. Pendiente: Fase B (Hoy) y Fase C (Semana y Rutinas).
- **2026-10-23 (3)** — La moderación y la Fase A se unieron en `main` (las dos habían subido a
  `20261023-2` por separado) con la versión `20261023-3`. Sin push hasta correr la **128** en
  Supabase.
- **2026-10-23 (4)** — **Pulido de Entrenar, Fase B (Hoy)**, sin commitear. Una tarjeta y un
  botón según el día (en curso → Continuar; agendado → Empezar; hecho → Ver lo que hiciste;
  descanso → qué sigue; usuario nuevo → Elegir qué entrenar), otras sesiones del día en una
  línea, la semana en siete puntos (toca → Semana), "Tu cuerpo" en una fila que se despliega
  (`habit_hoy_body`) y "Tu progreso" con fila propia. Probado solo el estado de usuario nuevo;
  faltan agendado, en curso y hecho. Versión `20261023-4`. Pendiente: Fase C.

- **2026-10-23 (5)** — **Fases B y C de Entrenar**, versión `20261023-5`.
  - Hoy: corregida la prioridad de días con varias sesiones (en curso/pendiente antes de
    completo), recuperación de series al reabrir y descanso en semanas con sesiones omitidas.
  - Semana: siete filas accesibles en una lista continua, programa compacto y menú de opciones;
    conserva la distribución habitual y las solicitudes al coach.
  - Rutinas: biblioteca de filas que abre una ficha completa, con todos los ejercicios y
    acciones de entrenar, asignar, editar o adaptar. Editor y búsqueda a pantalla completa;
    filtros por músculo y búsqueda por nombre, alias y equipo, sin límite artificial de 25.
  - Validación: comprobaciones del proyecto y pruebas aisladas de Hoy (36) y Rutinas (21).
    La sesión de prueba anterior no estaba disponible en el navegador local: queda pendiente
    validar los recorridos autenticados y el aspecto final con esa cuenta.
  - La foto histórica de 6.4 MB sigue pendiente de migrar a Storage. No se confirma ninguna
    modificación de esa imagen ni del post.
