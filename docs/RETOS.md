# Retos — un usuario propone, todos registran su marca

> Documento de planeación. Fecha: 2026-10-24. Dueño: Joseph.
> Se actualiza conforme avanzan las fases (bitácora al final).
> Relacionados: `HABIT_PARA_TODOS.md` (D11–D13: dos apps, una comunidad; Fase 8 "retos"),
> `migrations/126_lift_competition.sql` (el marcador del gym, mismo patrón de orden),
> `migrations/128_community_moderation.sql` (reportar y bloquear).

---

## 0. En cinco líneas

1. Cualquier cuenta propone un reto (un WOD escrito y cómo se mide) y cualquier cuenta registra
   su marca; la tabla se ordena sola.
2. Vive **dentro de Comunidad** (Feed | Retos), así que está en HABIT y en HABIT Crew sin hacer
   nada: la comunidad ya es una sola (D13).
3. **La base decide**: un trigger valida la marca y una vista da el lugar. La app solo pinta.
4. Es contenido de usuarios: entra en la moderación de la 128 (reportar, bloquear) desde el día
   uno, porque Apple lo pide (guideline 1.2).
5. Sin endpoints nuevos (techo de 12 funciones): tablas + RLS + vista, todo desde el cliente.

---

## 1. Decisiones

✅ **Confirmadas el 24 oct 2026.**

| # | Decisión | Elegido | Por qué |
|---|---|---|---|
| R1 | ¿Dónde vive? | **Pestaña dentro de Comunidad**, no botón nuevo en la barra | La barra de HABIT ya tiene 6 botones y no cabe otro a 375 px; la comunidad ya es la misma en las dos apps y ya trae la moderación |
| R2 | ¿Se publica directo o lo aprueba el admin? | **Directo**, como los posts, con reportar y bloquear | Si el admin aprueba cada reto, la sección depende de una persona y se vuelve lenta. El admin oculta lo que no deba estar |
| R3 | ¿Una marca o varios intentos? | **Una marca por persona y reto, que se puede corregir** mientras el reto esté abierto | En la tabla cuenta tu mejor marca sin tener que juntar varios intentos. Corregir = repetiste y te fue mejor |
| R4 | ¿Rx / Scaled? | **Sí, como opción del reto** (`has_divisions`) | Sin una división escalada un principiante no participa. Si el reto no la activa, todos van en una sola tabla |
| R5 | ¿Prueba? | **Link de video opcional** (`proof_url`) | Obligarla frena a todos por culpa de unos pocos; para lo dudoso queda reportar |
| R6 | ¿Quién marca un reto como oficial? | **Solo el admin** (`is_official`) | Es lo que distingue el reto del gym de uno propuesto por un socio, como el color en las rutinas |

---

## 2. Tipos de marca

El tipo (`score_type`) dice qué se registra y quién gana:

| `score_type` | Qué registras | Gana |
|---|---|---|
| `amrap` | `rounds` + `reps` sueltas | más rondas; a igualdad, más reps |
| `for_time` | `time_sec` si terminaste (`finished = true`); si no, las `reps` hechas al llegar a `time_cap_sec` | menos tiempo. Quien no terminó va **después** de todos los que terminaron, por reps |
| `max_reps` | `reps` | más |
| `max_load` | `load_kg` | más |
| `max_time` | `time_sec` (plancha, colgarse, hollow hold) | más |

`for_time` exige `time_cap_sec` (sin límite no se puede ordenar a quien no terminó); en los
demás es opcional y solo informa (un AMRAP de 12 min lo lleva en la descripción y en el
cronómetro de la Fase 2).

Empate: **gana quien registró primero esa marca** (`scored_at`, que solo se mueve cuando la marca
cambia — mismo criterio que `best_at` en la 126: repetir tu marca no te quita el lugar).

---

## 3. Modelo de datos — migración 129 (`migrations/129_challenges.sql`)

> Numeración: `HABIT_PARA_TODOS.md` apartó los números 128–132 para sus fases, pero la 128 la
> ocupó la moderación y la 129 Retos. Sus fases toman los siguientes números libres cuando se
> escriban; falta corregir la tabla de fases de ese documento.

