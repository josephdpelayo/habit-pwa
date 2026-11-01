# Stickers — que lo que entrenas se pueda subir a Instagram

> Plan del 31 oct 2026, rehecho tres veces ese día con Joseph (ver Bitácora). Fase 1 hecha, en
> las dos apps. Relacionados: `HABIT_PARA_TODOS.md`, `RETOS.md`.

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
- La marca cambia sola por app: en HABIT el logotipo dice HABIT; en Crew también HABIT (es la
  misma marca), y el sticker **Check-in** existe solo en HABIT, que es la que tiene gym.

## 3. El estilo

**Una sola fuente: Inter, la de HABIT**, con el **logo original** (`/icons/logo-original.png`).
La variedad sale de cómo se trata la letra, no de cambiar de fuente: peso (de 150 a 900),
itálica, espaciado, contorno, repetición, tamaño. **Blanco o negro**, nunca otro color.

Reglas: un dato héroe (o dos); si hacen falta más de tres renglones, son dos stickers; el
logotipo es siempre el de la app (logo + HABIT en 800 espaciado .1em).

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

## 5. Compartir

- Cada sticker lleva su botón **Compartir** con el ícono universal (cuadro con flecha hacia
  arriba). Abre la hoja del teléfono con el PNG: ahí están Instagram, WhatsApp, Guardar imagen y
  Copiar. Nada escondido detrás de un toque o de mantener presionado.
- Si el teléfono no tiene hoja de compartir (computadora), el botón descarga la imagen.
- La imagen ya está dibujada antes del toque (iPhone solo deja compartir desde un toque y sin
  esperas largas).

## 6. Fases

1. **Galería en el módulo** (`habit-share.js` crea y maneja la hoja) + botón Compartir + la
   frase del día con los estilos que apliquen (13 Frase, 7 Logotipo, 9 Sello). Llega a **las dos
   apps**: en HABIT solo el script y la llamada desde la frase.
2. **Entreno terminado**: la pantalla de resumen al cerrar una sesión y los estilos de entreno
   (1–8, 10, 11). En Crew completa; en HABIT, solo el botón que abre los stickers del entreno
   que acabas de cerrar.
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
- `scripts/check-share.js`: disposición de cada estilo (cabe, va centrado, no pierde texto) y
  que el correo nunca aparece.

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
