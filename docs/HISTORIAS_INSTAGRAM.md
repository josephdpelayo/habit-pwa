# Stickers — que lo que entrenas se pueda subir a Instagram

> **Idiomas (requisito del 1 nov 2026):** textos de la galería y de los stickers en español e
> inglés, de acuerdo con la elección de idioma de HABIT/HABIT Crew. La localización global
> está pendiente; los nuevos diseños deben contemplar ambas traducciones y su longitud.

> Plan del 31 oct 2026, rehecho tres veces ese día con Joseph (ver Bitácora). Fases 1 y 2 hechas
> (la 2 solo en Crew); la galería ya trae 11 estilos de frase, 16 de entreno y 7 de semana, y
> desde el 1 nov **todos firman como HABIT Crew**.
> Relacionados: `HABIT_PARA_TODOS.md`, `RETOS.md`.

## 1. La idea

Al terminar un entreno (o desde la frase del día, tu semana, un récord), HABIT te da una
**galería de stickers**: PNG con fondo transparente con tus números. Cada uno tiene su botón
**Compartir** con el ícono universal de compartir: abre la hoja del teléfono (Instagram,
WhatsApp, Guardar imagen, Copiar). En Instagram el sticker va encima de tu foto.

Por qué: es la recompensa del entreno (hoy cerrar una sesión termina en un aviso de dos
segundos) y cada historia enseña HABIT. Gratis para todos. Nada nuevo en el servidor.

## 2. En las dos apps

Los stickers van en **HABIT y en HABIT Crew** (pedido de Joseph, 31 oct). HABIT está congelada
(`app.html`, ver `CLAUDE.md`), así que la regla es que **HABIT reciba los stickers y nada más**:

- **Todo vive en `habit-share.js`**: el dibujo, la galería (la hoja, sus estilos, el botón) y
  compartir. La hoja la crea el propio módulo en el DOM, con su CSS adentro.
- Cada app solo **lo carga y lo llama**: `HabitShare.open({ kind:'quote', … })` con los datos que
  ya tiene. En `app.html` eso son el `<script>` y las llamadas en los puntos de entrada
  (la frase del día, el entreno terminado), sin tocar el resto de la app.
- **La firma es HABIT Crew en las dos apps** (Joseph, 1 nov: «que los stickers impulsen la marca
  HABIT Crew, tanto en la app de HABIT como en HABIT Crew»). Un sticker lo ve gente que todavía
  no tiene la app, y la que puede bajar es Crew. El sticker **Check-in**, cuando exista, va solo
  en HABIT, que es la que tiene gym.

## 3. El estilo

**Una sola fuente: Inter, la de HABIT**, con el **logo original** (`/icons/logo-original.png`).
La variedad sale de cómo se trata la letra, no de cambiar de fuente: peso (de 150 a 900),
itálica, espaciado, contorno, repetición, tamaño. **Un solo color por sticker**: era blanco o
negro, y desde el 1 nov (Joseph: «poder escoger entre varios más colores, para darle
versatilidad») se elige de una paleta de 12 —blanco, negro, crema, azul, cielo, lima, verde,
amarillo, naranja, rojo, rosa, lila; azul, verde, rojo y lila son los de la marca— o uno libre
con el selector del teléfono. Lo que va dentro de una forma rellena (recibo, carnet, cinta,
globo) lleva la tinta de `inkFor()`: blanco si contrasta 3:1 con el color (WCAG, letra grande),
si no negro.

Reglas: un dato héroe (o dos); si hacen falta más de tres renglones, son dos stickers; el
logotipo es el de HABIT Crew, como el encabezado de Crew: logo (1.15 de HABIT) + HABIT en 800
espaciado .06em + CREW en 600, chico (0.6 de HABIT) y espaciado .3em, sobre la misma línea base.
Ningún sticker sale sin marca, y **todos firman abajo con el mismo logotipo, a `SIG` (40 px)**.
Ninguna letra secundaria baja de ~30 px en el lienzo de 1080: en una historia el sticker se ve
a un tercio, y lo que medía 22 px desaparecía. **El cuadro de un logo es su tinta**: el PNG trae
margen (la tinta es ~65%, `LOGO_INK`) y `drawLogo` lo agranda; medirlo por su cuadro dejaba
todos los logos a dos tercios de lo que se quería.

## 4. Catálogo de estilos

Boceto del 31 oct (todos en Inter + logo real):