**Los nombres van copiados en la fila** (`challenges.created_by_name`,
`challenge_entries.user_name`), como `posts.user_name`: desde la 117 un socio solo lee su propio
perfil, y una tabla de marcas sin nombres no sirve. Los copia el trigger, nunca el cliente.

### 3.1 `challenges`

```
id              uuid pk
created_by      uuid default auth.uid() → profiles(id) on delete set null
title           text  1–80
description     text  ≤ 1000   -- el WOD tal cual
score_type      text  check in ('amrap','for_time','max_reps','max_load','max_time')
time_cap_sec    int   null; obligatorio si for_time; 60–7200
has_divisions   bool  default false
starts_on       date  default hoy (America/Mazatlan)
ends_on         date  default starts_on + 7; check ends_on >= starts_on, ≤ 60 días
is_official     bool  default false   -- solo admin lo cambia
status          text  'activo' | 'oculto'   -- oculto = lo quitó el admin o el autor
created_at      timestamptz
```

"Abierto" no es un estado guardado: es `status = 'activo' and hoy between starts_on and ends_on`
(fecha de Mazatlán), calculado en una función `challenge_is_open(id)`. Guardarlo pediría un cron.

### 3.2 `challenge_entries`

```
id              uuid pk
challenge_id    uuid → challenges(id) on delete cascade
user_id         uuid default auth.uid() → profiles(id) on delete cascade
division        text  'rx' | 'scaled'   default 'rx'
rounds          int   null  0–999
reps            int   null  0–9999
time_sec        int   null  1–86400
load_kg         numeric(6,2) null  > 0, ≤ 1000
finished        bool  null   -- solo for_time
note            text  ≤ 300
proof_url       text  ≤ 500, http(s)
scored_at       timestamptz  -- lo pone el trigger
created_at / updated_at
unique (challenge_id, user_id)   -- R3: una marca por persona
```

### 3.3 Reglas en la base

- **Trigger `challenge_entry_validate`** (before insert/update):
  - el reto está abierto; si no, `CHALLENGE_CLOSED`;
  - solo vienen los campos del tipo (los demás se ponen en null, no se rechaza):
    `amrap` → rounds+reps · `for_time` → finished + (time_sec ≤ cap si terminó, reps si no) ·
    `max_reps` → reps · `max_load` → load_kg · `max_time` → time_sec;
  - `division = 'scaled'` solo si el reto `has_divisions`;
  - `scored_at` se mueve solo si la marca cambió (como `best_at` en la 126);
  - `user_id` no se puede cambiar en un update.
- **Trigger en `challenges`**: el autor no puede tocar `is_official`; con marcas ya registradas no
  puede cambiar `score_type`, `time_cap_sec` ni `has_divisions` (cambiaría el orden de gente que ya
  registró), y sí puede corregir título, descripción, alargar `ends_on` u ocultarlo.
- Un reto **terminado queda congelado** para su autor (`CHALLENGE_CLOSED` al editarlo), y nadie
  —ni el SQL Editor— registra, corrige o quita su marca en él: la tabla final no se mueve. El
  admin sí puede editar el reto y borrar marcas.
- Al proponer, `starts_on` va de hoy a hoy + 30; cerrar antes se puede hasta hoy, nunca en el
  pasado (`CHALLENGE_BAD_DATES`).
- **Registrar es `insert` y corregir es `update` por id, no upsert**: PostgREST pone en el `SET`
  todas las columnas del payload, `challenge_id` incluida, y esa columna no tiene permiso de
  actualización. El duplicado llega como 23505.
- **Errores como códigos** que la app traduce, como `BOOKING_RPC_ERRORS`:
  `CHALLENGE_NO_SESSION`, `CHALLENGE_CLOSED`, `CHALLENGE_BAD_SCORE`, `CHALLENGE_BAD_DATES`,
  `CHALLENGE_LOCKED`. Las reglas de la tabla (`challenges_cap_for_time`, `challenges_dates`)
  llegan como 23514.

### 3.4 El orden: una sola vista

