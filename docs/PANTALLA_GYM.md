# Pantalla del gym — planificación

24 nov 2026. Joseph pidió una segunda pantalla en el gym que muestre **las rutinas del día** y,
cuando un socio lo decida desde su teléfono, **su entrenamiento en vivo**.

**Estado:** la **fase 1 está escrita** (24 nov): `migrations/152_gym_screen.sql`, `pantalla.html`,
`habit-screen.js`, `scripts/check-screen.js`; cómo funciona está al final de CLAUDE.md. La 152
**se corrió en Supabase el 24 nov 2026**. La pantalla `main` quedó apagada y nadie ha activado su
preferencia. Cambios respecto a este plan al construirla:
- La preferencia vive en su propia tabla, `gym_screen_prefs`, y no en `profiles`: el personal lee
  todos los perfiles y `profiles` tiene triggers que vigilan lo que el socio cambia.
- La invitación se hace **una vez**: cualquier respuesta la da por contestada. Si se cierra con
  ×, se repite la próxima vez que abra la app. No hay tope semanal.
- La regla de qué ejercicios forman la rutina no se duplica en SQL. El servidor manda los datos
  en crudo y la tele los arma con la misma función que la hoja de entreno; la prueba compara las
  dos.
- La pantalla nace **apagada**. Hasta que se encienda en el control, la app no enseña el ajuste
  ni invita a nadie.

La **fase 2 está escrita** (25 nov): `migrations/153_gym_screen_casts.sql`, el botón «Pantalla»
en la hoja de entreno de Crew y la tarjeta en vivo en la tele (y en `/pantalla?demo`). Se
probó en producción dentro de una transacción revertida. Respecto al plan:
- No hay `snapshot` libre: el teléfono manda solo la serie que toca, el descanso y la pausa, en
  columnas. Las series y la rutina ya las tiene la base.
- `gym_screen_casts` no se lee sin sesión: la tele la ve por `gym_screen_state`, y el
  socio solo lee la suya.
- El nombre lo pone `gym_screen_state` desde el perfil, como en la fase 1.

**La rutina del día** (27 nov, migración 156): mientras nadie esté en pantalla, la tele enseña una
rutina básica con todos sus ejercicios a la vista y la demostración de cada uno. Ver CLAUDE.md.

Las fases 3–4 siguen siendo plan.

**Decidido (Joseph, 24 nov):**
- «Rutinas del día» son **las rutinas de quien reservó**, no un WOD del gym elegido por el
  admin. La tele enseña, por horario, quién viene y qué le toca entrenar.
- **Nadie sale en la tele hasta que lo active.** La opción predeterminada es no aparecer; cada
  socio la enciende él mismo.
- **HABIT carga `habit-screen.js`** con una línea `<script>` en `app.html` (más la versión), desde
  F1. Es la excepción pedida, como stickers y Actividad; el resto de `app.html` sigue congelado.

## 1. Lo que ya existe y se reutiliza

| Pieza | Qué aporta | Qué no sirve |
|---|---|---|
| `competencia.html` (`/competencia`) | El molde: una página sin login (llave anon), Realtime + relectura cada 15 s, wake lock, pantalla completa, cursor oculto, tamaños con `clamp(vh)`, estados «Reconectando» / vacío | No se recarga sola cuando hay versión nueva |
| Recepción (`#s-reception` en `app.html`) | El reloj grande de Mazatlán con segundos (commits 006df65, 779266c) y la lista «quién está / próximas entradas» | Lee por una función de Vercel: eso ya agotó el CPU del plan gratis una vez. **La tele no debe consultar Vercel** |
| `coaching_schedule` + `coaching_week_slots()` (115) | Qué rutina le toca a cada quien cada día: la fila del día si ya existe; si no, la semana base o el programa resuelto por `coaching_week_slots`, la única regla de resolución | Solo la leen el dueño y el admin |
| `habit_slot_start()` (120) | Cuándo empieza una reserva en hora de Mazatlán | — |
| `habit-activity.js` / `habit-share.js` | El patrón de módulo compartido que HABIT, congelada, solo carga: IIFE, `APP_GLOBALS` revisados por un script, escucha delegado en el documento, CSS propio | — |

**Lo que la base NO tiene hoy** (revisado en vivo, solo lectura):
- `anon` no puede leer nada de `bookings`, `coaching_schedule`, `coaching_session_sets`,
  `boards`, `exercise_catalog` ni `profiles`. Realtime solo publica `lift_*` y
  `challenge_entries`.