| # | Estilo | Tratamiento | Ejemplo |
|---|---|---|---|
| 1 | Héroe | 900, apretado | `4,320` + `KG MOVIDOS` espaciado |
| 2 | Ligero | 150, enorme | `52:14` + *minutos de entreno* |
| 3 | Espaciado | 300 muy espaciado + 900 | `S Á B A D O` / `LEG 2` |
| 4 | Itálica | 800 itálica | *Leg day.* |
| 5 | Contorno | 900 solo trazo | `PR` + `100 KG × 5` |
| 6 | Eco | la palabra repetida desvaneciéndose | `LEG 2` ×4 |
| 7 | Logotipo | el logotipo de la app | logo HABIT + `ENTRENO Nº 47` |
| 8 | Recibo | 500, números tabulares, puntos guía | TIEMPO …… 52 MIN |
| 9 | Sello | texto en círculo alrededor del logo | MAKE IT A HABIT · ENTRENO Nº 47 |
| 10 | Burbuja | mensaje del iPhone en blanco y negro | «Leg 2 listo, 52 min» · *Entrenado* |
| 11 | Notificación | el aviso de HABIT con el logo | «Leg 2 completado» |
| 12 | Racha | 900 enorme + texto vertical | `6` SEMANAS SEGUIDAS |
| 13 | Frase | 500 + logotipo chico | la frase del día |
| 14 | Check-in (solo HABIT) | logotipo + lugar + hora | HABIT · MAZATLÁN · 11:00 |

Cada estilo puede tener **variantes** con otro dato (el Héroe sirve para kg, minutos, series o
nº de entreno). Datos disponibles: rutina, día y hora, duración, series, kg, ejercicios con su
mejor serie, músculos (con palabras, sin dibujo del cuerpo), récords, nº de entreno, racha.

### Lo que hay (1 nov 2026)

- **De la marca** (en los tres tipos, segundos en la galería después del primero): **Crew** (la
  marca apilada: el logo, HABIT espaciado al ancho exacto de CREW, y CREW enorme; debajo tu dato
  o la frase), **Carnet** (una credencial de la crew con proporción de tarjeta: logotipo, el
  logo grande y tenue cortado por el borde derecho como un holograma, la cifra o la frase, y abajo el día y `habittraininghub.app/crew`) e **Insignia** (escudo
  redondo: HABIT CREW y tu entreno dan la vuelta entre dos anillos, con HABIT CREW centrado
  arriba; dentro el logo y la cifra; no hay de frase, para eso está el Sello).
- **Frase del día** (9 + Crew y Carnet): Frase, Póster (900 en mayúsculas, a la izquierda, con barra), Itálica
  (300 itálica), Cinta (cada renglón en su tira), Mensaje (burbuja que te llegó de HABIT),
  Comillas (unas comillas enormes), Mínimo (400 entre dos líneas finas), Logotipo, Sello.
- **Entreno** (13 + los tres de la marca; uno sin el dato que enseña no sale): Héroe, Datos (dos
  o tres cifras como en un reloj; con una sola —yoga, un entreno libre— no sale: sería un Héroe
  chico), Recibo (ticket con ejercicios, código de barras y Nº de entreno), Ligero (el tiempo en
  Inter 200), Itálica, Contorno, Notificación, Mensaje («10.02 km corridos. 52:14.» con su
  «Entrenado»), Cinta, Espaciado, Eco, Sello, Logotipo. Sirven igual para un entreno de la app
  (series, kilos, ejercicios con su mejor serie) que para una carrera, un nado o una rodada
  registrados a mano (distancia, ritmo, velocidad, FC).
- **Semana** (4 + los tres de la marca): Semana (cuántos y los siete días como puntos), Héroe,
  Racha (desde 2 semanas seguidas), Datos.

## 5. Compartir

- La galería se **desliza** de un estilo a otro, con miniaturas debajo para saltar, y un solo
  botón **Compartir** (ícono universal) para el que se ve. Abre la hoja del teléfono con el PNG:
  ahí están Instagram, WhatsApp, Guardar imagen y Copiar. El truco para ponerlo encima de tu
  foto: **Copiar** y pegarlo en la historia.
- Si el teléfono no tiene hoja de compartir (computadora), el botón descarga la imagen.
- La imagen ya está dibujada antes del toque (iPhone solo deja compartir desde un toque y sin
  esperas largas).

## 6. Fases