`challenge_standings` (`security_invoker`, así que respeta la RLS y los bloqueos) devuelve cada
marca con su `place` por `(challenge_id, division)`, con un `rank()` cuyo `order by` es un `case`
por `score_type` (la tabla del §2). La app y, en la Fase 3, la tele leen `place` de ahí; nadie
más lo calcula. También trae `score_label` ("10 rondas + 5 reps", "4:05", "Límite · 80 reps",
"140.5 kg"), de `challenge_score_label()`, la misma que usa la copia del reporte.

`challenge_cards` es cada reto con su `phase` (`proximo` / `abierto` / `terminado`) y
`entries_count`, para las tarjetas. Las dos son `security_invoker`: lo bloqueado no aparece ni
cuenta, y los lugares se recorren para quien bloqueó.

### 3.5 RLS

| Tabla | select | insert | update | delete |
|---|---|---|---|---|
| `challenges` | autenticado, `status = 'activo'` o propio o admin | autenticado, `created_by = auth.uid()` | autor o admin (el trigger limita qué) | autor si nadie más registró; admin siempre |
| `challenge_entries` | si su reto se ve | propio, en un reto que se ve | propio | propio mientras esté abierto; admin siempre |

Las marcas se ven "si su reto se ve": la subconsulta pasa por la RLS de `challenges`, así que
oculto y bloqueado no hay que repetirlos. Permisos por columna: el socio no escribe
`created_by`, `user_id`, nombres, `scored_at` ni (al crear) `is_official` / `status`.

- **Bloqueos**: políticas `restrictive` con `community_visible_author(created_by)` /
  `community_visible_author(user_id)`, igual que `posts` en la 128: lo bloqueado no llega al
  teléfono, en los dos sentidos, salvo hacia el admin.
- `to authenticated` en todo; `anon` no ve retos (la tele de la Fase 3 tendrá su propia política,
  como `on_screen` en la 126).
- Revocar `anon` explícitamente en las funciones nuevas (lección de la 124).

### 3.6 Reportes

`community_reports` gana `challenge_id` y `entry_id` (`on delete set null`) y
`target_kind in ('post','comment','challenge','entry')`; el trigger de copia guarda título/WOD o
la marca y su autor. **Requiere que la 128 esté corrida antes**: esta migración altera su CHECK
y reescribe `community_report_fill` / `community_report_notify` con dos ramas más.

El admin borra retos y marcas **desde la app, sin endpoint**: la RLS ya se lo permite, y un
trigger `before delete` marca resueltos los reportes pendientes de lo borrado (lo que
`delete-community-item.js` hace para posts). Si lo borra su autor, el reporte se queda
pendiente y la cola lo muestra como "ya no existe", igual que un post que su autor borró.

---

## 4. Pantallas

### Fase 1 — lo mínimo que sirve

1. **Comunidad → Retos**: subpestañas Activos · Terminados · Míos (los que creé o donde registré).
   Tarjeta: título, tipo, "quedan N días", participantes, tu lugar si registraste, sello
   "Oficial HABIT" si `is_official`.
2. **Crear reto** (hoja, no pantalla): título, WOD, tipo, límite de tiempo (solo For Time),
   Rx/Scaled sí/no, fechas (7 días por defecto). Botón «+ Reto» en la pestaña.
3. **Detalle del reto**: el WOD, la tabla (dos si hay divisiones), tu marca resaltada y fija abajo
   si no cabes en pantalla, botón «Registrar mi marca» / «Corregir mi marca».
4. **Registrar marca** (hoja): los campos del tipo — rondas+reps, `mm:ss`, kg, terminé sí/no —,
   división, nota, link de video. Errores del trigger traducidos.
5. **Moderación**: menú ⋯ (`communityMoreBtn` / `openCommunityItemMenu`) en retos y marcas
   ajenas: reportar, bloquear. Admin → Comunidad: la cola muestra también retos y marcas; el
   admin oculta un reto, borra una marca, marca un reto como oficial.
6. `confirmSheet` / `promptSheet` / `choiceSheet` para todo; `withScrollKept` al repintar la tabla.