- **Una semana no se estampa hasta que el socio abre la app** (`ensure_coaching_week_from_template`
  corre desde el teléfono). Quien reservó y no ha abierto la app esta semana no tiene fila en
  `coaching_schedule` para hoy, así que la tele tiene que resolver el día igual que el
  estampado, no solo leer filas.
- La serie que toca ahora (`wsFocusSet`), el descanso (`wsRestEndAt`) y el Reloj viven **solo en
  el teléfono**.

**Tamaño real** (últimos 30 días): 25 entrenos cerrados por 8 personas, ~18 series por entreno,
77 min de media; reservas ~4.4 al día (máx. 7), de 21 socios en dos semanas, y nunca más de 4 a la
vez (el cupo). Hay 8 sesiones `in_progress` olvidadas (27 oct–23 nov): la tele filtra por hoy y
actividad reciente, nunca por `status` solo.

## 2. Decisiones

### 2.1 La tele: `pantalla.html` en `/pantalla?s=main&k=<llave>`

Copia del esqueleto de `competencia.html`. El cliente de Supabase se crea con
`persistSession:false`: la tele nunca guarda un login aunque alguien se haya metido ahí.

**Lo que enseña**, de mayor a menor peso:
1. **Ahora en el gym**: las reservas cuyo horario está corriendo (desde 10 min antes, igual que
   la puerta). Una tarjeta por persona —«Ana P.», horario, nombre y color de su rutina, la lista
   de ejercicios con series × reps— y su estado: *por empezar*, *entrenando* (con cuántas series
   lleva, leído de la base) o *terminó*. Máximo 4, el cupo.
2. **Próximas reservas** del día en una franja: hora, nombre y rutina, sin ejercicios.
3. **Transmitiendo** (§2.2): la tarjeta de quien transmite crece y se vuelve su entreno en vivo
   —ejercicio actual en grande, la serie que toca, peso y reps, lo que sigue, y la cuenta del
   descanso en grande—. Con 1 persona transmitiendo ocupa la pantalla; con 2–4, rejilla de 2×2.
4. Sin nadie que haya activado la pantalla en este horario: reloj grande, y como mucho una cifra
   sin nombres («Hoy entrenan 5 personas»).

Solo aparece quien lo activó (§2.5): con *nombre y rutina* sale completo; con *solo nombre y
hora*, sin ejercicios. Quien lo activó y no tiene rutina para hoy sale como «Entreno libre».
Quien no lo activó no sale en ninguna parte, ni en la lista de próximas reservas.

**Cómo se mantiene al día sin gastar Vercel**:
- Los datos llegan de **una sola función de Supabase**, `gym_screen_state(p_screen, p_key)` (§2.3).
- Realtime no puede avisarle a `anon` de cambios en tablas que no puede leer. Por eso hay una
  tabla sin datos personales, `gym_screen_pings (screen_id, bumped_at)`, que sí puede leer, y
  triggers en `bookings`, `coaching_schedule`, `coaching_session_sets` y `gym_screen_casts` la
  tocan. La tele oye ese «algo cambió» y vuelve a pedir el estado (con el mismo antirrebote de
  150 ms y una sola petición en vuelo que la competencia). Respaldo: relectura cada 60 s.
- Versión nueva: cada 15 min pide `/pantalla.html` estático y compara `PANTALLA_VERSION`
  (recarga si cambió y nadie transmite); recarga cada noche a las 4:00; y
  `gym_screens.reload_nonce` da un botón «Recargar tele» que llega por Realtime.
- Hora: el reloj usa `Intl` con `America/Mazatlan`; el descanso se cuenta con hora del servidor
  (`now()` viene en cada respuesta de `gym_screen_state`), porque el teléfono y la tele no tienen
  el mismo reloj.
- Textos en tabla `T = {es, en}`; el idioma de la tele es `gym_screens.lang`. Los nombres de
  ejercicio son contenido y se muestran como están.
- `sw.js`: una línea en `shellFor()` para `/pantalla` (si no, sobrescribe la copia sin conexión
  de la app), `pantalla` en la regex de `notificationclick`, fuera de `SHELL`.

### 2.2 Transmitir: el teléfono **publica una foto** de su entreno

Sin transmitir, la tele ya enseña qué le toca a cada quien y cuántas series lleva (eso sí está en
la base). Transmitir agrega lo que solo sabe el teléfono: **qué serie está haciendo ahora y la
cuenta del descanso**.

