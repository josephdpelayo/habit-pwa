# Stickers — que lo que entrenas se pueda subir a Instagram

> Plan del 31 oct 2026, rehecho el mismo día después de ver cómo lo resuelve AURA. Fase 0
> hecha (ver Bitácora al final). Relacionados: `HABIT_PARA_TODOS.md` (HABIT Crew, Comunidad), `RETOS.md`.

## 1. La idea en una línea

Al terminar un entreno, HABIT te da una **galería de stickers** con tus números: textos con fondo
transparente, en varios estilos tipográficos. **Tocas uno y se copia**; abres tu historia con tu
foto del gym y lo **pegas encima**. Mantener el dedo lo guarda como imagen.

No son tarjetas de pantalla completa sino stickers: la foto la pone el usuario (su cara, el gym,
el espejo), y HABIT pone los números con estilo. Así es como la gente sube historias de verdad, y
la foto del gym de HABIT sale en cada una sin que lo pidamos.

**Por qué importa:**

1. **Es la recompensa del entreno.** Hoy cerrar una sesión termina en un aviso de dos segundos.
2. **Cada historia enseña HABIT.** El sticker lleva el anillo de HABIT y, si se quiere, la
   dirección de HABIT Crew. Por eso es **gratis para todos**: cobrarlo apagaría justo lo que trae
   gente.
3. **Nada nuevo en el servidor.** Todo se dibuja en el teléfono con datos que la app ya tiene.
   Sin migraciones, sin endpoints.

## 2. Lo que aprendimos de AURA (capturas del 31 oct)

- Una sola pantalla: arriba **qué entreno** (selector) y **color**; en medio
  «Toca para copiar · Mantén para guardar»; abajo una **cuadrícula de stickers** sobre fondo
  oscuro, con pestañas (Actividad / Totales / Equipo).
- Los stickers son **solo tipografía**: condensada enorme ("133 CAL"), ancha ("SATURDAY"), serif
  itálica editorial ("Time 24m 15s"), monoespaciada tipo recibo con código de barras, burbujas de
  mensaje, resaltador, notificación. Algunos tienen variantes (puntitos debajo).
- Sin ilustraciones del cuerpo. Lo bonito es la tipografía y el aire.

Lo que **no** copiamos: sus estilos uno por uno ni sus datos (calorías y pulso vienen del reloj;
HABIT no los tiene). Tomamos el formato y lo hacemos con la identidad de HABIT.

## 3. El estilo HABIT

Minimalista y premium, **solo blanco y negro**. Ajustado el 31 oct con Joseph: variedad para cada
gusto, **menos texto** (uno o dos datos por sticker), **números grandes** y también stickers
**divertidos**.

| Familia | Para qué | Ejemplo |
|---|---|---|
| **Space Grotesk** (la de HABIT) | La marca, etiquetas, el anillo | `HABIT` · `Nº 47` |
| **Anton** (condensada) | El número héroe | `4,320 KG` |
| **Archivo Black** (ancha) | El día, la rutina, el grupo muscular | `SÁBADO` · `PIERNA` |
| **Instrument Serif** itálica | Lo editorial: frase del día, la rutina en grande | *Leg 2.* |
| **Space Mono** | Fechas, recibos, letra chica | `31.10 // 11:00` |

**Color: blanco o negro**, nada más (dos círculos arriba de la galería). El blanco para fotos
oscuras, el negro para fotos claras. Sin acento de color: lo que destaca es el tamaño.

**Reglas de cada sticker:** un dato héroe (o dos), lo demás en letra chica o nada. Si un sticker
necesita más de tres renglones, son dos stickers.

**Músculos sin maniquí.** La figura del cuerpo de la app se queda en la app; como sticker se ve
como un muñeco de bloques. Los músculos se dicen con tipografía: el grupo en grande (`PIERNA`) y,
como mucho, los músculos en letra chica.

## 4. Los stickers

Datos que HABIT sí tiene de cada entreno: rutina, día y hora, duración, series, kg movidos,
ejercicios con su mejor serie, músculos (series × `exerciseMuscleSplit()`), récords del día,
**número de entreno** (tu entreno nº 47 en HABIT) y racha de semanas.

La galería se ordena por **familias**; cada sticker puede tener **variantes** (puntitos debajo,
se cambian deslizando): el mismo estilo con otro dato. Así hay muchos sin diseñar cien.

**Pestaña Entreno:**

| Familia | Variantes (cada una un sticker) |
|---|---|
| **Héroe** (Anton, enorme) | `4,320 KG` · `52 MIN` · `18 SERIES` · `Nº 47` |
| **Ancho** (Archivo Black) | `SÁBADO / LEG 2` · `PIERNA` (el grupo muscular del día) · `LEG DAY` |
| **Editorial** (serif) | *Leg 2.* + «52 minutos» · *Sábado, 11:00* |
| **Recibo** (mono) | `31.10 // 11:00` + `ENTRENO Nº 47` · los 3 ejercicios con su mejor serie |
| **Burbuja** | Un mensaje del iPhone en blanco y negro: «Leg 2 listo, 52 min», y debajo **Entrenado** (como el «Entregado» de iMessage) |
| **Resaltador** | «52 min, 4,320 kg» con el marcador detrás |
| **Nota** | Una nota adhesiva: «leg 2 ✓ / sentadilla 100 × 5» |
| **Notificación** | El aviso de HABIT: «Leg 2 completado · 52 min» |
| **Récord** (solo si hubo) | `PR` en sello + `100 KG × 5` · «nuevo récord en sentadilla» en burbuja |