Fuera de la Fase 1 a propósito: notificaciones, cronómetro, feed.

### Fase 2 — que se mueva solo ✅ (migración 130, 24 oct)

- **Tarjeta en el feed** cuando alguien crea un reto, derivada de `challenges` (no un `post`
  aparte, que habría que mantener sincronizado): `loadFeedRetos` + `feedRetoCardHtml`, mezclada
  por fecha con las publicaciones. Si falla, el feed sigue igual.
- **Avisos** en `user_notifications`: "X registró su marca en tu reto" (al autor, solo la primera
  vez) y "X te pasó en «…»" (a las 10 personas más cercanas que una marca deja atrás). Los
  escribe el trigger `challenge_entry_notify` de la **130**; una política restrictiva impide que
  la app inserte avisos `challenge_*`. Tocar el aviso abre el reto. El **push** a quien tiene la
  app cerrada lo manda la app después de guardar (`retoPushAfterScore`), comparando los lugares
  de antes y de después que da la vista: la base no llama a `send-push`.
- **El orden vive en `challenge_sort_key()`** desde la 130: la usan la vista y el trigger, así
  que "te pasó" y la tabla no pueden discrepar.
- **Tarjeta en Inicio** (`renderInicioRetos`): los retos abiertos donde registraste, con tu
  lugar; si no hay, el oficial abierto. Nada si no hay ninguno.
- **Hacerlo ahora** (`openRetoTimer`): pantalla completa con 10 s para prepararse, pitidos en
  3-2-1 y la campana del descanso al empezar y al terminar. AMRAP cuenta hacia atrás la duración
  (o hacia adelante si no tiene) con «+1 ronda»; For Time cuenta hacia adelante hasta «Terminé»
  o el límite; Máx. tiempo hasta «Paré». Al terminar abre «Registrar marca» ya llenado —nunca
  guarda solo— y pide la pantalla encendida (Wake Lock) mientras corre. El tiempo sale de
  `Date.now()` contra el inicio, no de sumar ticks.
- ~~Convertir en rutina~~ — **descartado**. Un reto es texto libre y una rutina de HABIT solo
  admite ejercicios del `exercise_catalog` (el socio no escribe ejercicios a mano, ver
  `CLAUDE.md`). Convertirlo pediría inventar fichas sin músculo ni video. El cronómetro cubre lo
  que se quería: hacer el reto desde la app.

### Fase 3 — el gym

- Retos oficiales mensuales y una sección "Oficiales" arriba.
- Mostrar un reto en la tele: `competencia.html` lee `challenge_standings` de un reto marcado
  para pantalla (política `anon` acotada, como `on_screen`).
- Insignias por participar / podio.

---

## 5. Riesgos

- **Marcas falsas.** Sistema de honor + video opcional + reportar + el admin borra. Si se vuelve
  un problema, R5 se cambia por reto (`proof_required`) sin migrar datos.
- **Orden incorrecto por tipo.** El `case` de la vista es la parte delicada: probarla contra
  Postgres real con un caso por tipo, empates y For Time mezclando terminados y no terminados.
- **Zona horaria.** "Abierto hasta el 31" es el 31 en Mazatlán, no en UTC; la función usa
  `(now() at time zone 'America/Mazatlan')::date`, igual que la 126.
- **Dependencia de la 128.** Sin ella no hay reportes ni bloqueos, y no se debe lanzar sin eso.

---

## 6. Lo que deliberadamente no hacemos

- No hay varios intentos por persona (R3).
- No hay aprobación previa del admin (R2).
- No hay retos privados ni por invitación en v1: un reto es de la comunidad.
- No se crea un endpoint nuevo: todo es tabla, RLS, trigger y vista.
- No se calcula el lugar en la app.

---

## 7. Definición de terminado (Fase 1)

- [x] Migración pasa `npm run check:sql` y se probó contra Postgres real (orden por tipo, empates,
      cierre por fecha, bloqueos en los dos sentidos, `anon` sin acceso).