**Cómo, sin tocar `app.html`**: un módulo nuevo, `habit-screen.js`, que cargan las dos apps. Pone
el botón **«Pasar a la pantalla»** en la hoja de entreno y, mientras transmite y la hoja está
abierta, cada 1 s lee las variables de la app (`activeCoachingSession`, `coachSessionSets`,
`wsFocusSet`, `wsRestEndAt`, `wsRestTotal`, `wsPausedAt`…), arma un resumen chico y lo escribe
**solo si cambió** (máx. una escritura cada 2 s, más un latido cada 60 s). Se descartó envolver
las funciones de la app (`toggleSetDoneSb`…): no vería el descanso, el foco ni la pausa. Esas
variables son `let` de nivel superior: se leen por nombre con `typeof x !== 'undefined'`, nunca
como `window.x`.

El resumen manda el descanso y el tiempo como **segundos restantes / transcurridos**; el servidor
sella `rest_end_at = now() + restante`. Lleva `unit` (kg/lb) y los pesos en kg, como la app. Sin
conexión no escribe ni encola. Si la tele no recibe nada en 90 s, la tarjeta se atenúa
(«sin señal») pero no se quita: el teléfono se bloquea entre series.

`app.html` recibe **una sola línea** `<script src="/habit-screen.js?v=…">` (más el cambio de
versión), igual que con stickers y Actividad.

### 2.3 Base de datos

**Migración 152 — la pantalla y lo que ve**
- `gym_screens (id text pk = 'main', name, access_key text, mode auto|bookings|off,
  casting_enabled bool, lang text default 'es', reload_nonce int)`. Una fila hoy; tenerla desde
  el principio hace que una segunda tele no cueste nada. `access_key` **no la lee `anon`**.
- `gym_screen_pings (screen_id, bumped_at)`: lo único que `anon` lee directo; en
  `supabase_realtime` (bloque idempotente de la 126). Triggers `after insert/update/delete` en
  `bookings`, `coaching_schedule`, `coaching_session_sets` (solo si la fila es de hoy) la tocan.
- `profiles.screen_visibility text not null default 'hidden'` (`hidden` | `name` | `routine`) —
  ver §2.5. Todas las cuentas que ya existen quedan en `hidden`. Solo el dueño la cambia (la
  regla de update de `profiles` ya lo permite; revisar que `guard_profile_billing` no la frene).
- `gym_screen_state(p_screen text, p_key text) returns jsonb`, security definer:
  1. Si `p_key` no es la `access_key` de esa pantalla → vacío. **La llave anon es pública (está
     en el HTML); la llave de la tele no.** Sin ella, cualquiera con la llave anon podría
     preguntar desde su casa quién va al gym hoy y a qué hora.
  2. Reservas activas de hoy en Mazatlán (`bookings` no canceladas, con `habit_slot_start`).
  3. Por persona: nombre + inicial de `profiles`; su rutina del día = la fila de
     `coaching_schedule` de hoy si existe (`exercise_snapshot` o `boards.exercises` +
     `session_exercises`, la misma regla de `sessionExerciseList`), y si no, lo que resuelve
     `coaching_week_slots` para ese día (programa con `start_date` o semana base); estado y
     series hechas de `coaching_session_sets`.
  4. Las transmisiones vigentes de esa pantalla (§ 153).
  5. Deja fuera a todo `hidden` (lo filtra el servidor, no la tele: lo que no se activó nunca
     sale de la base) y devuelve solo lo que la tele pinta: nada de correo, teléfono, notas del
     coach ni feedback. De los `hidden` solo cuenta cuántos hay.
  - `revoke execute … from public` y `grant` explícito a `anon` solo de esta función; nada de
    escribir. La lógica de «qué toca hoy» queda escrita en SQL una segunda vez: hay que cuidar
    que `sessionExerciseList` y esta función no se separen (la prueba de §3 compara las dos).

**Migración 153 — transmitir**
- `gym_screen_casts (user_id pk, screen_id, schedule_id, snapshot jsonb, rest_end_at,
  updated_at, expires_at)`. Sin política para `anon`: la tele la ve a través de
  `gym_screen_state`.
- `start_gym_cast(p_screen, p_schedule)` revisa: la sesión es suya, `in_progress` y de hoy;
  **tiene una reserva corriendo ahora** (10 min antes a 15 min después; staff exento); la
  pantalla acepta transmisiones; hay menos de 4.
- `update_gym_cast(p_snapshot, p_rest_remaining_s)`: lista blanca de llaves, tamaño < 6 KB.
  `stop_gym_cast()`.
- El servidor decide cuándo termina: un trigger en `coaching_schedule` borra la transmisión
  cuando el estado deja `in_progress` (cubre cerrar desde otro aparato y la cola que sube
  tarde); `expires_at = least(última escritura + 20 min, fin de la reserva + 15 min)` y un
  pg_cron cada 5 min borra lo vencido.