1. **Galería en el módulo** (`habit-share.js` crea y maneja la hoja) + botón Compartir + la
   frase del día con los estilos que apliquen (13 Frase, 7 Logotipo, 9 Sello). Llega a **las dos
   apps**: en HABIT solo el script y la llamada desde la frase.
2. **Entreno terminado** ✓ (Crew): al cerrar una sesión salen sus stickers, y la pestaña
   Actividad tiene los de cada entreno (de la app o registrado de fuera) y los de tu semana. En
   HABIT falta: sería solo el botón que abre los stickers del entreno que acabas de cerrar.
3. **Récord, racha y check-in**: 5, 12 y 14 (este, al abrir la puerta en HABIT).
4. **Comunidad** (publicar el sticker con fondo en el feed) y, con la app nativa, mandarlo
   directo a Historias.

## 7. ¿Qué más? (ideas para después)

- **Hitos automáticos**: al llegar a 10, 25, 50, 100 entrenos, un sticker especial
  (`50` enorme + ENTRENOS EN HABIT).
- **Check-in del gym** (HABIT): al abrir la puerta, «¿Compartes que llegaste?» con el sticker 14.
  Es el que más enseña el lugar.
- **Retos**: tu lugar en un reto (`1º` + el nombre del reto).
- **Resumen del mes / del año**: entrenos, horas, toneladas, tu ejercicio más hecho.
- **Con fondo**: cada sticker también en 1080 × 1920 grafito, para quien no tiene foto.

## 8. Detalles técnicos

- Canvas a 1080 px de ancho; PNG transparente; el logo se tiñe de negro en el sticker negro.
- Inter ya la carga la app; antes de dibujar, `document.fonts.load()` de los pesos que se usan.
- El sello (texto en círculo) se dibuja letra por letra con rotación.
- Los estilos nuevos se describen como trazos (`ops`: texto, logo, rectángulo, círculo, línea,
  polígono) que dibuja `drawOps`; `scripts/check-share.js` revisa con cada tipo de entreno que
  ningún trazo se salga del lienzo, que la frase no pierda texto, los formatos (10.02 km, 5:13
  /km, 1,500 m, 26.7 km/h) y que el código de barras sea siempre el mismo para el mismo entreno.
- Inter de 100 a 900 y su itálica se piden a Google Fonts **al abrir la galería** (`#hs-inter`):
  las apps solo cargan de 300 a 800.
- Cada cifra va pegada a su unidad con un espacio duro («52 min» no se parte en dos renglones).

## Bitácora

- **2026-10-31 — Fase 0** (versión `20261031-6`). `habit-share.js` con dos stickers de la frase
  del día: la frase en Instrument Serif itálica, centrada y en renglones parejos, con el anillo y
  MAKE IT A HABIT debajo; y la firma «Make it a habit.» con el anillo. 1080 px de ancho, PNG
  transparente, blanco o negro (se recuerda en `localStorage`). Se abre tocando la frase en Inicio
  («Sticker» en su pie). Tocar copia; mantener deja el menú nativo de la imagen.
  - Encontrado al probar: la serif salía en Georgia porque se pedía la fuente antes de que la hoja
    de Google Fonts la declarara. Ahora se espera a la hoja.
  - Las 31 frases del día no tenían acentos («dias», «mañana» sin ñ); se corrigieron 22.
  - Probado en el navegador: stickers de 1080 × 452 y 942 × 260, esquina transparente, blanco y
    negro. **Falta probar en el iPhone:** copiar → pegar en una historia de Instagram, y mantener
    → Guardar en Fotos. El navegador de prueba no da permiso de portapapeles y cayó al plan B
    (descargar).
- **2026-10-31 — Ajustes de Joseph tras probarlo en su iPhone** (versión `20261031-7`).
  - **El logo real**: los stickers dibujan `/icons/logo-original.png` (el del encabezado), teñido
    de negro en el sticker negro; ya no un anillo dibujado.
  - **La fuente de HABIT**: Inter, como el logotipo (HABIT en 800 espaciado), en lugar de
    Instrument Serif. La frase va en Inter 600; la firma es el logotipo de HABIT con MAKE IT A
    HABIT debajo. La tabla de fuentes de §3 queda para las fases siguientes, a revisar con él.
  - **Solo en HABIT Crew** (`crew.html`): la app del gym no tiene stickers.