- [ ] Migración corrida en Supabase (después de la 128).
- [x] Crear, registrar, corregir y ver la tabla funciona en HABIT y en HABIT Crew (verificado con
      Supabase simulado; falta contra la base real).
- [x] Reportar y bloquear funcionan en retos y marcas; el admin oculta y borra (ídem).
- [x] Se ve bien a 375 px.
- [x] Versión subida en todos los lugares que pide `CLAUDE.md` (`20261024-1`).
- [x] `CLAUDE.md` describe las tablas nuevas y la vista.
- [x] 128 y 129 corridas en Supabase; publicado (`e2db310`, versión `20261024-1`).
- [ ] Probado en el iPhone con cuentas reales.

---

## 8. Bitácora

- **24 oct 2026** — Plan escrito; decisiones R1–R6 confirmadas.
- **24 oct 2026** — **Migración 129** (`129_challenges.sql`) escrita: `challenges`,
  `challenge_entries`, las vistas `challenge_standings` / `challenge_cards`, RLS con bloqueos, y
  `community_reports` ampliada a retos y marcas.
  - Cambios al plan al escribirla: los nombres van copiados en la fila (la 117 cerró la lectura
    de perfiles ajenos); el autor borra su reto solo si nadie más registró; un reto terminado
    queda congelado; el admin borra desde la app y los reportes se resuelven por trigger, sin
    tocar `delete-community-item.js`; registrar es insert + update, no upsert.
  - **Probada contra Postgres real** (PGlite, esquema mínimo tipo Supabase con `anon` /
    `authenticated` / `service_role` y `auth.uid()` por `request.jwt.claim.sub`; 84 casos, la 128
    y después la 129 dos veces seguidas): el orden de los cinco tipos con empates, For Time
    mezclando terminados y no terminados, divisiones, columnas ajenas al tipo, corregir sin mover
    `scored_at`, fechas (próximo / abierto / terminado), lo que el autor puede y no puede editar o
    borrar, oculto, bloqueos en los dos sentidos (también en el conteo), reportes de marca y de
    reto junto a los de posts, resolución al borrar, `anon` sin acceso y borrar la cuenta del
    autor sin que falle (el `on delete set null` es un UPDATE que pasa por el trigger).
  - **No corrida en Supabase.** Va después de la 128, que tampoco está corrida.
- **24 oct 2026** — **Pantallas de la Fase 1** en `app.html`. Versión `20261024-1`.
  - Comunidad tiene dos pestañas, **Feed | Retos** (`setCommunityTab`; la última se recuerda
    en `localStorage`, `habit_comm_tab`). Retos: Activos / Terminados / Míos y «+ Reto»
    (`renderRetos`, tarjetas de `challenge_cards` con tu marca y tu lugar de
    `challenge_standings`).
  - Una sola hoja, `#reto-modal`, con tres modos (`retoOpen.mode`): el **detalle** (WOD, Rx /
    Scaled, la tabla con tu fila resaltada, Realtime sobre `challenge_entries` que solo repinta
    en el detalle para no borrar un formulario), **proponer/editar** (`openRetoForm`; con marcas
    de otros desactiva lo que el trigger rechazaría y manda solo lo que cambió) y **registrar /
    corregir marca** (`openRetoScore`; los campos según el tipo, mm:ss para tiempos, «¿terminaste
    dentro del límite?» en For Time). Corregir manda en null las columnas que no usa el tipo.
  - El ⋯ de arriba: el autor edita, termina hoy o borra (si nadie más registró); los demás
    reportan o bloquean; el admin edita, marca oficial, oculta y borra. Cada marca ajena tiene
    el ⋯ de la 128 (`communityMoreBtn('entry', …)`) y, para el admin, 🗑.
  - Moderación: `COMMUNITY_ITEM_KINDS` le da nombre a los cuatro tipos en el menú, el reporte y
    el push; la cola del admin muestra «Reto de…» / «Marca de…» con «Ver reto», y «Borrar» va
    directo a la tabla (el trigger resuelve los reportes). Admin → Comunidad lista los 30 retos
    más recientes, ocultos incluidos (`renderAdminRetos`); moderar es abrir el reto.
  - Sin la 129 la pestaña dice «Retos todavía no está disponible» y la sección del admin no
    aparece (`isMissingRetosTable`).
  - **Verificado en el navegador local**, en `/crew` y en `/app`, a 375 px, con el cliente de
    Supabase simulado en la página (el servidor local apunta a producción y la 129 no está
    corrida): lista y filtros, detalle con divisiones, registrar (tiempo pasado del límite
    rechazado, link sin `https://` completado), corregir a «no terminé», proponer (sin título, For
    Time sin límite, válido), edición bloqueada, reto terminado sin botón, menús de autor y admin,
    reportar una marca y la cola del admin. Encontrado y arreglado: las pestañas usaban la grilla
    de tres columnas de `.admin-segmented`.
  - **No verificado** contra la base real ni en el iPhone.