- Lección de la 124: cada RPC del socio lleva `revoke execute … from public, anon` y revisa
  `auth.uid()` adentro.

La regla es **la reserva**, no la app: una cuenta solo de Crew nunca sale en la tele ni puede
transmitir (no tiene reservas), y nadie sale desde su casa fuera de su horario.

### 2.4 Control

`/pantalla?control` en el teléfono del admin usa la sesión que ya tiene en la app (mismo origen,
`persistSession` normal) y permite: modo de la tele, apagar las transmisiones, «Recargar tele»,
cambiar la llave de la tele (y enseñar la URL nueva para escribirla en el aparato), idioma, y ver
la vista previa. El panel no entra en `app.html`, que está congelada.

### 2.5 Privacidad

**Nadie aparece hasta que lo activa.** Cada socio decide:
- **Perfil → Pantalla del gym**, tres opciones: *no aparecer* (predeterminada), *solo mi nombre y
  mi hora*, *mi nombre y mi rutina*. La pone `habit-screen.js` en las dos apps.
- **Transmitir el entreno en vivo es aparte** y se elige en cada entreno. Si alguien transmite
  sin haber activado la pantalla, solo sale mientras transmite.
- **Cómo se entera la gente** (porque con la predeterminada apagada la tele empieza vacía):
  - una invitación al **reservar**, en el mismo lugar y con el mismo freno que la de avisos
    (`maybeAskPush`: pocas veces, máximo una por semana, y nunca a quien ya respondió);
  - la tarjeta de la tele en Perfil;
  - el botón «Pasar a la pantalla» al empezar un entreno con reserva.
  - Nunca se activa sola ni con una respuesta por omisión: «Ahora no» deja `hidden`.
- En la tele, solo nombre e inicial; nunca foto, correo ni datos del plan.
- Lo que viene del teléfono se pinta con `textContent`, nunca `innerHTML`.
- Interruptor del staff (`casting_enabled`, `mode = off`), vencimiento automático y llave de tele
  que se puede cambiar.

## 3. Fases

**F1 — La tele con las reservas del día**
Migración 152, `pantalla.html` (reloj, ahora en el gym, próximas reservas, autoactualización),
modo control, `habit-screen.js` solo con el ajuste de Perfil y la invitación, cargado por
`crew.html` **y `app.html`** (la línea `<script>`), `sw.js`, versión en todos lados, CLAUDE.md. Prueba `scripts/check-screen.js`: la tele y `sessionExerciseList` dan la
misma lista de ejercicios para los mismos datos; cada texto tiene es y en; las dos apps cargan el
módulo.

**F2 — Transmitir, primero en Crew**
Migración 153, el botón y el resumen en `habit-screen.js`, tarjetas en vivo en la tele. La prueba
agrega: las variables que el módulo lee existen en las dos apps. Se prueba en el gym con un
teléfono.

**F3 — Transmitir en HABIT**
No pide tocar `app.html` otra vez: el módulo ya está cargado desde F1, y encender el botón en
HABIT es una bandera dentro de `habit-screen.js` una vez probado en Crew.

**F4 — Después**
Emparejar con un código o QR en la tele (prueba presencia sin depender de la reserva y elige
pantalla si hay varias), el reto oficial del día (`docs/RETOS.md` ya lo planea), iconos de
ejercicio (mover `EXERCISE_ICONS` al módulo compartido `habit-training.js`), celebrar un récord
personal.

## 4. Pregunta pendiente para Joseph

1. **¿Qué aparato será la tele?** (Smart TV con navegador, Fire TV, Chromecast con Google TV, mini
   PC, iPad…). Cambia el wake lock y la pantalla completa.

## 5. Riesgos

- La regla de «qué rutina toca hoy» vive en el cliente (`sessionExerciseList`, el estampado) y
  ahora también en `gym_screen_state`. Si una cambia y la otra no, la tele enseña otra cosa que
  el teléfono. `check-screen.js` compara las dos.
- El módulo depende de nombres de variables de la app: si alguien renombra una en `crew.html`,
  transmitir deja de funcionar sin error. `check-screen.js` lo vigila.
- iOS duerme la PWA y la app de Capacitor en segundo plano: por eso nada se quita antes de 20 min.
- Con la predeterminada apagada, la tele vale lo que valga la invitación: si pocos la activan, se
  ve casi siempre el reloj. Medir en Admin cuántos la activaron en las primeras dos semanas.
- La llave de la tele está escrita en el aparato: si sale del gym (foto de la URL), se cambia
  desde el control.