- **2026-10-31 — Fase 1** (versión `20261031-8`), en HABIT y HABIT Crew.
  - `habit-share.js` trae la galería completa: hoja propia (clases `hs-*`, CSS que se inyecta al
    cargar para que el botón de cada app se vea bien antes de abrir nada), blanco/negro, y por
    sticker su botón **Compartir** con el ícono universal (`navigator.share` con el PNG). Ya no
    hay «toca para copiar · mantén para guardar»: la hoja del teléfono trae Copiar y Guardar.
  - Tres estilos para la frase del día: **Frase**, **Logotipo** y **Sello** (el texto da la vuelta
    al logo con la fecha; la letra crece hasta llenar ~78% del círculo).
  - Las apps solo marcan la frase con `data-hs-share` y ponen el botón «Compartir» debajo de ella.
    En HABIT ese es todo el cambio, más el `<script>`.
  - Probado en el navegador: los tres estilos en las dos apps, en blanco y negro, y que Compartir
    entrega un PNG de ~100 KB. Falta el iPhone.
  - Las frases del día de HABIT ya llevan acentos (las mismas 22 correcciones que Crew), con el
    visto bueno de Joseph: salen en los stickers.
- **2026-11-01 — Fase 2 y más estilos** (versión `20261101-1`). Joseph: «se ven aesthetic, me
  gustaron, demos más opciones».
  - Seis estilos más para la frase (Póster, Itálica, Cinta, Mensaje, Comillas, Mínimo), trece de
    entreno y cuatro de semana (lista en §4).
  - La galería pasó de lista a carrusel: con 13 estilos la lista era un scroll eterno.
  - En Crew: la pestaña **Actividad** (ver `HABIT_PARA_TODOS.md`, bitácora del 1 nov) y los
    stickers al cerrar un entreno.
  - HABIT recibe los estilos nuevos de la frase y el carrusel (vienen en `habit-share.js`), sin
    cambios en `app.html` más que la versión.
  - Encontrado al probar: con scroll-snap, saltar a un estilo con desplazamiento suave mientras se
    pintaba otro sticker regresaba al primero. El salto ahora es directo, y pintar solo cambia el
    `src` de una imagen que ya estaba.
- **2026-11-01 — Todos firman como HABIT Crew** (versión `20261101-2`). Joseph: «me gustaría que
  esto de los stickers impulse la marca HABIT Crew… tanto en la app de HABIT como en HABIT Crew».
  - El logotipo de todos los stickers pasa de «HABIT» a «HABIT CREW» (CREW chico, como el
    encabezado de Crew), en las dos apps; la Notificación y el Mínimo dicen HABIT CREW, y los
    Sellos llevan HABIT CREW en la vuelta.
  - Ligero, Contorno, Espaciado, Eco y el Mensaje del entreno no traían marca: ahora firman.
  - Tres estilos de la marca: Crew, Carnet e Insignia (§4). El Carnet lleva
    `habittraininghub.app/crew`: quien ve la historia sabe dónde se baja.
  - `scripts/check-share.js` falla si un estilo no dice CREW.
  - De paso, Contorno: Inter variable trae contornos encimados dentro del 4 y el trazo los
    dibujaba; ahora se traza al doble y se borra el relleno (queda solo el borde). Y la coma de
    «4,320» ya no toca la unidad.
- **2026-11-01 — Más colores** (versión `20261101-3`). Joseph: «también para poder cambiar el
  color del sticker, no solo blanco y negro… para darle versatilidad».
  - `PALETTE` con 12 colores y uno libre (`<input type="color">` dentro del último círculo, que
    se pinta al dejar de moverlo). Los colores pasaron de la cabeza de la galería a una fila que
    se desliza debajo del sticker.
  - La tinta de las formas rellenas ya no es «el contrario del blanco»: `inkFor()` elige blanco
    o negro por contraste, y la prueba revisa que cada color de la paleta llegue a 3:1.
  - El fondo de la vista previa también se elige por contraste: oscuro para los colores claros,
    claro para los oscuros.
  - Se recuerda el último color, también uno libre (`habit_sticker_color`: la clave o `#rrggbb`).