**Pestaña Semana:** `6` enorme + «semanas seguidas» · los 7 días con puntos · `4 ENTRENOS` ·
`16.8 T` esta semana.

**Pestaña Frase:** la frase del día en serif itálica · la firma «Make it a habit.» con el anillo.

Cada sticker tiene además la opción **con fondo** (1080 × 1920) para quien no tiene foto.

## 5. Cómo se usa

1. Cierras el entreno → sale **«Entreno terminado»** con tu resumen y **Compartir**. (Sustituye
   el aviso de hoy; respeta la oferta de guardar cambios en la rutina y el feedback.)
2. **Compartir** abre la galería: arriba el entreno y los dos colores, la indicación
   «Toca para copiar · Mantén para guardar», pestañas Entreno / Semana / Frase y la cuadrícula.
3. **Tocar** copia el sticker (PNG transparente) → en Instagram, al abrir la historia, aparece
   «Agregar sticker» con lo copiado. **Mantener** abre la hoja del teléfono (Guardar imagen,
   Instagram, WhatsApp).
4. También desde: la tarjeta de Hoy cuando ya entrenaste, la frase del día en Inicio, la tira de
   la semana y Progreso.

Regla: **del entreno terminado a la historia en tres toques** (Compartir → sticker → pegar).

## 6. Decisiones

| # | Decisión | Propuesta | Por qué |
|---|---|---|---|
| D1 | ¿Stickers o tarjetas? | **Stickers transparentes**, con opción «con fondo» | Es como se suben historias de verdad, y la foto del usuario hace el resto |
| D2 | ¿Cómo se dibuja? | **Canvas dibujado a mano**, a 3× para que se vea nítido | Una captura de pantalla sale con la interfaz y distinta en cada teléfono |
| D3 | ¿Cómo llega a Instagram? | **Copiar** (portapapeles) al tocar; **compartir/guardar** al mantener | Pegar un sticker es el gesto natural de Instagram. Hay que probarlo en tu iPhone (Fase 0) |
| D4 | ¿Cuerpo dibujado? | **No**: músculos con tipografía | Ver §3 |
| D5 | ¿Datos personales? | **Nunca el correo**; nombre apagado por defecto; pesos encendidos con interruptor | Hay quien no quiere enseñar cuánto carga |
| D6 | ¿Marca? | El anillo de HABIT siempre; `habittraininghub.app/crew` en los que tienen espacio | Que se reconozca sin gritar |
| D7 | ¿Gratis? | **Sí** | Es el canal de crecimiento de Crew |
| D8 | ¿Dónde vive el código? | `habit-share.js`: la parte de datos es pura (Node) y el dibujo recibe un canvas | La regla del repo: lo que se prueba fuera del navegador no crece `app.html` |

## 7. Fases

**Fase 0 — Probar el camino (medio día).** Dos stickers de la frase del día (serif y firma).
Valida en tu iPhone con la app instalada: copiar → pegar en Instagram, mantener → guardar,
fuentes nítidas y fondo transparente. Si copiar no funciona, el plan B es solo guardar/compartir.

**Fase 1 — Entreno terminado + galería.** La pantalla «Entreno terminado» y la galería con las
familias Héroe, Ancho, Editorial, Recibo y Burbuja, los dos colores y el interruptor de pesos.

**Fase 2 — El resto.** Resaltador, Nota, Notificación, Récord, la pestaña Semana, las variantes
de cada familia y la opción «con fondo».

**Fase 3 — Comunidad.** «Publicar en la Comunidad» desde la galería, con el sticker «con fondo»
como foto (bucket `community-images`).

**Fase 4 — App de la tienda (opcional).** Mandar directo a Historias con el esquema de Meta
(`instagram-stories://`), que necesita la app nativa y un Facebook App ID.

## 8. Detalles técnicos

- **Copiar sin perder el toque.** iPhone solo deja copiar o compartir desde un toque. Se usa
  `new ClipboardItem({'image/png': promesa})`: el toque llama a copiar al instante y la imagen se
  termina de dibujar dentro de la promesa. Las vistas previas de la galería ya están dibujadas
  al abrirla, así que la promesa resuelve en milisegundos.
- **Fuentes.** `document.fonts.load()` de las cinco familias antes de dibujar; las cuatro nuevas
  se cargan solo al abrir la galería, no al abrir la app.
- **Transparencia.** PNG con canal alfa; sin fondo, sin sombras. Para que el blanco se lea sobre
  una foto clara está el negro. Las burbujas, notas y notificaciones sí llevan su propia caja
  (blanca con letra negra, o al revés).
- **Sin imágenes externas en el canvas** (avatar, fotos): bloquean la exportación.
- **Versión y caché.** `habit-share.js` al `SHELL` de `sw.js` y a todos los `?v=`.
- **Pruebas.** `scripts/check-share.js`: los datos de cada sticker con sesiones reales (con y sin
  pesos, entreno libre, pirámide, sin series), el número de entreno, el grupo muscular del día y los
  porcentajes de músculos (suman 100) y que el correo nunca aparece.

## 9. Preguntas abiertas

1. ¿El nombre de la persona en algún sticker, o nunca?
2. ¿«Entreno nº 47» cuenta todos los entrenos en HABIT desde siempre (propuesta) o solo los del año?
3. En la app del gym, ¿la dirección dice HABIT Crew o nada?

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