- **24 oct 2026** — **128 y 129 corridas en Supabase** (las corrió Joseph) y publicado en Vercel
  (`e2db310`, versión `20261024-1`).
  - Comprobado contra producción, solo lectura y con la llave pública: `challenges`,
    `challenge_entries`, `challenge_standings`, `challenge_cards`, `community_blocks` y las
    columnas `challenge_id` / `entry_id` de `community_reports` existen (responden 42501, permiso
    denegado; una tabla o columna inventada responde PGRST205 / 42703), y `anon` no lee ninguna
    ni ejecuta `challenge_is_open`. `/crew`, `/app`, `sw.js` y los manifests sirven la versión
    nueva con Retos.
  - **Falta:** la prueba con sesión (proponer, registrar, corregir, reportar, bloquear, moderar)
    con dos cuentas reales en el iPhone. No se hizo desde aquí: un reto de prueba lo vería toda
    la comunidad.
- **24 oct 2026** — **Arreglo: las hojas de confirmar y los avisos quedaban detrás de las
  hojas.** `.confirm-overlay` tenía `z-index` 2600 y el toast 999; toda `.terms-modal` tiene
  9999. En producción, desde la Fase 1, el ⋯ del reto, reportar una marca, «Quitar mi marca» y los
  «¿Borrar…?» abrían algo invisible, y los errores al guardar no se veían. La verificación de la
  Fase 1 no lo vio porque tocaba los botones por código. Ahora 10050 y 10060 (`14ad524`, versión
  `20261024-2`). Afecta a toda la app: cualquier `confirmSheet` dentro de una hoja.
- **24 oct 2026** — **Fase 2** (migración **130**, versión `20261024-3`): tarjeta en el feed,
  avisos por trigger y push, tarjeta en Inicio y el cronómetro. «Convertir en rutina» quedó
  descartado (ver §4).
  - **130 probada contra Postgres real** (PGlite: la 128, la 129 y la 130 dos veces; 104 casos, los
    84 de la 129 con la vista nueva y 20 de avisos): aviso al autor solo la primera vez, "te pasó"
    al subir y no al corregir la nota ni al subir sin pasar a nadie, empatar no es pasar, otra
    división no pasa a nadie, autor que además queda atrás recibe un solo aviso, tope de 10 con los
    más cercanos, la app no puede insertar avisos de reto pero sí los comentarios de la 005, el
    aviso de alguien bloqueado no se ve y borrar el reto borra sus avisos.
  - **Verificado en el navegador local** (`/crew`, 375 px, Supabase simulado): la tarjeta en el
    feed mezclada por fecha, Inicio con «Tus retos» y el aviso en ámbar que abre el reto, el
    cronómetro de For Time (Terminé → 0:09 llenado → guardado → 1.er lugar → push a los tres que
    pasó), AMRAP (+1/−1, «Salir» pide confirmar y la confirmación se ve encima, corte a los 12 min
    con las rondas llenadas, push al autor) y Máx. tiempo (Paré → 1:35), y For Time al acabarse el
    tiempo (pide reps).
  - **No verificado** contra la base real ni en el iPhone (sonido, vibración, Wake Lock).
  - **Orden de despliegue:** cualquiera. Sin la 130 la app funciona igual pero no se crean los
    avisos dentro de la app (el push sí sale).