- **2026-11-01 — Menos toscos** (versión `20261101-5`). Joseph: «que estén bien estilizados…
  algunos se ven muy toscos». Revisados los 50 a escala de historia, en blanco, negro y lima.
  - El logo del Sello estaba en un cuarto del círculo: el PNG trae margen. Ahora el cuadro de
    todo logo es su tinta (`LOGO_INK`, `drawLogo` lo agranda), y con eso crecieron también los
    logotipos, la Insignia, el Crew y el icono de la Notificación.
  - Una sola firma, `SIG` = 40 px (`signOps`), en lugar de tamaños de 22 a 30; la firma de solo
    texto «HABIT CREW» de Ligero, Contorno, Espaciado y Eco pasó al logotipo como los demás.
  - Letra secundaria a ~30 px o más en todos (etiquetas, fechas, unidades, filas del Recibo, la
    Notificación, Mínimo, Datos). Una frase corta crece (`fewLines`: «Hazlo.» sale al doble que
    una larga) sin pasar de tres renglones; el Póster abre su interlineado para los acentos.
  - Carnet: el «chip» parecía de relleno; ahora es el logo tenue cortado por el borde (op `logo`
    con `clip`). En el de la semana, la racha sube a la esquina.
  - Ligero en Inter 200 (el 100 quedaba en trazos de un pixel), Mensaje con la cola curva de
    iMessage, Cinta con tiras de al menos 58 px (un nombre larguísimo se corta con «…»), Datos
    no sale con una sola cifra.


## Galería personalizable — 20261101-6

### Diagnóstico y dirección

El catálogo anterior mezcla firmas discretas con composiciones donde Crew ocupa todo el
sticker. Además, cada plantilla selecciona los datos por su cuenta: elegir un diseño cambia
lo que se cuenta. El nuevo flujo separa la selección de información de su presentación.
La dirección es editorial: tipografía Inter, espacio negativo, líneas finas, un dato principal,
y métricas secundarias. Mantiene PNG transparente, 12 colores y color libre.

### Entreno y semana

Los primeros tres diseños compatibles con la selección explícita son:

- Editorial: cifra principal y secundarios en dos columnas, sin fondo.
- Ficha: la misma jerarquía sobre una tarjeta redondeada del color elegido, con tinta de contraste.
- Compacto: valores alineados a la derecha y etiquetas a la izquierda, sin fondo.

«Qué quiero mostrar» ofrece casillas solo para datos disponibles. En entrenos: título,
tiempo, distancia, ritmo/velocidad, FC media, número, series, volumen, calorías, desnivel,
esfuerzo y fecha. En semana: cantidad, tiempo total, distancia total, racha, fechas y días
entrenados. Por defecto se seleccionan título/tiempo/distancia o cantidad/tiempo/días/fechas.
Sin casillas quedan únicamente el encabezado y la firma; nunca se recupera una cifra oculta.
Los días activos representan días distintos, mientras que la cantidad cuenta sesiones.
No se calculan FC ni calorías semanales porque el resumen actual no entrega esos datos.

### Marca

Los tres diseños usan el mismo lockup horizontal: logo + HABIT + CREW, con las proporciones
internas de `lockupLayout`. Se calcula un ancho objetivo de 320 px en el lienzo de 1080
(~30%); el tamaño de fuente se redondea a píxeles enteros. La firma conserva tamaño,
alineación izquierda y aire propio aunque cambie el contenido. El logo se mide por su tinta.
La firma nunca se convierte en el dato protagonista.

Desde `20261101-7`, los estilos anteriores vuelven a la galería personalizable: todos
respetan `data.fields`. Cada plantilla de entreno conserva su composición y muestra los
campos que utiliza entre los seleccionados; los datos desmarcados nunca se recuperan. Las frases conservan su
catálogo actual. No se modifican los datos del entrenamiento ni se guardan preferencias
personales en el servidor.

### Verificación

Pruebas de cada campo aislado, selección vacía y selección completa, ausencia de FC no
registrada, exclusión de datos desmarcados y trazos dentro del lienzo. Revisión local de la
galería con ejemplos de carrera y semana, casillas en vivo, cambio de estilo y color lima.
Pendiente: pegado y tamaño percibido en una historia real desde iPhone/Android.


### 20261101-7 — Variedad recuperada y semana como protagonista

La restricción a tres opciones era una regresión del selector de información, no una decisión
sobre el catálogo. Se elimina el filtro y se adaptan los hechos del entreno antes de construir
las plantillas anteriores. Se recuperan hasta 19 estilos de entreno (algunos necesitan tiempo
o varias métricas); las casillas también permiten controlar ejercicios y mejores series.

La semana ofrece 13 opciones con selección explícita:

- Ritual: calendario de siete casillas con palomitas, cantidad protagonista y métricas debajo.
- Bitácora: papel con bordes dentados, separadores punteados y código de barras decorativo.
- Balance: tablero de cifras en dos columnas y días activos en puntos.
- Editorial, Ficha y Compacto: las tres composiciones anteriores.
- Semana: cifra centrada y calendario grande.
- Crew: «MAKE IT / A HABIT.» y resumen centrado.
- Carnet: tarjeta sólida con el resumen y calendario.
- Insignia: cifra dentro de dos anillos y datos debajo.
- Héroe: cifra en contorno.
- Racha: semanas seguidas en itálica cuando se selecciona racha; si se oculta usa otra métrica seleccionada.
- Datos: columnas de métricas.

No se inventan intensidades ni cantidades por día: las siete marcas solo representan presencia.
La firma horizontal mantiene un ancho objetivo de 320 px en todos los diseños semanales.
Se verifican los 13 diseños con las 64 combinaciones de los seis campos semanales.


### 20261101-10 — Disciplinas y referencia «THIS WEEK»

El resumen semanal recibe `disciplines:[{type,count,durationSec,distanceM}]` desde
`HabitActivity.weekSummary`. Se agrupa la lista ya conciliada, dentro de los siete días de la
semana: correr, fuerza, bici, nado, caminar, cardio, yoga, deportes y otros. La distancia de
correr no incluye caminar ni bici; fuerza se representa por tiempo y nunca por distancia.

Las casillas añaden cada disciplina disponible, con su métrica principal en la etiqueta.
Por defecto se incluyen las disciplinas; «Solo disciplinas» desmarca totales, calendario y
fechas, y «Resumen completo» selecciona todos los datos disponibles. El estilo elegido se
mantiene al cambiar la selección. Los totales y cada disciplina se controlan por separado:
desmarcar Tiempo total no oculta un tiempo de Fuerza que esté seleccionado expresamente.

Cuatro estilos nuevos, sin quitar los 13 anteriores (17 cuando hay desglose):

- This Week: referencia de Joseph, «THIS WEEK», pictogramas y cifras anchas en filas compactas.
  Usar «Solo disciplinas» para acercarse a la referencia: correr en km y fuerza en H/M.
- Mix: bandas redondeadas sólidas, pictograma, nombre y cifra en tinta de contraste.
- Pasaporte: sellos deportivos en una cuadrícula de dos columnas.
- Tipográfico: nombres grandes con punto, cifras debajo y divisores finos.

Los 13 estilos existentes también incorporan «POR DISCIPLINA» antes de la firma. No se
rellena el desglose cuando los datos antiguos solo traen totales; en ese caso se conservan
las 13 opciones. Pictogramas vectoriales propios (`sport`), sin emojis ni descargas; el texto
ancho (`scaleX`) se mide antes de alinear. Todos mantienen la firma horizontal de ~320 px.

Pruebas: sumar fuentes conciliadas sin duplicarlas, excluir otras semanas, separar los km por
deporte, selección individual y vacía, conservar todos los estilos y que nueve disciplinas con
cifras largas quepan dentro del PNG. Revisión visual local de los cuatro diseños y sus casillas.


### 20261101-11 — Referencias Aura: diario, notas, gráficas y condensado

Referencias aportadas por Joseph: IMG_9301.PNG, IMG_9302.PNG e IMG_9303.PNG. La dirección
visual es tipografía compacta de alto contraste, datos alineados, listas cronológicas,
separación por día y gráficas sencillas. Se añaden cinco diseños semanales a los 17 existentes:

- Diario: día de la semana, pictograma y métrica principal de cada sesión.
- Notas: lista con palomitas, cifras y nombre de la disciplina, sin títulos privados de rutinas.
- Barras: siete días y una gráfica independiente por disciplina; km para distancia y minutos
  para tiempo, sin combinar unidades en un mismo eje.
- Tabla: filas por día y total por disciplina, con valores alineados a la derecha.
- Impacto: una cifra grande por deporte en Inter 900 condensada horizontalmente.

`weekSummary` pasa `sessions:[{ds,type,durationSec,distanceM}]` desde las actividades ya
conciliadas y ordenadas de esa semana. No se reconstruye un desglose diario a partir de un
total semanal. Diario/Notas/Barras/Tabla aparecen cuando hay sesiones reales; Impacto solo
necesita agregados por disciplina. Con los datos completos, la galería tiene 22 opciones.

Dos casillas nuevas controlan «Detalle de entrenamientos» y «Distribución por día»; los
estilos anteriores excluyen estos campos de sus cifras principales. «Solo disciplinas»
conserva esas dos selecciones para que los formatos de detalle sigan funcionando. Las listas
muestran hasta 36 sesiones y anuncian cuántas adicionales hay. Las tablas de distancia usan
«—» cuando falta la medida, y las gráficas distinguen descanso (0) de medida ausente («—»).
Si la distancia del día es parcial, se marca con «+».

Los textos de los cinco nuevos diseños y sus dos controles tienen diccionario ES/EN
(`WEEK_REFERENCE_COPY`). `HabitShare.open({lang:'en', ...})` y `data.lang` permiten elegir la
versión exportada; en ausencia de opción se usa el idioma del documento. El selector global
de idioma y las traducciones del resto de la app siguen pendientes. No anunciar bilingüismo
global por haber localizado estos diseños.

Verificación: todos los diseños dentro del lienzo, selección vacía/por disciplina, días y
cifras en ambos idiomas, fuerza medida en minutos, km separados, listas largas y falta de
GPS. Revisión visual en navegador con un ejemplo mixto de once sesiones.

### 20261102-1 — Título personalizado del sticker

- Entrenos y resúmenes semanales muestran un campo «Título del sticker» encima de las
  opciones. Es opcional, hasta 60 caracteres; vacío o solo espacios recupera el título
  predeterminado de cada diseño. El título de la hoja sigue siendo «Tu entreno» / «Tu semana».
- `data.customTitle` solo afecta la imagen; no escribe ni renombra la actividad original.
  Se conserva al cambiar diseño, color o selección de métricas dentro de la galería.
  Escribir un título de entreno activa la casilla del nombre para que se vea; desmarcarla
  vuelve a ocultarlo. Al abrir otro sticker se parte de sus propios datos.
- Los 22 diseños semanales aceptan el título; si es largo, gana renglones sin cambiar
  la proporción de la firma. Los diseños numéricos de entreno también lo incorporan.
  Las frases conservan su contenido y no muestran este editor.
- Campo, ayuda y ejemplo preparados en español e inglés. El selector global de idioma
  sigue pendiente. Las flechas del teclado editan el texto sin cambiar de diseño.
- Verificación: catálogo, títulos largos, vuelta al predeterminado, selección y datos
  originales en `check-share.js`; editor y PNG de vista previa revisados en navegador
  con datos de ejemplo. La prueba dentro de Instagram en iPhone sigue pendiente.

### 20261102-2 — Legibilidad dentro de una historia

La captura de Instagram mostró etiquetas de 30–32 px y cifras de disciplina de 68 px,
demasiado pequeñas al reducir un PNG de 1080 px. Se revisaron las proporciones del catálogo:

- Desglose semanal compartido: nombres de disciplina a 60 px y cifras hasta 132 px,
  iconos mayores y separación para que la fecha no toque la última cifra. Se elimina
  el encabezado redundante «POR DISCIPLINA». Títulos y días crecen también.
- Los 22 estilos semanales y los de entreno reciben etiquetas, cifras secundarias y
  fechas mayores, con ajustes de renglones y espacios. La firma semanal pasa de un ancho
  objetivo de 320 a 400 px; las firmas secundarias de los demás estilos también crecen.
- El diseño Logotipo mantiene un ancho de 1080 px: los subtítulos largos ganan renglones
  en vez de ensanchar el PNG y empequeñecer el conjunto al pegarlo.
- La galería abre con «Ver en una historia»: marco 9:16 con fondo de contraste y tamaño
  aproximado. Puede desactivarse para ver el sticker de cerca. El marco y su nota no se
  exportan; el PNG conserva transparencia. Textos nuevos preparados para ES/EN.
- Las miniaturas solo desplazan su carrusel horizontal; ya no desplazan verticalmente
  la hoja cuando se actualiza el título o se dibuja el catálogo.
- Verificación: catálogo existente, combinaciones de casillas, títulos largos, cifras
  legibles a 300 px de ancho y separación entre fecha y métricas. Comparación en navegador
  con Inter y datos de ejemplo, a idéntica escala sobre un marco de historia. Instagram
  controla la escala inicial al pegar; falta repetir la prueba en el iPhone.
