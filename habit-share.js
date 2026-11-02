// HABIT Share — stickers para historias de Instagram (docs/HISTORIAS_INSTAGRAM.md).
//
// Lo usan las dos apps, HABIT (app.html, congelada) y HABIT Crew (crew.html), y por eso TODO vive
// aquí: el dibujo, la galería (la hoja, su CSS) y compartir. Una app solo carga este archivo y
// marca lo que se puede compartir:
//
//   <section data-hs-share="quote" data-hs-text="…" data-hs-date="2026-10-31"> … </section>
//
// o lo abre ella misma: HabitShare.open({ kind:'workout', data:{…} }). Tres tipos:
//   quote   — la frase del día: { text, ds }
//   workout — un entreno, de la app o de fuera (correr, bici, nadar…):
//             { type, title, ds, durationSec, distanceM, sets, volumeKg, exercises:[{name,best}],
//               elevationM, avgHr, kcal, effort, number }
//   week    — tu semana: { count, durationSec, distanceM, days:[7 × 0/1, lunes primero], weekStart,
//             streak, disciplines:[{type,count,durationSec,distanceM}] }
// Cada sticker es un PNG transparente de un solo color (uno de `PALETTE` o uno libre), en Inter
// (la fuente de HABIT) con su logo original (/icons/logo-original.png). La galería se desliza
// de un estilo a otro y su botón Compartir abre la hoja del teléfono (Instagram, WhatsApp,
// Guardar imagen, Copiar).
//
// Todos firman como HABIT Crew, también los que salen de HABIT: un sticker es lo que ven los
// que todavía no tienen la app, y la que pueden bajar es Crew (abierta a cualquiera). Tres
// estilos hacen de la marca el tema: «Crew» (la palabra enorme), «Carnet» e «Insignia».
//
// La disposición de cada estilo es pura y se prueba en Node (scripts/check-share.js): recibe
// `measure(texto, font)` en lugar de un canvas. Los estilos nuevos se describen como una lista de
// trazos (`ops`: texto, logo, rectángulo, círculo, línea, polígono) que dibuja `drawOps`; así la
// prueba revisa que nada se salga del lienzo sin dibujar nada.
(function (global) {
  'use strict';

  // Los colores del sticker. Blanco y negro primero, los de siempre; luego los de la marca
  // (azul, verde, rojo, lila) y los que más se ven en historias de entreno. También se puede
  // elegir uno libre ('#rrggbb'). Lo que va dentro de una forma rellena (el recibo, el carnet,
  // la cinta) no se elige: es la tinta de `inkFor`.
  const PALETTE = [
    { key: 'blanco', label: 'Blanco', hex: '#ffffff' },
    { key: 'negro', label: 'Negro', hex: '#0b0b0b' },
    { key: 'crema', label: 'Crema', hex: '#f2e8d5' },
    { key: 'azul', label: 'Azul', hex: '#2563eb' },
    { key: 'cielo', label: 'Cielo', hex: '#7cc4ff' },
    { key: 'lima', label: 'Lima', hex: '#d4ff3a' },
    { key: 'verde', label: 'Verde', hex: '#10b981' },
    { key: 'amarillo', label: 'Amarillo', hex: '#ffd60a' },
    { key: 'naranja', label: 'Naranja', hex: '#ff6b2c' },
    { key: 'rojo', label: 'Rojo', hex: '#ef4444' },
    { key: 'rosa', label: 'Rosa', hex: '#ff8fb8' },
    { key: 'lila', label: 'Lila', hex: '#8b5cf6' }
  ];
  const COLORS = Object.fromEntries(PALETTE.map((c) => [c.key, c.hex]));
  const INK = { dark: '#0b0b0b', light: '#ffffff' };
  const WIDTH = 1080;          // ancho de una historia: el sticker sale nítido a cualquier escala
  const PAD = 72;
  const CAP = 0.73;            // altura de mayúsculas y números de Inter, en em
  const INTER = '"Inter", -apple-system, system-ui, sans-serif';
  const LOGO_SRC = '/icons/logo-original.png';
  const LOGO_INK = 0.65;        // el PNG del logo trae margen: la tinta es ~65% de su cuadro
  const SIG = 40;              // la firma (el logotipo chico de abajo): igual en todos los estilos
  const COLOR_KEY = 'habit_sticker_color';
  // Las apps cargan Inter de 300 a 800 y sin itálicas; los stickers usan de 100 a 900 y la
  // itálica. Se pide al abrir la galería, no al cargar: la app no descarga nada de más.
  const FONT_HREF = 'https://fonts.googleapis.com/css2?family=Inter:ital,wght@0,100..900;1,100..900&display=swap';

  const quoteFont = (px) => `600 ${px}px ${INTER}`;
  const wordFont = (px) => `800 ${px}px ${INTER}`;
  const subFont = (px) => `600 ${px}px ${INTER}`;
  const sealFont = (px) => `700 ${px}px ${INTER}`;
  const crewFont = (px) => `600 ${px}px ${INTER}`;
  const CREW_URL = 'habittraininghub.app/crew';
  const F = (weight, px, italic) => `${italic ? 'italic ' : ''}${weight} ${px}px ${INTER}`;

  // ── Color (puro) ─────────────────────────────────────────────────────────

  // Luminancia relativa y contraste, como los define WCAG.
  function luminance(hex) {
    const n = parseInt(String(hex).slice(1), 16);
    const ch = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
  }
  function contrast(a, b) {
    const x = luminance(a), y = luminance(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
  }
  // La tinta sobre un color: blanco si llega a 3:1 (lo que pide WCAG para letra grande, y la
  // de los stickers lo es), si no negro. El blanco gana los empates porque sobre azul, rojo o
  // lila se ve mejor aunque el negro mida un poco más.
  function inkFor(hex) {
    return contrast(hex, INK.light) >= 3 ? INK.light : INK.dark;
  }
  const isHex = (v) => /^#[0-9a-f]{6}$/i.test(String(v || ''));
  const paletteHex = (k) => (Object.prototype.hasOwnProperty.call(COLORS, k) ? COLORS[k] : null);
  // Un color de la paleta (por su clave) o uno libre; cualquier otra cosa, blanco.
  function resolveColor(key) {
    const hex = paletteHex(key) || (isHex(key) ? String(key).toLowerCase() : COLORS.blanco);
    return { fg: hex, ink: inkFor(hex) };
  }

  // ── Disposición (pura) ─────────────────────────────────────────────────

  // Renglones de a lo más `maxWidth`, palabra por palabra.
  function wrapText(text, maxWidth, measure) {
    // Solo los espacios normales parten: un espacio duro (\u00a0) mantiene «52 min» junto.
    const words = String(text || '').trim().split(/[ \t\n]+/).filter(Boolean);
    const lines = [];
    let line = '';
    words.forEach((w) => {
      const next = line ? line + ' ' + w : w;
      if (line && measure(next) > maxWidth) { lines.push(line); line = w; }
      else line = next;
    });
    if (line) lines.push(line);
    return lines;
  }

  // Los mismos renglones, pero parejos: el ancho más chico que no agrega un renglón. Una frase
  // con la última línea de una sola palabra se ve descuidada; esto es el `text-wrap: balance`
  // de CSS hecho a mano.
  function balancedWrap(text, maxWidth, measure) {
    const base = wrapText(text, maxWidth, measure);
    if (base.length < 2) return base;
    let lo = maxWidth * 0.5, hi = maxWidth, best = base;
    for (let i = 0; i < 14; i++) {
      const mid = (lo + hi) / 2;
      const tryLines = wrapText(text, mid, measure);
      if (tryLines.length === base.length && tryLines.every((l) => measure(l) <= mid + 0.5)) {
        best = tryLines; hi = mid;
      } else lo = mid;
    }
    return best;
  }

  // Ancho de un texto con espacio entre letras (el canvas de Safari aún no trae letterSpacing).
  function spacedWidth(text, spacing, measure) {
    const chars = [...String(text || '')];
    return chars.reduce((n, c) => n + measure(c), 0) + spacing * Math.max(0, chars.length - 1);
  }

  // El logotipo de HABIT Crew, como el encabezado de Crew: el logo, HABIT y, sobre la misma
  // línea base, CREW chico y espaciado (allá 9 px junto a 17 px, .32em). Centrado en `cx`. El
  // logo se mide por su tinta (ver `drawLogo`): 1.15 veces la letra, como el de 30 px junto a
  // HABIT de 17 px, y HABIT va centrado en su altura.
  function lockupLayout(cx, top, wordPx, measure) {
    const spacing = Math.round(wordPx * 0.06);
    const logo = Math.round(wordPx * 1.15);
    const gap = Math.round(wordPx * 0.42);
    const wordW = spacedWidth('HABIT', spacing, (c) => measure(c, wordFont(wordPx)));
    const crewPx = Math.round(wordPx * 0.6);
    const crewSpacing = Math.round(crewPx * 0.3);
    const crewGap = Math.round(wordPx * 0.34);
    const crewW = spacedWidth('CREW', crewSpacing, (c) => measure(c, crewFont(crewPx)));
    const width = logo + gap + wordW + crewGap + crewW;
    const x0 = cx - width / 2;
    const baseline = top + logo / 2 + wordPx * CAP / 2;
    return {
      width, height: logo,
      logo: { x: x0, y: top, size: logo },
      word: { text: 'HABIT', font: wordFont(wordPx), spacing, x: x0 + logo + gap, y: baseline },
      crew: { text: 'CREW', font: crewFont(crewPx), spacing: crewSpacing, x: x0 + logo + gap + wordW + crewGap, y: baseline }
    };
  }

  // La frase en renglones parejos, con el tamaño más grande que no pase de `maxLines`. Los
  // renglones siempre se calculan con el tamaño que se queda: si ninguno cabe (una frase
  // larguísima), se usa el más chico con sus propios renglones. `maxLines` puede depender del
  // tamaño (ver `fewLines`).
  function fitLines(text, measure, fontFn, sizes, maxWidth, maxLines) {
    const most = typeof maxLines === 'function' ? maxLines : () => maxLines;
    let size = sizes[0], lines = [];
    for (const px of sizes) {
      size = px;
      lines = balancedWrap(text, maxWidth, (s) => measure(s, fontFn(px)));
      if (lines.length <= most(px)) break;
    }
    return { size, lines };
  }

  // Una frase corta («Hazlo.») sube de tamaño, pero solo mientras quepa en `few` renglones:
  // arriba de `above` px, cinco renglones serían un muro. Con el tamaño de siempre, una frase
  // de una palabra quedaba apenas más grande que la firma.
  const fewLines = (above, few, many) => (px) => (px > above ? few : many);

  // Estilo «Frase»: la frase centrada y en renglones parejos; debajo el logotipo chico. Una
  // frase larga baja de tamaño en lugar de pasar de cinco renglones.
  function quoteLayout(text, measure) {
    const quote = '“' + String(text || '').trim() + '”';
    const inner = WIDTH - PAD * 2;
    const { size, lines } = fitLines(quote, measure, quoteFont, [150, 128, 110, 94, 76, 70, 64, 58, 52, 46, 40], inner, fewLines(76, 3, 5));
    const lineH = Math.round(size * 1.22);
    const top = PAD;
    const textBottom = top + lineH * lines.length;
    const lockup = lockupLayout(WIDTH / 2, textBottom + 64, SIG, measure);
    return {
      kind: 'frase', width: WIDTH,
      height: Math.round(lockup.logo.y + lockup.height + PAD),
      font: quoteFont(size), size, lineH,
      lines: lines.map((t, i) => ({ text: t, x: WIDTH / 2, y: top + lineH * i + size })),
      lockup
    };
  }

  // Estilo «Logotipo»: el logotipo de HABIT en grande y una línea espaciada debajo.
  function signatureLayout(measure, subText) {
    const wordPx = 112;
    const subPx = 42, subSpacing = Math.round(subPx * 0.3);
    const text = String(subText || 'MAKE IT A HABIT').toUpperCase();
    const subW = spacedWidth(text, subSpacing, (c) => measure(c, subFont(subPx)));
    const probe = lockupLayout(0, PAD, wordPx, measure);
    const width = Math.ceil(Math.max(probe.width, subW) + PAD * 2);
    const cx = width / 2;
    const lockup = lockupLayout(cx, PAD, wordPx, measure);
    const subY = lockup.logo.y + lockup.height + 60 + subPx * CAP;
    return {
      kind: 'logotipo', width, height: Math.ceil(subY + PAD * 0.8),
      lockup,
      sub: { text, font: subFont(subPx), spacing: subSpacing, x: cx - subW / 2, y: subY }
    };
  }

  // Las letras de `body` alrededor de un círculo de radio `radius`, en orden y con el espacio
  // repartido para que la vuelta cierre exacta.
  function ringChars(body, radius, font, measure) {
    const circumference = 2 * Math.PI * radius;
    const widths = [...body].map((c) => measure(c, font));
    const total = widths.reduce((a, b) => a + b, 0);
    const spacing = (circumference - total) / widths.length;
    let along = 0;
    const chars = [...body].map((ch, i) => {
      const mid = along + widths[i] / 2;
      along += widths[i] + spacing;
      return { ch, angle: (mid / circumference) * Math.PI * 2 };
    });
    return { spacing, chars };
  }

  // Estilo «Sello»: el texto da la vuelta completa alrededor del logo, como un sello. El
  // espacio entre letras se reparte para que la vuelta cierre exacta; si el texto no cabe, la
  // letra baja de tamaño.
  function sealLayout(text, measure) {
    const size = 1000, cx = size / 2, cy = size / 2;
    const body = String(text || 'MAKE IT A HABIT · ').toUpperCase();
    // La letra crece hasta que el texto llena ~78% de la vuelta (un sello apretado, no letras
    // sueltas); el radio se ajusta para que la letra más grande siga cabiendo en el lienzo.
    const widthAt = (px) => [...body].reduce((n, c) => n + measure(c, sealFont(px)), 0);
    const radiusFor = (px) => size / 2 - px * 0.55 - 24;
    let px = 100;
    for (let i = 0; i < 3; i++) {
      const target = 2 * Math.PI * radiusFor(px) * 0.78;
      px = Math.max(30, Math.min(120, Math.round(px * target / Math.max(1, widthAt(px)))));
    }
    const radius = radiusFor(px);
    const { spacing, chars } = ringChars(body, radius, sealFont(px), measure);
    // El logo llena ~60% del hueco dentro del anillo.
    const hole = radius - px * CAP / 2;
    const logo = Math.round(hole * 2 * 0.6);
    return {
      kind: 'sello', width: size, height: size, cx, cy, radius,
      font: sealFont(px), size: px, spacing, chars,
      logo: { x: cx - logo / 2, y: cy - logo / 2, size: logo }
    };
  }

  // ── Trazos: lo que comparten los estilos nuevos ──────────────────────────

  // Un texto ya colocado: `x` es su borde izquierdo y `w` su ancho, para que la prueba sepa
  // dónde queda sin dibujarlo. color: 'fg' (el del sticker) o 'inv' (el contrario, para lo que
  // va dentro de una forma rellena).
  function textOp(measure, text, font, o) {
    const spacing = o.spacing || 0;
    const w = spacing ? spacedWidth(text, spacing, (c) => measure(c, font)) : measure(text, font);
    let x = o.x;
    if (o.align === 'center') x = o.x - w / 2;
    else if (o.align === 'right') x = o.x - w;
    return { op: 'text', text, font, x, y: o.y, w, px: pxOf(font), spacing, color: o.color || 'fg', alpha: o.alpha, stroke: o.stroke };
  }
  function pxOf(font) { const m = String(font).match(/(\d+(?:\.\d+)?)px/); return m ? Number(m[1]) : 0; }

  // El tamaño más grande (de `maxPx` a `minPx`) con el que `text` cabe en `maxW`.
  function fitPx(measure, text, fontFn, maxW, maxPx, minPx, spacingEm) {
    const widthAt = (px) => {
      const sp = Math.round(px * (spacingEm || 0));
      return sp ? spacedWidth(text, sp, (c) => measure(c, fontFn(px))) : measure(text, fontFn(px));
    };
    let px = maxPx;
    const w0 = widthAt(px);
    if (w0 > maxW) px = Math.max(minPx, Math.floor(maxPx * maxW / w0));
    while (px > minPx && widthAt(px) > maxW) px -= 2;
    return px;
  }

  // Recorta con «…» lo que no cabe en `maxW`.
  function clip(measure, text, font, maxW) {
    let t = String(text || '');
    if (measure(t, font) <= maxW) return t;
    while (t.length > 1 && measure(t + '…', font) > maxW) t = t.slice(0, -1);
    return t.trim() + '…';
  }

  // El tamaño que cabe y, si ni el más chico alcanza (un nombre larguísimo), el texto recortado.
  function fitText(measure, text, fontFn, maxW, maxPx, minPx, spacingEm) {
    const px = fitPx(measure, text, fontFn, maxW, maxPx, minPx, spacingEm);
    const sp = Math.round(px * (spacingEm || 0));
    const width = (t) => (sp ? spacedWidth(t, sp, (c) => measure(c, fontFn(px))) : measure(t, fontFn(px)));
    let t = String(text || '');
    if (width(t) > maxW) {
      while (t.length > 1 && width(t + '…') > maxW) t = t.slice(0, -1);
      t = t.trim() + '…';
    }
    return { px, text: t, spacing: sp };
  }

  // El logotipo como trazos: centrado en `x`, o empezando en `x` con align 'left'.
  function lockupOps(measure, x, top, wordPx, align, color) {
    const probe = lockupLayout(0, top, wordPx, measure);
    const cx = align === 'left' ? x + probe.width / 2 : x;
    const L = lockupLayout(cx, top, wordPx, measure);
    return {
      width: L.width, height: L.height,
      ops: [
        { op: 'logo', x: L.logo.x, y: L.logo.y, size: L.logo.size, color: color || 'fg' },
        textOp(measure, 'HABIT', L.word.font, { x: L.word.x, y: L.word.y, spacing: L.word.spacing, color: color || 'fg' }),
        textOp(measure, 'CREW', L.crew.font, { x: L.crew.x, y: L.crew.y, spacing: L.crew.spacing, color: color || 'fg' })
      ]
    };
  }

  // La firma de abajo: el logotipo a `SIG`, centrado en `x` o empezando en `x` con align 'left'.
  function signOps(measure, x, top, align, color) {
    return lockupOps(measure, x, top, SIG, align || 'center', color);
  }

  // 31.10.26, para el sello.
  function shortDate(ds) {
    const m = String(ds || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
    return m ? `${m[3]}.${m[2]}.${m[1].slice(2)}` : '';
  }
  const DAYS = ['DOMINGO', 'LUNES', 'MARTES', 'MIÉRCOLES', 'JUEVES', 'VIERNES', 'SÁBADO'];
  function dayName(ds) {
    const m = String(ds || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
    return m ? DAYS[new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])).getUTCDay()] : '';
  }

  // ── Los datos de un entreno ──────────────────────────────────────────────

  // Los tipos de actividad. Crew los usa también para su lista y su formulario: una sola fuente
  // para las palabras. `label` es el botón («Correr»), `noun` el nombre de una sin nombre
  // («Carrera.» se lee mejor en un sticker que «Correr.»), `dist` en qué se mide la distancia
  // (nadar va en metros).
  const ACTIVITY_TYPES = {
    run:      { label: 'Correr',  noun: 'Carrera',   verb: 'corriendo', past: 'corridos',  dist: 'km' },
    bike:     { label: 'Bici',    noun: 'Rodada',    verb: 'en bici',   past: 'en bici',   dist: 'km' },
    swim:     { label: 'Nadar',   noun: 'Nado',      verb: 'nadando',   past: 'nadados',   dist: 'm' },
    walk:     { label: 'Caminar', noun: 'Caminata',  verb: 'caminando', past: 'caminados', dist: 'km' },
    strength: { label: 'Fuerza',  noun: 'Fuerza',    verb: 'de entreno' },
    cardio:   { label: 'Cardio',  noun: 'Cardio',    verb: 'de cardio' },
    yoga:     { label: 'Yoga',    noun: 'Yoga',      verb: 'de yoga' },
    sport:    { label: 'Deporte', noun: 'Deporte',   verb: 'jugando' },
    other:    { label: 'Otro',    noun: 'Entreno',   verb: 'de entreno' }
  };

  const pad2 = (n) => String(n).padStart(2, '0');
  function thousands(n) { return String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
  // 10.02 (correr), 42.3 (bici), 1,500 (nadar, en metros).
  function distanceText(type, m) {
    if (!(m > 0)) return '';
    if (type === 'swim') return thousands(m);
    return (m / 1000).toFixed(type === 'bike' ? 1 : 2);
  }
  const distanceUnit = (type) => (type === 'swim' ? 'M' : 'KM');
  // 52:14, 1:12:05.
  function clock(sec) {
    sec = Math.max(0, Math.round(Number(sec) || 0));
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    return h ? `${h}:${pad2(m)}:${pad2(s)}` : `${m}:${pad2(s)}`;
  }
  // 52 MIN, 1 H 12 MIN.
  function minutesText(sec) {
    const min = Math.round((Number(sec) || 0) / 60);
    if (min < 60) return `${min} MIN`;
    const h = Math.floor(min / 60), r = min % 60;
    return r ? `${h} H ${r} MIN` : `${h} H`;
  }
  // 5:12 /KM al correr o caminar, 1:45 /100 M al nadar, 28.4 KM/H en bici.
  function paceText(type, sec, m) {
    if (!(sec > 0) || !(m > 0)) return '';
    if (type === 'run' || type === 'walk') return clock(sec / (m / 1000)) + ' /KM';
    if (type === 'swim') return clock(sec / (m / 100)) + ' /100 M';
    if (type === 'bike') return (m / 1000 / (sec / 3600)).toFixed(1) + ' KM/H';
    return '';
  }

  // Todo lo que los estilos dicen de un entreno, ya en palabras: el dato héroe, las cifras, la
  // frase de la burbuja. Un estilo que no tiene qué mostrar (sin tiempo no hay «Ligero») no sale.
  function workoutFacts(d) {
    d = d || {};
    const type = ACTIVITY_TYPES[d.type] ? d.type : 'strength';
    const T = ACTIVITY_TYPES[type];
    const dur = d.durationSec > 0 ? Math.round(d.durationSec) : 0;
    const dist = T.dist && d.distanceM > 0 ? Math.round(d.distanceM) : 0;
    const sets = d.sets > 0 ? Math.round(d.sets) : 0;
    const vol = d.volumeKg > 0 ? Math.round(d.volumeKg) : 0;
    const title = String(d.title || '').trim().slice(0, 60) || T.noun;
    const exercises = (Array.isArray(d.exercises) ? d.exercises : []).filter((e) => e && e.name).slice(0, 4);
    const distT = distanceText(type, dist), unit = distanceUnit(type);
    const pace = paceText(type, dur, dist);

    let hero;
    if (dist) hero = { value: distT, unit, label: type === 'swim' ? 'METROS' : 'KILÓMETROS' };
    else if (vol) hero = { value: thousands(vol), unit: 'KG', label: 'KG MOVIDOS' };
    else if (sets) hero = { value: String(sets), unit: 'SERIES', label: 'SERIES' };
    else if (dur) hero = { value: String(Math.round(dur / 60)), unit: 'MIN', label: 'MINUTOS' };
    else hero = { value: '1', unit: '', label: 'ENTRENO' };

    const stats = [];
    if (dist) stats.push({ label: 'DISTANCIA', value: distT + ' ' + unit });
    // Con segundos (un reloj, la app) el tiempo va como reloj; en minutos cerrados (registrado a
    // mano), «52 MIN»: «52:00» se ve inventado.
    const durShort = dur % 60 ? clock(dur) : minutesText(dur);
    if (dur) stats.push({ label: 'TIEMPO', value: durShort });
    if (pace) stats.push({ label: type === 'bike' ? 'VELOCIDAD' : 'RITMO', value: pace });
    if (sets) stats.push({ label: 'SERIES', value: String(sets) });
    if (vol) stats.push({ label: 'VOLUMEN', value: thousands(vol) + ' KG' });
    if (d.elevationM > 0) stats.push({ label: 'DESNIVEL', value: thousands(d.elevationM) + ' M' });
    if (d.avgHr > 0) stats.push({ label: 'FC PROMEDIO', value: Math.round(d.avgHr) + ' LPM' });
    if (d.kcal > 0) stats.push({ label: 'KCAL', value: thousands(d.kcal) });
    if (d.effort > 0) stats.push({ label: 'ESFUERZO', value: Math.round(d.effort) + '/10' });

    // Tres cifras para «Datos»: lo que se ve en un reloj al terminar.
    const trio = [];
    if (dist) trio.push({ value: distT, label: type === 'swim' ? 'METROS' : 'KM' });
    if (dur) trio.push({ value: dur % 60 ? clock(dur) : minutesText(dur).toLowerCase(), label: 'TIEMPO' });
    if (pace) trio.push({ value: pace.replace(/ .*$/, ''), label: type === 'bike' ? 'KM/H' : (type === 'swim' ? 'MIN/100 M' : 'MIN/KM') });
    if (sets) trio.push({ value: String(sets), label: 'SERIES' });
    if (vol) trio.push({ value: thousands(vol), label: 'KG' });
    if (exercises.length && trio.length < 3) trio.push({ value: String(d.exerciseCount || exercises.length), label: 'EJERCICIOS' });
    if (d.avgHr > 0) trio.push({ value: String(Math.round(d.avgHr)), label: 'LPM' });
    if (d.effort > 0) trio.push({ value: Math.round(d.effort) + '/10', label: 'ESFUERZO' });

    // «52 min · 18 series · 4,320 kg», «10.02 km · 52:14 · 5:12 /km».
    // Cada cifra va pegada a su unidad con un espacio duro: «52 min» nunca se parte en dos
    // renglones.
    const NB = '\u00a0';
    const parts = [];
    if (dist) parts.push(distT + NB + unit.toLowerCase());
    const durWords = minutesText(dur).toLowerCase().replace(/ /g, NB);
    if (dur) parts.push(dist && dur % 60 ? clock(dur) : durWords);
    if (pace) parts.push(pace.toLowerCase().replace(/ /g, NB));
    if (sets) parts.push(sets + NB + (sets === 1 ? 'serie' : 'series'));
    if (vol) parts.push(thousands(vol) + NB + 'kg');
    const summary = parts.slice(0, 3);

    // La burbuja se lee como un mensaje: «10.02 km corridos. 52:14.» / «Leg 2, listo. 52 min y 18 series.»
    let bubble;
    if (dist) bubble = `${distT}${NB}${unit.toLowerCase()} ${T.past}.` + (dur ? ` ${dur % 60 ? clock(dur) : durWords}.` : '');
    else {
      const rest = parts.slice(0, 2);
      bubble = `${title}, listo.` + (rest.length ? ' ' + rest.join(' y ').replace(/^./, (c) => c.toUpperCase()) + '.' : '');
    }

    // «Ligero»: el tiempo enorme y en qué se fue. Lo registrado a mano llega en minutos
    // cerrados, y «52:00» se ve inventado: va «52» + «minutos corriendo».
    let light = null;
    if (dur) {
      if (dur % 60) light = { value: clock(dur), sub: T.verb };
      else if (dur < 3600) light = { value: String(dur / 60), sub: (dur === 60 ? 'minuto ' : 'minutos ') + T.verb };
      else light = { value: `${Math.floor(dur / 3600)}:${pad2((dur % 3600) / 60)}`, sub: 'horas ' + T.verb };
    }

    const facts = {
      type, typeLabel: T.label, title, ds: d.ds || '', day: dayName(d.ds), date: shortDate(d.ds),
      dur, dist, sets, vol, pace, hero, stats, trio: trio.slice(0, 3), summary, bubble, light,
      exercises, number: d.number > 0 ? Math.round(d.number) : 0
    };
    if (!Array.isArray(d.fields)) return facts;
    const selected = selectedFields('workout', { ...d, fields: d.fields });
    const has = (id) => d.fields.includes(id);
    const metrics = selected.filter((r) => !['title', 'ds', 'exercises'].includes(r.id));
    const main = metrics.find((r) => ['distanceM', 'volumeKg', 'sets'].includes(r.id)) || metrics[0];
    return {
      ...facts,
      title: has('title') ? title : 'MI ENTRENO',
      ds: has('ds') ? facts.ds : '', day: has('ds') ? facts.day : '', date: has('ds') ? facts.date : '',
      dur: has('durationSec') ? dur : 0, dist: has('distanceM') ? dist : 0,
      sets: has('sets') ? sets : 0, vol: has('volumeKg') ? vol : 0,
      pace: has('pace') ? pace : '', number: has('number') ? facts.number : 0,
      exercises: has('exercises') ? exercises : [],
      hero: main ? { value: main.value, unit: main.unit, label: main.unit || main.label.toUpperCase() }
        : { value: '✓', unit: '', label: 'ENTRENADO' },
      stats: metrics.map((r) => ({ label: r.unit || r.label.toUpperCase(), value: r.value })),
      trio: metrics.slice(0, 3).map((r) => ({ value: r.value, label: r.unit || r.label.toUpperCase() })),
      summary: metrics.slice(0, 3).map((r) => [r.value, r.unit].filter(Boolean).join(' ')),
      bubble: [has('title') ? title + '.' : 'Entrenado.', ...metrics.map((r) => [r.value, r.unit].filter(Boolean).join(' ') + '.')].join(' '),
      light: has('durationSec') ? light : null
    };
  }

  // ── Estilos del entreno ──────────────────────────────────────────────────

  // «Héroe»: una cifra enorme, apretada, y qué es.
  function heroLayout(f, measure, kind, label) {
    const maxW = WIDTH - PAD * 2;
    const value = f.hero.value;
    const px = fitPx(measure, value, (p) => F(900, p), maxW, 340, 120, -0.035);
    const ops = [];
    let y = PAD + px * CAP;
    ops.push(textOp(measure, value, F(900, px), { x: WIDTH / 2, y, align: 'center', spacing: Math.round(px * -0.035) }));
    // La coma de «4,320» baja de la línea base: la etiqueta se aparta lo que baja.
    const lab = fitText(measure, label || f.hero.label, (p) => F(700, p), maxW, 50, 30, 0.22);
    y += Math.round(px * 0.14) + (/,/.test(value) ? Math.round(px * 0.1) : 0) + lab.px * CAP;
    ops.push(textOp(measure, lab.text, F(700, lab.px), { x: WIDTH / 2, y, align: 'center', spacing: lab.spacing }));
    y += 76;
    const lk = signOps(measure, WIDTH / 2, y);
    ops.push(...lk.ops);
    return { kind: kind || 'heroe', width: WIDTH, height: Math.round(y + lk.height + PAD * 0.8), ops };
  }

  // «Ligero»: el tiempo en Inter 200, enorme, y en itálica en qué se fue. (El 100 se perdía al
  // achicar el sticker: sus trazos quedaban de un pixel.)
  function lightLayout(f, measure) {
    if (!f.light) return null;
    const maxW = WIDTH - PAD * 2;
    const px = fitPx(measure, f.light.value, (p) => F(200, p), maxW, 330, 140, -0.02);
    const ops = [];
    let y = PAD + px * CAP;
    ops.push(textOp(measure, f.light.value, F(200, px), { x: WIDTH / 2, y, align: 'center', spacing: Math.round(px * -0.02) }));
    const sp = 64;
    y += 56 + sp * 0.72;
    ops.push(textOp(measure, f.light.sub, F(300, sp, true), { x: WIDTH / 2, y, align: 'center' }));
    if (f.day) {
      const d = fitText(measure, [f.day, f.date].filter(Boolean).join(' · '), (p) => F(600, p), maxW, 32, 24, 0.24);
      y += 66 + d.px * CAP;
      ops.push(textOp(measure, d.text, F(600, d.px), { x: WIDTH / 2, y, align: 'center', spacing: d.spacing, alpha: 0.75 }));
    }
    y += 76;
    const lk = signOps(measure, WIDTH / 2, y);
    ops.push(...lk.ops);
    return { kind: 'ligero', width: WIDTH, height: Math.round(y + lk.height + PAD * 0.8), ops };
  }

  // «Espaciado»: el día con mucho aire, la rutina en 900 y una línea de cifras.
  function spacedLayout(f, measure) {
    const maxW = WIDTH - PAD * 2;
    const ops = [];
    let y = PAD;
    if (f.day) {
      const dp = 46;
      y += dp * CAP;
      ops.push(textOp(measure, f.day, F(400, dp), { x: WIDTH / 2, y, align: 'center', spacing: Math.round(dp * 0.5) }));
      y += 48;
    }
    const tt = fitText(measure, f.title.toUpperCase(), (p) => F(900, p), maxW, 200, 64, -0.01);
    // 0.92 y no la altura de mayúsculas: deja lugar al acento de «SÁBADO».
    y += tt.px * 0.92;
    ops.push(textOp(measure, tt.text, F(900, tt.px), { x: WIDTH / 2, y, align: 'center', spacing: tt.spacing }));
    const meta = f.summary.slice(0, 2).join(' · ').toUpperCase();
    if (meta) {
      const m = fitText(measure, meta, (p) => F(600, p), maxW, 40, 26, 0.2);
      y += 52 + m.px * CAP;
      ops.push(textOp(measure, m.text, F(600, m.px), { x: WIDTH / 2, y, align: 'center', spacing: m.spacing, alpha: 0.85 }));
    }
    y += 76;
    const lk = signOps(measure, WIDTH / 2, y);
    ops.push(...lk.ops);
    return { kind: 'espaciado', width: WIDTH, height: Math.round(y + lk.height + PAD * 0.8), ops };
  }

  // «Itálica»: «Leg day.» en 800 itálica, con sus cifras debajo.
  function italicLayout(f, measure) {
    const maxW = WIDTH - PAD * 2;
    const text = /[.!?]$/.test(f.title) ? f.title : f.title + '.';
    let px = fitPx(measure, text, (p) => F(800, p, true), maxW, 210, 110);
    let lines = [text];
    if (measure(text, F(800, px, true)) > maxW) {
      const r = fitLines(text, measure, (p) => F(800, p, true), [130, 116, 104, 92, 80], maxW, 3);
      px = r.size; lines = r.lines;
    }
    const ops = [];
    let y = PAD + px * 0.8;
    lines.forEach((l, i) => {
      ops.push(textOp(measure, l, F(800, px, true), { x: WIDTH / 2, y: y + i * px * 1.02, align: 'center' }));
    });
    y += (lines.length - 1) * px * 1.02;
    const meta = f.summary.join(' · ');
    if (meta) {
      const mp = fitPx(measure, meta, (p) => F(500, p), maxW, 46, 30);
      y += 56 + mp * CAP;
      ops.push(textOp(measure, meta, F(500, mp), { x: WIDTH / 2, y, align: 'center', alpha: 0.9 }));
    }
    y += 76;
    const lk = signOps(measure, WIDTH / 2, y);
    ops.push(...lk.ops);
    return { kind: 'italica', width: WIDTH, height: Math.round(y + lk.height + PAD * 0.8), ops };
  }

  // «Contorno»: la cifra solo en trazo, y su unidad sólida.
  function outlineLayout(f, measure) {
    const maxW = WIDTH - PAD * 2;
    const value = f.hero.value;
    const px = fitPx(measure, value, (p) => F(900, p), maxW, 360, 130);
    const ops = [];
    let y = PAD + px * CAP;
    // Sin espaciado negativo: letra por letra, los trazos se enciman y el contorno se ensucia.
    ops.push(textOp(measure, value, F(900, px), { x: WIDTH / 2, y, align: 'center', stroke: Math.max(3, Math.round(px * 0.016)) }));
    const label = [f.hero.unit, f.day].filter(Boolean).join(' · ');
    if (label) {
      const lp = fitPx(measure, label, (p) => F(800, p), maxW, 48, 28, 0.24);
      // La coma de «4,320» baja de la línea base: con 50 tocaba la unidad.
      y += (/[,.]/.test(value) ? Math.round(px * 0.2) + 34 : 54) + lp * CAP;
      ops.push(textOp(measure, label, F(800, lp), { x: WIDTH / 2, y, align: 'center', spacing: Math.round(lp * 0.24) }));
    }
    y += 76;
    const lk = signOps(measure, WIDTH / 2, y);
    ops.push(...lk.ops);
    return { kind: 'contorno', width: WIDTH, height: Math.round(y + lk.height + PAD * 0.8), ops };
  }

  // «Eco»: el nombre repetido, desvaneciéndose hacia abajo.
  function echoLayout(f, measure) {
    const maxW = WIDTH - PAD * 2;
    const tt = fitText(measure, f.title.toUpperCase(), (p) => F(900, p), maxW, 170, 72, -0.02);
    const px = tt.px;
    const ops = [];
    const alphas = [1, 0.55, 0.3, 0.15, 0.07];
    let y = PAD + px * CAP;
    alphas.forEach((a, i) => {
      ops.push(textOp(measure, tt.text, F(900, px), { x: WIDTH / 2, y: y + i * px * 0.9, align: 'center', spacing: tt.spacing, alpha: a }));
    });
    y += (alphas.length - 1) * px * 0.9;
    const meta = [f.summary.slice(0, 2).join(' · ').toUpperCase(), f.date].filter(Boolean).join(' · ');
    if (meta) {
      const m = fitText(measure, meta, (p) => F(600, p), maxW, 36, 26, 0.2);
      y += 60 + m.px * CAP;
      ops.push(textOp(measure, m.text, F(600, m.px), { x: WIDTH / 2, y, align: 'center', spacing: m.spacing }));
    }
    y += 76;
    const lk = signOps(measure, WIDTH / 2, y);
    ops.push(...lk.ops);
    return { kind: 'eco', width: WIDTH, height: Math.round(y + lk.height + PAD * 0.8), ops };
  }

  // «Datos»: el logotipo y la fecha arriba, el nombre, y tres cifras como en un reloj. Con una
  // sola cifra (yoga: solo minutos) no sale: sería «Héroe» en chico.
  function dataLayout(f, measure, opts) {
    const trio = (opts && opts.trio) || f.trio;
    if (!trio || trio.length < 2) return null;
    const maxW = WIDTH - PAD * 2;
    const ops = [];
    const lk = signOps(measure, PAD, PAD, 'left');
    ops.push(...lk.ops);
    const corner = opts && 'corner' in opts ? opts.corner : [f.day, f.date].filter(Boolean).join(' ');
    if (corner) {
      const c = fitText(measure, corner, (p) => F(600, p), maxW - lk.width - 40, 32, 22, 0.14);
      ops.push(textOp(measure, c.text, F(600, c.px), { x: WIDTH - PAD, y: PAD + lk.height / 2 + c.px * CAP / 2, align: 'right', spacing: c.spacing, alpha: 0.75 }));
    }
    let y = PAD + lk.height + 70;
    const title = (opts && opts.title) || f.title;
    const tt = fitText(measure, title, (p) => F(800, p), maxW, 88, 48, -0.01);
    y += tt.px * CAP;
    ops.push(textOp(measure, tt.text, F(800, tt.px), { x: PAD, y, spacing: tt.spacing }));
    y += 76;
    // Cada columna empieza un poco después de su raya; la cifra más ancha manda el tamaño de
    // las tres, para que se lean como una sola fila.
    const colW = maxW / trio.length, inset = 30, lp = 30;
    const vp = Math.min(...trio.map((t) => fitPx(measure, t.value, (p) => F(800, p), colW - inset * 2, 132, 48, -0.02)));
    const top = y;
    y += vp * CAP;
    const ly = y + 30 + lp * CAP;
    trio.forEach((t, i) => {
      const x = PAD + colW * i + (i ? inset : 0);
      if (i) ops.push({ op: 'line', x1: x - inset, y1: top - 2, x2: x - inset, y2: ly + 4, w: 3, alpha: 0.3 });
      ops.push(textOp(measure, t.value, F(800, vp), { x, y, spacing: Math.round(vp * -0.02) }));
      const l = fitText(measure, t.label, (p) => F(600, p), colW - inset * 2, lp, 22, 0.12);
      ops.push(textOp(measure, l.text, F(600, l.px), { x, y: ly, spacing: l.spacing, alpha: 0.7 }));
    });
    y = ly;
    return { kind: 'datos', width: WIDTH, height: Math.round(y + PAD * 0.9), ops };
  }

  // Dientes de papel: el borde de un recibo recién cortado.
  function zigzag(x0, x1, y, depth, tooth, down) {
    const pts = [];
    const n = Math.max(2, Math.round((x1 - x0) / tooth));
    const step = (x1 - x0) / n;
    for (let i = 0; i <= n; i++) pts.push([x0 + i * step, i % 2 ? y + (down ? depth : -depth) : y]);
    return pts;
  }

  // Un renglón de recibo: etiqueta, puntos guía y la cifra a la derecha.
  function receiptRow(measure, label, value, y, x0, x1, fl, fv) {
    const vw = measure(value, fv);
    const l = clip(measure, label, fl, x1 - x0 - vw - 60);
    const lw = measure(l, fl);
    const ops = [textOp(measure, l, fl, { x: x0, y, color: 'inv' }), textOp(measure, value, fv, { x: x1, y, align: 'right', color: 'inv' })];
    const dot = '.', dw = measure(dot, fl) + 7;
    const from = x0 + lw + 14, to = x1 - vw - 14;
    const n = Math.floor((to - from) / dw);
    if (n > 1) ops.push(textOp(measure, dot.repeat(n), fl, { x: to - n * dw + 7, y, spacing: 7, color: 'inv', alpha: 0.5 }));
    return ops;
  }

  // Un código de barras que siempre es el mismo para el mismo entreno.
  function barcode(seed, x0, y, w, h) {
    let s = 0;
    for (const c of String(seed || 'HABIT')) s = (s * 31 + c.charCodeAt(0)) >>> 0;
    const rnd = () => { s = (s * 1103515245 + 12345) >>> 0; return (s >>> 8) / 16777216; };
    const ops = [];
    let x = x0;
    while (x < x0 + w - 4) {
      const bw = 2 + Math.floor(rnd() * 4) * 2;
      if (x + bw > x0 + w) break;
      ops.push({ op: 'rect', x, y, w: bw, h, color: 'inv' });
      x += bw + 3 + Math.floor(rnd() * 3) * 2;
    }
    return ops;
  }

  // «Recibo»: el entreno como ticket de papel, con su código de barras.
  function receiptLayout(f, measure) {
    const W = 900, px0 = 34, x0 = px0 + 58, x1 = W - px0 - 58;
    const cw = x1 - x0;
    const ops = [];
    const body = [];
    let y = 40 + 66;
    const lk = lockupOps(measure, W / 2, y, 48, 'center', 'inv');
    body.push(...lk.ops);
    y += lk.height + 70;
    const head = f.number ? `ENTRENO Nº ${f.number}` : 'ENTRENO';
    body.push(textOp(measure, head, F(700, 34), { x: W / 2, y, align: 'center', spacing: 8, color: 'inv' }));
    if (f.day) {
      y += 50;
      body.push(textOp(measure, f.day + ' ' + f.date, F(500, 30), { x: W / 2, y, align: 'center', spacing: 5, color: 'inv', alpha: 0.7 }));
    }
    const rule = () => { y += 42; body.push({ op: 'line', x1: x0, y1: y, x2: x1, y2: y, w: 3, dash: [12, 9], color: 'inv', alpha: 0.5 }); y += 26; };
    rule();
    y += 34;
    // El nombre y su tipo; sin nombre propio, el tipo ya es el nombre y no se repite.
    body.push(...(f.title === ACTIVITY_TYPES[f.type].noun
      ? receiptRow(measure, 'ACTIVIDAD', f.title.toUpperCase(), y, x0, x1, F(600, 30), F(800, 36))
      : receiptRow(measure, f.title.toUpperCase(), f.typeLabel.toUpperCase(), y, x0, x1, F(800, 36), F(600, 30))));
    f.exercises.forEach((e) => {
      y += 54;
      body.push(...receiptRow(measure, String(e.name).toUpperCase(), String(e.best || '—').toUpperCase(), y, x0, x1, F(500, 30), F(700, 30)));
    });
    rule();
    f.stats.slice(0, 5).forEach((s, i) => {
      y += i ? 54 : 30;
      body.push(...receiptRow(measure, s.label, s.value, y, x0, x1, F(500, 30), F(700, 30)));
    });
    rule();
    y += 44;
    body.push(...receiptRow(measure, 'TOTAL', (f.hero.value + ' ' + f.hero.unit).trim(), y, x0, x1, F(900, 46), F(900, 46)));
    y += 58;
    body.push(...barcode(f.title + f.ds + f.hero.value, x0 + 30, y, cw - 60, 104));
    y += 104 + 62;
    body.push(textOp(measure, 'MAKE IT A HABIT', F(700, 30), { x: W / 2, y, align: 'center', spacing: 10, color: 'inv' }));
    y += 56;
    const top = 40, bottom = y;
    const pts = [
      ...zigzag(px0, W - px0, top, 12, 26, false),
      ...zigzag(px0, W - px0, bottom, 12, 26, true).reverse()
    ];
    ops.push({ op: 'poly', pts, color: 'fg' }, ...body);
    return { kind: 'recibo', width: W, height: Math.round(bottom + 40), ops };
  }

  // Un globo de mensaje: el rectángulo redondo y su colita curva, como la de iMessage. `side`
  // 'right' es un mensaje que mandaste (el entreno), 'left' uno que te llegó (la frase). La
  // colita sale del borde, baja y se dobla hacia fuera; el canvas de los trazos solo sabe de
  // polígonos, así que sus curvas van en puntos.
  function bubbleOps(x, y, w, h, side) {
    const r = Math.min(52, h / 2);
    const ops = [{ op: 'rect', x, y, w, h, r, color: 'fg' }];
    const s = side === 'right' ? 1 : -1, ex = side === 'right' ? x + w : x, by = y + h;
    const P = (dx, dy) => [ex + s * dx, by + dy];
    const quad = (a, c, b) => Array.from({ length: 10 }, (_, i) => {
      const t = (i + 1) / 10, u = 1 - t;
      return [u * u * a[0] + 2 * u * t * c[0] + t * t * b[0], u * u * a[1] + 2 * u * t * c[1] + t * t * b[1]];
    });
    const from = P(0, -66), tip = P(22, 0), back = P(-48, -6);
    ops.push({ op: 'poly', pts: [P(-60, -66), from, ...quad(from, P(0, -18), tip), ...quad(tip, P(-14, 2), back)], color: 'fg' });
    return ops;
  }

  // «Burbuja»: el entreno como un mensaje de iPhone, en blanco y negro, con su «Entrenado».
  function bubbleLayout(f, measure) {
    const maxText = 780, padX = 52, padY = 40;
    const { size: px, lines } = fitLines(f.bubble, measure, (p) => F(500, p), [64, 58, 52, 48], maxText, 4);
    const lineH = px * 1.22;
    const textW = Math.max(...lines.map((l) => measure(l, F(500, px))));
    const bw = Math.ceil(textW + padX * 2);
    const bh = Math.ceil(padY * 2 + px * 0.78 + (lines.length - 1) * lineH + px * 0.22);
    const W = Math.max(bw + PAD * 2, 640);
    const bx = W - PAD - bw, by = PAD;
    const ops = bubbleOps(bx, by, bw, bh, 'right');
    lines.forEach((l, i) => ops.push(textOp(measure, l, F(500, px), { x: bx + padX, y: by + padY + px * 0.78 + i * lineH, color: 'inv' })));
    let y = by + bh + 34 + 34 * CAP;
    ops.push(textOp(measure, 'Entrenado', F(500, 34), { x: W - PAD - 8, y, align: 'right', alpha: 0.6 }));
    // Debajo, el logotipo alineado a la derecha, como el globo.
    y += 50;
    const lk = signOps(measure, W - PAD - 8 - lockupLayout(0, 0, SIG, measure).width, y, 'left');
    ops.push(...lk.ops);
    return { kind: 'burbuja', width: W, height: Math.round(y + lk.height + PAD * 0.7), ops };
  }

  // «Notificación»: el aviso de HABIT Crew, como si el teléfono te felicitara. El ícono va
  // centrado en la altura del aviso, como en iOS.
  function notifLayout(f, measure) {
    const W = 1040, cx0 = 20, cw = W - 40, pad = 40, icon = 124;
    const tx = cx0 + pad + icon + 32, tr = cx0 + cw - pad;
    const ops = [];
    const top = 20;
    const inner = [];
    let y = top + pad + 32 * CAP;
    inner.push(textOp(measure, 'HABIT CREW', F(600, 32), { x: tx, y, spacing: 3, color: 'inv', alpha: 0.55 }));
    inner.push(textOp(measure, 'ahora', F(400, 32), { x: tr, y, align: 'right', color: 'inv', alpha: 0.45 }));
    y += 62;
    inner.push(textOp(measure, 'Entreno completado', F(700, 46), { x: tx, y, color: 'inv' }));
    const body = [f.title, ...f.summary].join(' · ');
    // Dos renglones como el aviso de iOS; lo que no cabe termina en «…».
    const all = wrapText(body, tr - tx, (s) => measure(s, F(500, 40)));
    const lines = all.length > 2 ? [all[0], clip(measure, all.slice(1).join(' '), F(500, 40), tr - tx)] : all;
    lines.forEach((l) => {
      y += 54;
      inner.push(textOp(measure, l, F(500, 40), { x: tx, y, color: 'inv', alpha: 0.8 }));
    });
    const h = Math.max(y + 12 + pad - top, icon + pad * 2);
    const iy = top + (h - icon) / 2, li = Math.round(icon * 0.6);
    ops.push({ op: 'rect', x: cx0, y: top, w: cw, h, r: 52, color: 'fg' },
      { op: 'rect', x: cx0 + pad, y: iy, w: icon, h: icon, r: 30, color: 'inv' },
      { op: 'logo', x: cx0 + pad + (icon - li) / 2, y: iy + (icon - li) / 2, size: li, color: 'fg' }, ...inner);
    return { kind: 'notif', width: W, height: Math.round(top + h + 20), ops };
  }

  // «Cinta»: cada dato en su tira, como cinta de rotulador; se escalonan para que se vea
  // pegado a mano.
  function tapeLayout(lines, measure, kind, opts) {
    const maxW = WIDTH - PAD * 2 - 120;
    const fontFn = (p) => F(800, p);
    // Todas las tiras van del mismo tamaño; `minPx` es el piso, y lo que no cabe ahí se recorta
    // en lugar de achicar las demás (un nombre larguísimo las dejaba todas diminutas).
    const px = Math.min(...lines.map((l) => fitPx(measure, l, fontFn, maxW, (opts && opts.maxPx) || 76, (opts && opts.minPx) || 40, 0.04)));
    lines = lines.map((l) => fitText(measure, l, () => fontFn(px), maxW, px, px, 0.04).text);
    const padX = Math.round(px * 0.42), bandH = Math.round(px * 1.36), gap = 14;
    const shift = (opts && opts.shift) || [-34, 40, -14, 28, -40, 18, -24];
    const ops = [];
    let y = PAD;
    lines.forEach((l, i) => {
      const sp = Math.round(px * 0.04);
      const tw = spacedWidth(l, sp, (c) => measure(c, fontFn(px)));
      const bw = tw + padX * 2;
      const cx = WIDTH / 2 + (shift[i % shift.length] || 0);
      const bx = Math.max(PAD / 2, Math.min(WIDTH - PAD / 2 - bw, cx - bw / 2));
      ops.push({ op: 'rect', x: bx, y, w: bw, h: bandH, r: 6, color: 'fg' });
      ops.push(textOp(measure, l, fontFn(px), { x: bx + padX, y: y + (bandH + px * CAP) / 2, spacing: sp, color: 'inv' }));
      y += bandH + gap;
    });
    y += 52;
    const lk = signOps(measure, WIDTH / 2, y);
    ops.push(...lk.ops);
    return { kind: kind || 'cinta', width: WIDTH, height: Math.round(y + lk.height + PAD * 0.8), ops };
  }

  function workoutTape(f, measure) {
    const lines = [f.title.toUpperCase(), ...f.summary.slice(0, 2).map((s) => s.toUpperCase()), f.day].filter(Boolean).slice(0, 4);
    return tapeLayout(lines, measure, 'cinta', { minPx: 58 });
  }

  // ── Estilos de la frase del día ─────────────────────────────────────────

  function cleanQuote(text) { return String(text || '').trim(); }

  // «Póster»: la frase en mayúsculas 900, alineada a la izquierda, con una barra y el logotipo.
  function posterLayout(text, measure) {
    const t = cleanQuote(text).toUpperCase();
    const maxW = WIDTH - PAD * 2;
    const { size: px, lines } = fitLines(t, measure, (p) => F(900, p), [200, 170, 146, 124, 110, 98, 88, 78, 68, 60, 56], maxW, fewLines(124, 2, 8));
    // Apretado, pero no tanto que el acento de «DÍAS» toque el renglón de arriba.
    const lineH = px * 1.04;
    const ops = [];
    let y = PAD + px * 0.92;
    lines.forEach((l, i) => ops.push(textOp(measure, l, F(900, px), { x: PAD, y: y + i * lineH })));
    y += (lines.length - 1) * lineH + 60;
    ops.push({ op: 'rect', x: PAD, y, w: 132, h: 16, color: 'fg' });
    y += 16 + 56;
    const lk = signOps(measure, PAD, y, 'left');
    ops.push(...lk.ops);
    return { kind: 'poster', width: WIDTH, height: Math.round(y + lk.height + PAD * 0.8), ops };
  }

  // «Itálica» de la frase: Inter 300 itálica, ligera, centrada.
  function quoteItalicLayout(text, measure) {
    const q = '“' + cleanQuote(text) + '”';
    const maxW = WIDTH - PAD * 2;
    const { size: px, lines } = fitLines(q, measure, (p) => F(300, p, true), [150, 128, 110, 94, 82, 74, 66, 58, 52, 46, 40], maxW, fewLines(82, 3, 5));
    const lineH = px * 1.22;
    const ops = [];
    let y = PAD + px * 0.85;
    lines.forEach((l, i) => ops.push(textOp(measure, l, F(300, px, true), { x: WIDTH / 2, y: y + i * lineH, align: 'center' })));
    y += (lines.length - 1) * lineH + 72;
    const lk = signOps(measure, WIDTH / 2, y);
    ops.push(...lk.ops);
    return { kind: 'italica', width: WIDTH, height: Math.round(y + lk.height + PAD * 0.8), ops };
  }

  // «Cinta» de la frase: cada renglón en su tira.
  function quoteTapeLayout(text, measure) {
    const t = cleanQuote(text).toUpperCase();
    const maxW = WIDTH - PAD * 2 - 140;
    // Se parte con el mismo espaciado con el que se dibuja: si no, un renglón justo se recorta.
    const spaced = (str, font) => spacedWidth(str, Math.round(pxOf(font) * 0.04), (c) => measure(c, font));
    const { size, lines } = fitLines(t, spaced, (p) => F(800, p), [110, 96, 84, 72, 62, 56, 50, 46, 42], maxW, fewLines(62, 3, 7));
    return tapeLayout(lines, measure, 'cinta', { maxPx: size, shift: [-22, 26, -10, 18, -26, 12, -16] });
  }

  // «Mensaje»: la frase como un mensaje que te llegó de HABIT.
  function quoteBubbleLayout(text, measure) {
    const maxText = 780, padX = 50, padY = 40;
    const { size: px, lines } = fitLines(cleanQuote(text), measure, (p) => F(500, p), [76, 66, 58, 52, 48, 44, 40], maxText, fewLines(58, 2, 7));
    const lineH = px * 1.26;
    const textW = Math.max(...lines.map((l) => measure(l, F(500, px))));
    const bw = Math.ceil(textW + padX * 2);
    const bh = Math.ceil(padY * 2 + px * 0.78 + (lines.length - 1) * lineH + px * 0.22);
    const bx = PAD, by = PAD;
    const ops = bubbleOps(bx, by, bw, bh, 'left');
    lines.forEach((l, i) => ops.push(textOp(measure, l, F(500, px), { x: bx + padX, y: by + padY + px * 0.78 + i * lineH, color: 'inv' })));
    const y = by + bh + 48;
    const lk = signOps(measure, PAD + 8, y, 'left');
    ops.push(...lk.ops);
    const W = Math.ceil(Math.max(bx + bw, PAD + 8 + lk.width) + PAD);
    return { kind: 'burbuja', width: W, height: Math.round(y + lk.height + PAD * 0.7), ops };
  }

  // «Comillas»: unas comillas enormes y la frase debajo, a la izquierda.
  function quoteMarksLayout(text, measure) {
    const maxW = WIDTH - PAD * 2;
    const ops = [];
    const qp = 320;
    // Las comillas de Inter ocupan de la altura de mayúsculas (0.73 em) a ~0.45 em sobre la
    // línea base: el renglón siguiente empieza donde terminan, no en su línea base.
    const qy = PAD + qp * CAP;
    ops.push(textOp(measure, '“', F(900, qp), { x: PAD - qp * 0.04, y: qy }));
    let y = qy - qp * 0.42 + 50;
    const { size: px, lines } = fitLines(cleanQuote(text), measure, (p) => F(600, p), [130, 112, 96, 82, 68, 62, 56, 50, 44, 40], maxW, fewLines(68, 3, 6));
    const lineH = px * 1.2;
    y += px * 0.8;
    lines.forEach((l, i) => ops.push(textOp(measure, l, F(600, px), { x: PAD, y: y + i * lineH })));
    y += (lines.length - 1) * lineH + 68;
    const lk = signOps(measure, PAD, y, 'left');
    ops.push(...lk.ops);
    return { kind: 'comillas', width: WIDTH, height: Math.round(y + lk.height + PAD * 0.8), ops };
  }

  // «Mínimo»: la frase en 400, entre dos líneas finas, y HABIT CREW con mucho aire.
  function quoteMinimalLayout(text, ds, measure) {
    const maxW = 820;
    const ops = [];
    let y = PAD;
    ops.push({ op: 'line', x1: WIDTH / 2 - 40, y1: y, x2: WIDTH / 2 + 40, y2: y, w: 4 });
    const { size: px, lines } = fitLines(cleanQuote(text), measure, (p) => F(400, p), [84, 72, 62, 54, 50, 46, 42, 38, 34], maxW, fewLines(54, 3, 7));
    const lineH = px * 1.36;
    y += 64 + px * 0.8;
    lines.forEach((l, i) => ops.push(textOp(measure, l, F(400, px), { x: WIDTH / 2, y: y + i * lineH, align: 'center' })));
    y += (lines.length - 1) * lineH + 60;
    ops.push({ op: 'line', x1: WIDTH / 2 - 40, y1: y, x2: WIDTH / 2 + 40, y2: y, w: 4 });
    const sp = 32;
    y += 64 + sp * CAP;
    const sign = ['HABIT CREW', shortDate(ds)].filter(Boolean).join('  ·  ');
    ops.push(textOp(measure, sign, F(600, sp), { x: WIDTH / 2, y, align: 'center', spacing: Math.round(sp * 0.32) }));
    return { kind: 'minimo', width: WIDTH, height: Math.round(y + PAD * 0.8), ops };
  }

  // ── Estilos de la semana ────────────────────────────────────────────────

  // Deportes como pictogramas vectoriales: mismo color que el sticker, sin emojis.
  const SPORT_MARKS = {
    run: { dots: [[16, 3.5, 2]], paths: [[[6, 8], [11, 6], [15, 10], [20, 8]], [[11, 6], [9, 13], [14, 16], [17, 21]], [[9, 13], [5, 18], [2, 21]]] },
    strength: { dots: [[12, 6, 1.8]], paths: [[[3, 7], [3, 15]], [[1, 9], [1, 13]], [[21, 7], [21, 15]], [[23, 9], [23, 13]], [[3, 10], [21, 10]], [[7, 10], [7, 14], [12, 16], [17, 14], [17, 10]], [[10, 16], [9, 22]], [[14, 16], [15, 22]]] },
    bike: { rings: [[5, 17, 4], [19, 17, 4]], paths: [[[5, 17], [10, 8], [15, 17], [5, 17]], [[10, 8], [17, 8], [19, 17]], [[14, 4], [17, 4]], [[8, 5], [11, 5]]] },
    swim: { dots: [[18, 6, 2]], paths: [[[5, 12], [11, 7], [16, 11]], [[1, 17], [4, 15], [8, 17], [12, 15], [16, 17], [20, 15], [23, 17]], [[1, 22], [4, 20], [8, 22], [12, 20], [16, 22], [20, 20], [23, 22]]] },
    walk: { dots: [[13, 3.5, 2]], paths: [[[12, 8], [10, 15], [7, 22]], [[10, 15], [15, 18], [17, 22]], [[12, 8], [7, 12], [6, 16]], [[12, 8], [16, 12], [20, 13]]] },
    cardio: { paths: [[[1, 12], [6, 12], [9, 5], [14, 20], [18, 12], [23, 12]]] },
    yoga: { dots: [[12, 4, 2]], paths: [[[12, 8], [12, 15]], [[5, 12], [12, 15], [19, 12]], [[12, 15], [3, 21], [21, 21], [12, 15]]] },
    sport: { rings: [[12, 12, 10]], paths: [[[12, 2], [12, 22]], [[2, 12], [22, 12]], [[5, 4], [8, 12], [5, 20]], [[19, 4], [16, 12], [19, 20]]] },
    other: { paths: [[[12, 2], [12, 22]], [[2, 12], [22, 12]], [[5, 5], [19, 19]], [[5, 19], [19, 5]]] }
  };

  function compactWeekTime(seconds) {
    const min = Math.round(seconds / 60), h = Math.floor(min / 60), m = min % 60;
    return h ? h + 'H' + (m ? ' ' + m + 'M' : '') : min + 'M';
  }

  function normalizeDisciplines(d) {
    const groups = new Map();
    for (const r of Array.isArray(d.disciplines) ? d.disciplines : []) {
      if (!r || !ACTIVITY_TYPES[r.type]) continue;
      const safe = (v, max) => Number.isFinite(Number(v)) ? Math.max(0, Math.min(max, Number(v))) : 0;
      const count = Math.round(safe(r.count, 1000));
      if (!count) continue;
      if (!groups.has(r.type)) groups.set(r.type, { type: r.type, count: 0, durationSec: 0, distanceM: 0 });
      const g = groups.get(r.type);
      g.count += count; g.durationSec += safe(r.durationSec, 7 * 86400);
      if (ACTIVITY_TYPES[r.type].dist) g.distanceM += safe(r.distanceM, 10000000);
    }
    const order = ['run', 'strength', 'bike', 'swim', 'walk', 'cardio', 'yoga', 'sport', 'other'];
    return [...groups.values()].sort((a, b) => order.indexOf(a.type) - order.indexOf(b.type)).map((r) => {
      let value;
      if (r.distanceM > 0) value = r.type === 'swim' ? thousands(r.distanceM) + ' M' : (r.distanceM / 1000).toFixed(1) + ' KM';
      else if (r.durationSec > 0) value = compactWeekTime(r.durationSec);
      else value = r.count + (r.count === 1 ? ' ENTRENO' : ' ENTRENOS');
      return { ...r, id: 'discipline:' + r.type, label: ACTIVITY_TYPES[r.type].label, value };
    });
  }

  function selectedDisciplines(d) {
    return normalizeDisciplines(d).filter((r) => !Array.isArray(d.fields) || d.fields.includes(r.id));
  }

  // Texto ancho de display, medido con su expansión real antes de alinear o recortar.
  function displayOp(measure, value, x, y, width, maxPx, color, opts) {
    opts = opts || {};
    const scale = opts.scale || 1.14;
    const t = fitText(measure, value, (p) => F(900, p), width / scale, maxPx, 28);
    const op = textOp(measure, t.text, F(900, t.px), { x, y, color: color || 'fg' });
    op.w *= scale; op.scaleX = scale;
    if (opts.align === 'right') op.x -= op.w;
    if (opts.align === 'center') op.x -= op.w / 2;
    return op;
  }

  // El mismo desglose entra también en los 13 diseños existentes, antes de su firma.
  function disciplineBlock(d, measure, x, top, width, ink) {
    const rows = selectedDisciplines(d), ops = [];
    if (!rows.length) return { ops, height: 0 };
    let y = top;
    ops.push({ op: 'line', x1: x, x2: x + width, y1: y, y2: y, color: ink, alpha: .25 });
    y += 58;
    ops.push(textOp(measure, 'POR DISCIPLINA', F(600, 30), { x, y, spacing: 3, color: ink }));
    for (const r of rows) {
      y += 84;
      ops.push({ op: 'sport', type: r.type, x, y: y - 48, size: 48, color: ink });
      const name = fitText(measure, r.label.toUpperCase(), (p) => F(600, p), 310, 30, 28);
      ops.push(textOp(measure, name.text, F(600, name.px), { x: x + 72, y: y - 4, color: ink }));
      ops.push(displayOp(measure, r.value, x + width, y, width - 400, 68, ink, { scale: 1, align: 'right' }));
      y += 28;
    }
    return { ops, height: y - top + 32 };
  }

  function disciplineWeekLayout(id, d, measure) {
    if (!normalizeDisciplines(d).length) return null;
    const rows = selectedDisciplines(d), fields = selectedFields('week', d), ops = [];
    const x = 88, width = WIDTH - x * 2, right = WIDTH - x;
    let y = 130;
    const label = (t, px, atX, atY, color, align) => {
      const f = fitText(measure, t, (p) => F(600, p), width, px, 28);
      ops.push(textOp(measure, f.text, F(600, f.px), { x: atX, y: atY, color: color || 'fg', align: align || 'left' }));
    };
    const heading = id === 'thisweek' ? 'THIS WEEK' : id === 'mix' ? 'WEEKLY MIX' : id === 'pasaporte' ? 'MI SEMANA / PASAPORTE' : 'EN TODAS MIS FORMAS.';
    ops.push(displayOp(measure, heading, x, y, width, id === 'thisweek' ? 72 : 44, 'fg'));
    y += 68;
    if (id === 'pasaporte') {
      const gap = 24, cellW = (width - gap) / 2, cellH = 320;
      rows.forEach((r, i) => {
        const col = i % 2, cellX = x + col * (cellW + gap), cellY = y + Math.floor(i / 2) * (cellH + gap), cx = cellX + cellW / 2;
        ops.push({ op: 'rect', x: cellX, y: cellY, w: cellW, h: cellH, r: 18, stroke: 2 });
        ops.push({ op: 'sport', type: r.type, x: cx - 46, y: cellY + 32, size: 92 });
        label(r.label.toUpperCase(), 30, cx, cellY + 180, 'fg', 'center');
        ops.push(displayOp(measure, r.value, cx, cellY + 270, cellW - 48, 70, 'fg', { scale: 1, align: 'center' }));
      });
      y += Math.ceil(rows.length / 2) * (cellH + gap);
    } else {
      for (const r of rows) {
        if (id === 'thisweek') {
          // Referencia: dos filas compactas, icono deportivo y métrica dominante.
          ops.push({ op: 'sport', type: r.type, x: x + 10, y: y + 6, size: 110 });
          ops.push(displayOp(measure, r.value, x + 174, y + 102, width - 174, 146, 'fg', { scale: 1.18 }));
          y += 156;
        } else if (id === 'mix') {
          ops.push({ op: 'rect', x, y, w: width, h: 194, r: 38 });
          ops.push({ op: 'sport', type: r.type, x: x + 34, y: y + 44, size: 88, color: 'inv' });
          label(r.label.toUpperCase(), 28, x + 154, y + 55, 'inv');
          ops.push(displayOp(measure, r.value, x + 154, y + 146, width - 190, 100, 'inv'));
          y += 216;
        } else {
          ops.push({ op: 'sport', type: r.type, x, y: y + 2, size: 48 });
          ops.push(displayOp(measure, r.label.toUpperCase() + '.', x + 76, y + 52, width - 76, 88, 'fg'));
          ops.push(displayOp(measure, r.value, x, y + 192, width, 152, 'fg', { scale: 1.05 }));
          y += 238;
          ops.push({ op: 'line', x1: x, x2: right, y1: y, y2: y, alpha: .25 }); y += 42;
        }
      }
    }
    // Los totales son independientes del detalle por deporte y siguen las casillas.
    const totals = fields.filter((r) => ['count', 'durationSec', 'distanceM', 'streak'].includes(r.id));
    if (totals.length) {
      y += 28;
      for (let i = 0; i < totals.length; i += 2) {
        const t = totals.slice(i, i + 2).map((r) => r.value + ' ' + r.unit).join(' · ');
        label(t, 30, x, y); y += 48;
      }
    }
    if (fields.some((r) => r.id === 'days')) {
      const days = weekFacts(d).days, step = width / 7;
      y += 18;
      'LMMJVSD'.split('').forEach((t, i) => {
        const cx = x + step * (i + .5);
        ops.push({ op: 'circle', cx, cy: y + 22, r: 18, stroke: days[i] ? 0 : 2, alpha: days[i] ? 1 : .3 });
        label(t, 28, cx, y + 84, 'fg', 'center');
      });
      y += 120;
    }
    const date = fields.find((r) => r.id === 'weekStart');
    if (date) { y += 22; label(date.value, 30, x, y); y += 24; }
    y += 48;
    const probe = lockupLayout(0, 0, 40, measure);
    const brand = lockupOps(measure, x, y, Math.round(40 * 320 / probe.width), 'left');
    ops.push(...brand.ops);
    return { kind: id, width: WIDTH, height: Math.ceil(y + brand.height + 80), ops };
  }

  // Referencias Aura: composición de datos, sin copiar nombres de marca ni su interfaz.
  // Los textos nuevos nacen en ES/EN; el selector global de HABIT sigue siendo otra fase.
  const WEEK_REFERENCE_COPY = {
    es: { week: 'ESTA SEMANA', total: 'TOTAL', daily: 'POR DÍA', bySport: 'POR DISCIPLINA', distance: 'KILÓMETROS', time: 'MINUTOS',
      types: { run: 'CORRER', strength: 'FUERZA', bike: 'BICI', swim: 'NADAR', walk: 'CAMINAR', cardio: 'CARDIO', yoga: 'YOGA', sport: 'DEPORTE', other: 'ENTRENO' },
      days: ['LUNES', 'MARTES', 'MIÉRCOLES', 'JUEVES', 'VIERNES', 'SÁBADO', 'DOMINGO'],
      short: ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'], more: n => '+ ' + n + ' ENTRENOS MÁS',
      fields: { sessions: 'Detalle de entrenamientos', daily: 'Distribución por día' },
      styles: { diario: 'Diario', notas: 'Notas', barras: 'Barras', tabla: 'Tabla', impacto: 'Impacto' } },
    en: { week: 'THIS WEEK', total: 'TOTAL', daily: 'BY DAY', bySport: 'BY SPORT', distance: 'KILOMETERS', time: 'MINUTES',
      types: { run: 'RUNNING', strength: 'STRENGTH', bike: 'CYCLING', swim: 'SWIMMING', walk: 'WALKING', cardio: 'CARDIO', yoga: 'YOGA', sport: 'SPORT', other: 'WORKOUT' },
      days: ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'],
      short: ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'], more: n => '+ ' + n + ' MORE WORKOUTS',
      fields: { sessions: 'Workout details', daily: 'Daily breakdown' },
      styles: { diario: 'Journal', notas: 'Notes', barras: 'Bars', tabla: 'Table', impacto: 'Impact' } }
  };
  const referenceCopy = d => WEEK_REFERENCE_COPY[/^en\b/i.test(d.lang || d.locale || 'es') ? 'en' : 'es'];
  function referenceTime(seconds, exact) {
    const sec = Math.max(0, Math.round(seconds)), h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
    if (!exact) return sec < 60 ? sec + 'S' : compactWeekTime(sec);
    return [h ? h + 'H' : '', m ? m + 'M' : '', s ? s + 'S' : ''].filter(Boolean).join(' ') || '0M';
  }
  function referenceMetric(type, durationSec, distanceM, exact) {
    if (ACTIVITY_TYPES[type].dist && distanceM > 0) {
      return type === 'swim' ? thousands(distanceM) + ' M' : Number((distanceM / 1000).toFixed(2)) + ' KM';
    }
    return durationSec > 0 ? referenceTime(durationSec, exact) : '—';
  }
  function normalizeWeekSessions(d) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(d.weekStart || '')) return [];
    const start = Date.parse(d.weekStart + 'T00:00:00Z'), end = start + 7 * 864e5;
    if (!Number.isFinite(start)) return [];
    return (Array.isArray(d.sessions) ? d.sessions : []).filter(r => r && ACTIVITY_TYPES[r.type]).map((r) => {
      const date = /^\d{4}-\d{2}-\d{2}$/.test(r.ds || '') ? Date.parse(r.ds + 'T00:00:00Z') : NaN;
      const valid = n => Number.isFinite(Number(n)) ? Math.max(0, Number(n)) : 0;
      return { type: r.type, ds: r.ds, day: Math.round((date - start) / 864e5),
        durationSec: Math.min(86400, valid(r.durationSec)), distanceM: ACTIVITY_TYPES[r.type].dist ? Math.min(1000000, valid(r.distanceM)) : 0,
        date };
    }).filter(r => r.date >= start && r.date < end).sort((a, b) => a.ds.localeCompare(b.ds));
  }
  function weeklyReferenceLayout(id, d, measure) {
    const sports = selectedDisciplines(d), allSessions = normalizeWeekSessions(d), copy = referenceCopy(d);
    if (!normalizeDisciplines(d).length || (id !== 'impacto' && !allSessions.length)) return null;
    const has = field => !Array.isArray(d.fields) || d.fields.includes(field);
    const selected = new Set(sports.map(r => r.type));
    const sessions = allSessions.filter(r => selected.has(r.type));
    const ops = [], x = 88, width = WIDTH - x * 2, right = WIDTH - x;
    let y = 112;
    const text = (value, px, atX, atY, opts) => {
      opts = opts || {};
      const t = fitText(measure, String(value), p => F(opts.weight || 600, p), opts.width || width, px, Math.min(28, px));
      ops.push(textOp(measure, t.text, F(opts.weight || 600, t.px), { x: atX, y: atY, align: opts.align || 'left', alpha: opts.alpha }));
    };
    const rule = atY => ops.push({ op: 'line', x1: x, x2: right, y1: atY, y2: atY, w: 2, alpha: .3 });
    text(copy.week, id === 'notas' ? 68 : 42, x, y, { weight: 800 }); y += 78;
    if (id === 'diario' || id === 'notas') {
      if (has('sessions')) {
        let lastDay = -1;
        const shown = sessions.slice(0, 36);
        for (const r of shown) {
          if (id === 'diario' && has('daily') && r.day !== lastDay) {
            if (lastDay >= 0) y += 30;
            text(copy.days[r.day], 32, x, y, { weight: 700 }); y += 58; lastDay = r.day;
          }
          const value = referenceMetric(r.type, r.durationSec, r.distanceM, true);
          if (id === 'diario') {
            ops.push({ op: 'sport', type: r.type, x, y: y - 42, size: 50 });
            ops.push(displayOp(measure, value, x + 80, y, width - 80, 76));
            y += 94;
          } else {
            // Una lista de notas: marca, cifra y disciplina, con ritmo tipográfico tranquilo.
            text('✓', 38, x, y);
            text(value + '  ' + copy.types[r.type].toLowerCase(), 50, x + 66, y, { width: width - 66, weight: 500 });
            y += 78;
          }
        }
        if (sessions.length > shown.length) { y += 20; text(copy.more(sessions.length - shown.length), 32, x, y); y += 50; }
      }
    } else if (id === 'impacto') {
      for (const r of sports) {
        text(copy.types[r.type], 34, x, y, { weight: 700 }); y += 42;
        const value = referenceMetric(r.type, r.durationSec, r.distanceM);
        const op = displayOp(measure, value.replace(/ /g, ''), WIDTH / 2, 0, width, 650, 'fg', { scale: .35, align: 'center' });
        op.y = y + op.px * .78;
        ops.push(op); y = op.y + op.px * .25 + 76;
      }
    } else if (has('daily')) {
      for (const sport of sports) {
        const points = Array.from({ length: 7 }, (_, day) => {
          const rows = sessions.filter(r => r.type === sport.type && r.day === day);
          return { day, count: rows.length, durationSec: rows.reduce((n, r) => n + r.durationSec, 0), distanceM: rows.reduce((n, r) => n + r.distanceM, 0) };
        });
        const totalSec = points.reduce((n, r) => n + r.durationSec, 0), totalM = points.reduce((n, r) => n + r.distanceM, 0);
        const distance = totalM > 0 && ACTIVITY_TYPES[sport.type].dist;
        text(copy.types[sport.type], 34, x, y, { weight: 700 });
        ops.push(displayOp(measure, referenceMetric(sport.type, totalSec, totalM), right, y + 6, width - 320, 64, 'fg', { align: 'right' }));
        y += 56;
        if (id === 'tabla') {
          rule(y); y += 56;
          for (const point of points.filter(r => r.count)) {
            text(copy.days[point.day], 30, x, y, { width: 390 });
            const value = distance ? (point.distanceM > 0 ? referenceMetric(sport.type, 0, point.distanceM) : '—') : referenceMetric(sport.type, point.durationSec, 0, true);
            ops.push(displayOp(measure, value, right, y + 10, width - 430, 72, 'fg', { align: 'right' }));
            y += 58; rule(y); y += 54;
          }
          text(copy.total, 30, x, y, { weight: 700 });
          ops.push(displayOp(measure, referenceMetric(sport.type, totalSec, totalM), right, y + 10, width - 300, 78, 'fg', { align: 'right' }));
          y += 112;
        } else {
          const values = points.map(r => distance ? r.distanceM / 1000 : r.durationSec / 60);
          const max = Math.max(...values, 1), baseline = y + 280, step = width / 7;
          text(distance ? copy.distance : copy.time, 26, x, y, { alpha: .65 });
          for (let i = 0; i < 7; i++) {
            const cx = x + step * (i + .5), height = values[i] / max * 214;
            if (height > 0) ops.push({ op: 'rect', x: cx - 26, y: baseline - height, w: 52, h: height, r: 4, alpha: i === 6 ? 1 : .65,
              sourceType: sport.type, sourceDay: i, metricValue: values[i], metric: distance ? 'km' : 'min' });
            const incomplete = sessions.some(r => r.type === sport.type && r.day === i && (distance ? !r.distanceM : !r.durationSec));
            const value = values[i] ? String(Number(values[i].toFixed(1))) + (incomplete ? '+' : '') : incomplete ? '—' : '0';
            text(value, 28, cx, baseline + 46, { align: 'center', width: step - 10, weight: 700 });
            text(copy.short[i], 25, cx, baseline + 90, { align: 'center', width: step - 8, alpha: .7 });
          }
          rule(baseline + 4); y = baseline + 160;
        }
      }
    }
    y += 46;
    const probe = lockupLayout(0, 0, 40, measure);
    const brand = lockupOps(measure, x, y, Math.round(40 * 320 / probe.width), 'left');
    ops.push(...brand.ops);
    return { kind: id, width: WIDTH, height: Math.ceil(y + brand.height + 80), ops };
  }

  function weekFacts(d) {
    d = d || {};
    const count = Math.max(0, Math.round(d.count || 0));
    const days = Array.from({ length: 7 }, (_, i) => !!(d.days && d.days[i]));
    const dur = d.durationSec > 0 ? Math.round(d.durationSec) : 0;
    const dist = d.distanceM > 0 ? Math.round(d.distanceM) : 0;
    const parts = [];
    if (dur) parts.push(minutesText(dur));
    if (dist) parts.push((dist / 1000).toFixed(1) + ' KM');
    const m = String(d.weekStart || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
    let range = '';
    if (m) {
      const a = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])), b = new Date(a.getTime() + 6 * 86400000);
      const f = (x) => pad2(x.getUTCDate()) + '.' + pad2(x.getUTCMonth() + 1);
      range = f(a) + ' – ' + f(b);
    }
    return { count, days, dur, dist, meta: parts.join(' · '), range, streak: Math.max(0, Math.round(d.streak || 0)) };
  }

  // «Semana»: cuántas veces, y los siete días como puntos.
  function weekDotsLayout(w, measure) {
    const ops = [];
    const kp = 36;
    let y = PAD + kp * CAP;
    ops.push(textOp(measure, 'ESTA SEMANA', F(700, kp), { x: WIDTH / 2, y, align: 'center', spacing: Math.round(kp * 0.3) }));
    const px = 300;
    y += 52 + px * CAP;
    ops.push(textOp(measure, String(w.count), F(900, px), { x: WIDTH / 2, y, align: 'center', spacing: -10 }));
    const ep = 46;
    y += 56 + ep * CAP;
    ops.push(textOp(measure, w.count === 1 ? 'ENTRENO' : 'ENTRENOS', F(800, ep), { x: WIDTH / 2, y, align: 'center', spacing: Math.round(ep * 0.26) }));
    const r = 34, step = 112, x0 = WIDTH / 2 - step * 3, lp = 32;
    y += 84 + r;
    'LMMJVSD'.split('').forEach((letter, i) => {
      const cx = x0 + step * i;
      ops.push(w.days[i]
        ? { op: 'circle', cx, cy: y, r, color: 'fg' }
        : { op: 'circle', cx, cy: y, r: r - 2, stroke: 4, color: 'fg', alpha: 0.45 });
      ops.push(textOp(measure, letter, F(700, lp), { x: cx, y: y + r + 30 + lp * CAP, align: 'center', alpha: w.days[i] ? 0.9 : 0.5 }));
    });
    y += r + 30 + lp * CAP;
    if (w.meta) {
      const m = fitText(measure, w.meta, (p) => F(600, p), WIDTH - PAD * 2, 38, 26, 0.14);
      y += 64 + m.px * CAP;
      ops.push(textOp(measure, m.text, F(600, m.px), { x: WIDTH / 2, y, align: 'center', spacing: m.spacing, alpha: 0.85 }));
    }
    y += 76;
    const lk = signOps(measure, WIDTH / 2, y);
    ops.push(...lk.ops);
    return { kind: 'semana', width: WIDTH, height: Math.round(y + lk.height + PAD * 0.8), ops };
  }

  // «Racha»: el número de semanas seguidas, enorme, con sus palabras apiladas al lado.
  function streakLayout(w, measure) {
    if (w.streak < 2) return null;
    const ops = [];
    const value = String(w.streak);
    const px = fitPx(measure, value, (p) => F(900, p), 520, 380, 200, -0.04);
    const nw = spacedWidth(value, Math.round(px * -0.04), (c) => measure(c, F(900, px)));
    const base = PAD + px * CAP;
    ops.push(textOp(measure, value, F(900, px), { x: PAD, y: base, spacing: Math.round(px * -0.04) }));
    const words = ['SEMANAS', 'SEGUIDAS', 'ENTRENANDO'];
    const wp = Math.round(px * CAP / 3.6);
    const wx = PAD + nw + 44;
    const step = (px * CAP - wp * CAP) / (words.length - 1);
    words.forEach((t, i) => ops.push(textOp(measure, t, F(800, wp), { x: wx, y: base - px * CAP + wp * CAP + i * step, spacing: Math.round(wp * 0.08) })));
    const wordsW = Math.max(...words.map((t) => spacedWidth(t, Math.round(wp * 0.08), (c) => measure(c, F(800, wp)))));
    const y = base + 76;
    const lk = signOps(measure, PAD, y, 'left');
    ops.push(...lk.ops);
    return { kind: 'racha', width: Math.ceil(Math.max(wx + wordsW, PAD + lk.width) + PAD), height: Math.round(y + lk.height + PAD * 0.8), ops };
  }

  // ── Estilos de la marca: HABIT Crew ─────────────────────────────────────

  // «Crew»: la marca apilada, como en una playera. El logo, HABIT espaciado al ancho exacto de
  // CREW y CREW enorme; debajo, el dato (`rows`, un renglón cada uno) o la frase (`para`).
  // HABIT toma el tamaño con el que ese espacio queda en ~0.5em: con uno fijo y chico, las
  // letras quedaban sueltas de lado a lado.
  function crewStackLayout(measure, o) {
    const maxW = WIDTH - PAD * 2;
    const ops = [];
    let y = PAD;
    const cp = fitPx(measure, 'CREW', (p) => F(900, p), maxW - 60, 300, 160, -0.03);
    const csp = Math.round(cp * -0.03);
    const crewW = spacedWidth('CREW', csp, (c) => measure(c, F(900, cp)));
    const habitAt = (p) => [...'HABIT'].reduce((n, c) => n + measure(c, F(800, p)), 0);
    const hp = Math.round(crewW / (habitAt(100) / 100 + 4 * 0.5));
    const logo = Math.round(hp * 1.15);
    ops.push({ op: 'logo', x: WIDTH / 2 - logo / 2, y, size: logo });
    y += logo + Math.round(hp * 0.5) + hp * CAP;
    ops.push(textOp(measure, 'HABIT', F(800, hp), { x: WIDTH / 2, y, align: 'center', spacing: (crewW - habitAt(hp)) / 4 }));
    y += Math.round(cp * 0.13) + cp * CAP;
    ops.push(textOp(measure, 'CREW', F(900, cp), { x: WIDTH / 2, y, align: 'center', spacing: csp }));
    y += 20;
    if (o.para) {
      const { size: px, lines } = fitLines(o.para, measure, (p) => F(500, p), [84, 72, 62, 56, 50, 46, 42, 38], maxW, fewLines(56, 2, 5));
      const lh = px * 1.26;
      y += 60 + px * 0.8;
      lines.forEach((l, i) => ops.push(textOp(measure, l, F(500, px), { x: WIDTH / 2, y: y + i * lh, align: 'center' })));
      y += (lines.length - 1) * lh;
    }
    (o.rows || []).filter((r) => r && r.text).forEach((r, i) => {
      const t = fitText(measure, r.text, (p) => F(r.weight, p), maxW, r.max, r.min, r.spacing);
      y += (i ? 36 : 64) + t.px * CAP;
      ops.push(textOp(measure, t.text, F(r.weight, t.px), { x: WIDTH / 2, y, align: 'center', spacing: t.spacing, alpha: r.alpha }));
    });
    return { kind: 'crew', width: WIDTH, height: Math.round(y + PAD * 0.9), ops };
  }

  // «Carnet»: la credencial de la crew. Una tarjeta rellena (proporción de tarjeta de banco) con
  // el logotipo, el dato grande —o la frase— y el logo enorme y tenue saliendo por su borde,
  // como el holograma de una tarjeta; abajo, el día y dónde se baja la app.
  // c: { kicker, value, unit, line, para, foot }.
  function carnetLayout(measure, c) {
    const x = 40, w = WIDTH - 80, pad = 68, top = 40;
    const ix = x + pad, ir = x + w - pad, iw = ir - ix;
    const body = [];
    let y = top + 64;
    const lk = lockupOps(measure, ix, y, SIG, 'left', 'inv');
    body.push(...lk.ops);
    if (c.kicker) {
      const k = fitText(measure, c.kicker, (p) => F(700, p), iw - lk.width - 40, 30, 20, 0.2);
      body.push(textOp(measure, k.text, F(700, k.px), { x: ir, y: y + lk.height / 2 + k.px * CAP / 2, align: 'right', spacing: k.spacing, color: 'inv', alpha: 0.6 }));
    }
    y += lk.height + 90;
    if (c.para) {
      const { size: px, lines } = fitLines(c.para, measure, (p) => F(600, p), [96, 84, 72, 60, 54, 48, 44, 40, 36], iw, fewLines(60, 2, 5));
      const lh = px * 1.2;
      y += px * CAP;
      lines.forEach((l, i) => body.push(textOp(measure, l, F(600, px), { x: ix, y: y + i * lh, color: 'inv' })));
      y += (lines.length - 1) * lh;
    } else {
      const up = 48, usp = Math.round(up * 0.08);
      const unitW = c.unit ? spacedWidth(c.unit, usp, (ch) => measure(ch, F(800, up))) + 26 : 0;
      const vp = fitPx(measure, c.value, (p) => F(900, p), iw - unitW, 210, 80, -0.03);
      const vsp = Math.round(vp * -0.03);
      y += vp * CAP;
      body.push(textOp(measure, c.value, F(900, vp), { x: ix, y, spacing: vsp, color: 'inv' }));
      if (c.unit) {
        const vw = spacedWidth(c.value, vsp, (ch) => measure(ch, F(900, vp)));
        body.push(textOp(measure, c.unit, F(800, up), { x: ix + vw + 26, y, spacing: usp, color: 'inv' }));
      }
      if (c.line) {
        const t = fitText(measure, c.line, (p) => F(600, p), iw, 36, 30, 0.1);
        y += 60 + t.px * CAP;
        body.push(textOp(measure, t.text, F(600, t.px), { x: ix, y, spacing: t.spacing, color: 'inv', alpha: 0.75 }));
      }
    }
    // Abajo, pegado al borde: la tarjeta guarda su proporción aunque el contenido sea corto.
    const fp = 30;
    const bottom = Math.max(top + Math.round(w / 1.586), y + 100 + fp * CAP + 60);
    const fy = bottom - 60;
    const urlW = measure(CREW_URL, F(500, fp));
    body.push(textOp(measure, CREW_URL, F(500, fp), { x: ir, y: fy, align: 'right', color: 'inv', alpha: 0.6 }));
    if (c.foot) {
      const f = fitText(measure, c.foot, (p) => F(700, p), iw - urlW - 40, fp, 22, 0.16);
      body.push(textOp(measure, f.text, F(700, f.px), { x: ix, y: fy, spacing: f.spacing, color: 'inv' }));
    }
    const h = bottom - top, wm = Math.round(h * 0.94);
    const card = { x, y: top, w, h, r: 52 };
    const ops = [
      { op: 'rect', ...card },
      { op: 'logo', x: x + w - wm * 0.6, y: top + (h - wm) / 2, size: wm, color: 'inv', alpha: 0.07, clip: card },
      ...body
    ];
    return { kind: 'carnet', width: WIDTH, height: bottom + top, ops };
  }

  // «Insignia»: un escudo redondo. Dos anillos, HABIT CREW y el dato dando la vuelta entre ellos,
  // y dentro el logo con la cifra. La letra del anillo se ajusta para llenar ~80% de la vuelta.
  function insigniaLayout(measure, ring, value, unit) {
    const size = 1000, cx = size / 2, cy = size / 2, outer = 474;
    const body = String(ring).toUpperCase();
    const widthAt = (px) => [...body].reduce((n, ch) => n + measure(ch, sealFont(px)), 0);
    const radiusFor = (px) => outer - 28 - px * 0.5;
    let px = 52;
    for (let i = 0; i < 3; i++) {
      px = Math.max(30, Math.min(60, Math.round(px * (2 * Math.PI * radiusFor(px) * 0.8) / Math.max(1, widthAt(px)))));
    }
    const radius = radiusFor(px);
    const inner = radius - px * 0.5 - 28;
    const ringed = ringChars(body, radius, sealFont(px), measure);
    const spacing = ringed.spacing;
    // Que la marca (lo primero del anillo, hasta el primer «·») quede centrada arriba.
    const head = Math.max(1, body.indexOf(' · ') > 0 ? body.indexOf(' · ') : 1);
    const turn = (ringed.chars[0].angle + ringed.chars[head - 1].angle) / 2;
    const chars = ringed.chars.map((ch) => ({ ch: ch.ch, angle: ch.angle - turn }));
    const ops = [
      { op: 'circle', cx, cy, r: outer, stroke: 10 },
      { op: 'circle', cx, cy, r: inner, stroke: 4 },
      { op: 'arc', cx, cy, radius, font: sealFont(px), px, spacing, chars }
    ];
    const maxW = inner * 2 * 0.72;
    const vp = fitPx(measure, value, (p) => F(900, p), maxW, 240, 90, -0.03);
    const logo = Math.round(inner * 0.3);
    const u = unit ? fitText(measure, unit, (p) => F(700, p), maxW * 0.9, 40, 24, 0.24) : null;
    // La coma de «4,320» baja de la línea base: la unidad se aparta lo que baja.
    const gapU = 44 + (/,/.test(value) ? Math.round(vp * 0.08) : 0);
    const blockH = logo + 44 + vp * CAP + (u ? gapU + u.px * CAP : 0);
    let y = cy - blockH / 2;
    ops.push({ op: 'logo', x: cx - logo / 2, y, size: logo });
    y += logo + 44 + vp * CAP;
    ops.push(textOp(measure, value, F(900, vp), { x: cx, y, align: 'center', spacing: Math.round(vp * -0.03) }));
    if (u) {
      y += gapU + u.px * CAP;
      ops.push(textOp(measure, u.text, F(700, u.px), { x: cx, y, align: 'center', spacing: u.spacing }));
    }
    return { kind: 'insignia', width: size, height: size, ops };
  }

  // Lo que dice cada estilo de la marca, por tipo. En un entreno, la línea de abajo lleva lo que
  // la cifra grande no dijo ya («10.02 KM» arriba, «52:14 · 5:13 /KM» abajo).
  function workoutRest(f) {
    const hero = (f.hero.value + ' ' + f.hero.unit).trim();
    return f.summary.map((s) => s.replace(/ /g, ' ').toUpperCase()).filter((s) => s !== hero);
  }
  function workoutRing(f) {
    const title = f.title.length > 22 ? f.title.slice(0, 21).trim() + '…' : f.title;
    return ['HABIT CREW', title, f.number ? `ENTRENO Nº ${f.number}` : '', [f.day, f.date].filter(Boolean).join(' ')]
      .filter(Boolean).join(' · ') + ' · ';
  }
  const entrenos = (n) => (n === 1 ? 'ENTRENO' : 'ENTRENOS');

  // Los estilos de cada tipo, en el orden en que salen en la galería. `layout` recibe los datos
  // y `measure`; devuelve null cuando a ese entreno le falta lo que el estilo enseña.
  const KINDS = {
    quote: {
      title: 'Frase del día',
      styles: [
        { id: 'frase', label: 'Frase', layout: (d, m) => quoteLayout(d.text, m) },
        { id: 'crew', label: 'Crew', layout: (d, m) => crewStackLayout(m, { para: '“' + cleanQuote(d.text) + '”' }) },
        {
          id: 'carnet', label: 'Carnet', layout: (d, m) => carnetLayout(m, {
            kicker: 'FRASE DEL DÍA', para: '“' + cleanQuote(d.text) + '”',
            foot: [dayName(d.ds), shortDate(d.ds)].filter(Boolean).join(' ') || 'MAKE IT A HABIT'
          })
        },
        { id: 'poster', label: 'Póster', layout: (d, m) => posterLayout(d.text, m) },
        { id: 'italica', label: 'Itálica', layout: (d, m) => quoteItalicLayout(d.text, m) },
        { id: 'cinta', label: 'Cinta', layout: (d, m) => quoteTapeLayout(d.text, m) },
        { id: 'burbuja', label: 'Mensaje', layout: (d, m) => quoteBubbleLayout(d.text, m) },
        { id: 'comillas', label: 'Comillas', layout: (d, m) => quoteMarksLayout(d.text, m) },
        { id: 'minimo', label: 'Mínimo', layout: (d, m) => quoteMinimalLayout(d.text, d.ds, m) },
        { id: 'logotipo', label: 'Logotipo', layout: (d, m) => signatureLayout(m, 'MAKE IT A HABIT') },
        { id: 'sello', label: 'Sello', layout: (d, m) => sealLayout('HABIT CREW · MAKE IT A HABIT · ' + (shortDate(d.ds) ? shortDate(d.ds) + ' · ' : ''), m) }
      ]
    },
    workout: {
      title: 'Tu entreno',
      styles: [
        { id: 'heroe', label: 'Héroe', layout: (d, m) => heroLayout(workoutFacts(d), m) },
        {
          id: 'crew', label: 'Crew', layout: (d, m) => {
            const f = workoutFacts(d);
            return crewStackLayout(m, { rows: [
              { text: (f.hero.value + ' ' + f.hero.unit).trim(), weight: 800, max: 120, min: 56, spacing: 0 },
              { text: [f.title.toUpperCase(), f.day].filter(Boolean).join(' · '), weight: 600, max: 40, min: 30, spacing: 0.2, alpha: 0.8 }
            ] });
          }
        },
        {
          id: 'carnet', label: 'Carnet', layout: (d, m) => {
            const f = workoutFacts(d);
            return carnetLayout(m, {
              kicker: f.day, value: f.hero.value, unit: f.hero.unit,
              line: [f.title.toUpperCase(), ...workoutRest(f).slice(0, 2)].join(' · '),
              foot: [f.number ? `ENTRENO Nº ${f.number}` : '', f.date].filter(Boolean).join(' · ')
            });
          }
        },
        {
          id: 'insignia', label: 'Insignia', layout: (d, m) => {
            const f = workoutFacts(d);
            return insigniaLayout(m, workoutRing(f), f.hero.value, f.hero.label);
          }
        },
        { id: 'datos', label: 'Datos', layout: (d, m) => dataLayout(workoutFacts(d), m) },
        { id: 'recibo', label: 'Recibo', layout: (d, m) => receiptLayout(workoutFacts(d), m) },
        { id: 'ligero', label: 'Ligero', layout: (d, m) => lightLayout(workoutFacts(d), m) },
        { id: 'italica', label: 'Itálica', layout: (d, m) => italicLayout(workoutFacts(d), m) },
        { id: 'contorno', label: 'Contorno', layout: (d, m) => outlineLayout(workoutFacts(d), m) },
        { id: 'notif', label: 'Notificación', layout: (d, m) => notifLayout(workoutFacts(d), m) },
        { id: 'burbuja', label: 'Mensaje', layout: (d, m) => bubbleLayout(workoutFacts(d), m) },
        { id: 'cinta', label: 'Cinta', layout: (d, m) => workoutTape(workoutFacts(d), m) },
        { id: 'espaciado', label: 'Espaciado', layout: (d, m) => spacedLayout(workoutFacts(d), m) },
        { id: 'eco', label: 'Eco', layout: (d, m) => echoLayout(workoutFacts(d), m) },
        {
          id: 'sello', label: 'Sello', layout: (d, m) => {
            const f = workoutFacts(d);
            return sealLayout(`${f.hero.value} ${f.hero.unit} · ${f.date ? f.date + ' · ' : ''}HABIT CREW · `.replace(/ {2,}/g, ' '), m);
          }
        },
        {
          id: 'logotipo', label: 'Logotipo', layout: (d, m) => {
            const f = workoutFacts(d);
            return signatureLayout(m, f.number ? `ENTRENO Nº ${f.number}` : `${f.hero.value} ${f.hero.unit} · ${f.day || 'MAKE IT A HABIT'}`);
          }
        }
      ]
    },
    week: {
      title: 'Tu semana',
      styles: [
        { id: 'semana', label: 'Semana', layout: (d, m) => weekDotsLayout(weekFacts(d), m) },
        {
          id: 'crew', label: 'Crew', layout: (d, m) => {
            const w = weekFacts(d);
            return crewStackLayout(m, { rows: [
              { text: `${w.count} ${entrenos(w.count)}`, weight: 800, max: 120, min: 56, spacing: 0 },
              { text: w.meta || 'ESTA SEMANA', weight: 600, max: 40, min: 30, spacing: 0.2, alpha: 0.8 }
            ] });
          }
        },
        {
          id: 'carnet', label: 'Carnet', layout: (d, m) => {
            const w = weekFacts(d);
            return carnetLayout(m, {
              // La racha arriba, donde cabe entera; abajo junto a la dirección quedaba diminuta.
              kicker: w.streak >= 2 ? `${w.streak} SEMANAS SEGUIDAS` : 'MI SEMANA',
              value: String(w.count), unit: entrenos(w.count), line: w.meta, foot: w.range || 'MI SEMANA'
            });
          }
        },
        {
          id: 'insignia', label: 'Insignia', layout: (d, m) => {
            const w = weekFacts(d);
            return insigniaLayout(m, ['HABIT CREW', 'ESTA SEMANA', w.range].filter(Boolean).join(' · ') + ' · ', String(w.count), entrenos(w.count));
          }
        },
        {
          id: 'heroe', label: 'Héroe', layout: (d, m) => {
            const w = weekFacts(d);
            return heroLayout({ hero: { value: String(w.count), label: '' } }, m, 'heroe', w.count === 1 ? 'ENTRENO ESTA SEMANA' : 'ENTRENOS ESTA SEMANA');
          }
        },
        { id: 'racha', label: 'Racha', layout: (d, m) => streakLayout(weekFacts(d), m) },
        {
          id: 'datos', label: 'Datos', layout: (d, m) => {
            const w = weekFacts(d);
            const trio = [{ value: String(w.count), label: w.count === 1 ? 'ENTRENO' : 'ENTRENOS' }];
            if (w.dur) trio.push({ value: clock(w.dur).replace(/:\d\d$/, '') + (w.dur >= 3600 ? '' : "'"), label: w.dur >= 3600 ? 'HORAS' : 'MINUTOS' });
            if (w.dist) trio.push({ value: (w.dist / 1000).toFixed(1), label: 'KM' });
            return dataLayout({}, m, { trio, title: 'Mi semana', corner: w.range });
          }
        }
      ]
    }
  };

  // Datos explícitos: ningún diseño puede recuperar un campo desmarcado.
  function stickerFields(kind, d) {
    const rows = [];
    const add = (id, label, value, unit) => { if (value !== '' && value != null) rows.push({ id, label, value: String(value), unit: unit || '' }); };
    if (kind === 'week') {
      const w = weekFacts(d);
      add('count', 'Entrenamientos', w.count, 'ENTRENOS');
      if (w.dur) add('durationSec', 'Tiempo total', minutesText(w.dur), 'TIEMPO TOTAL');
      if (w.dist) add('distanceM', 'Distancia total', (w.dist / 1000).toFixed(1), 'KM TOTALES');
      if (w.streak > 1) add('streak', 'Racha', w.streak, 'SEMANAS SEGUIDAS');
      if (w.range) add('weekStart', 'Fechas', w.range);
      if (d.days) add('days', 'Días entrenados', w.days.filter(Boolean).length, 'DÍAS ACTIVOS');
      normalizeDisciplines(d).forEach((r) => add(r.id, r.label + ' · ' + r.value, r.value, r.label.toUpperCase()));
      if (normalizeWeekSessions(d).length) { add('sessions', referenceCopy(d).fields.sessions, normalizeWeekSessions(d).length); add('daily', referenceCopy(d).fields.daily, 7); }
    } else {
      const f = workoutFacts({ ...d, fields: undefined });
      add('title', 'Nombre del entreno', f.title);
      if (f.dur) add('durationSec', 'Tiempo', f.dur % 60 ? clock(f.dur) : minutesText(f.dur), 'TIEMPO');
      if (f.dist) add('distanceM', 'Distancia', distanceText(f.type, f.dist), distanceUnit(f.type));
      if (f.pace) add('pace', 'Ritmo / velocidad', f.pace, f.type === 'bike' ? 'VELOCIDAD' : 'RITMO');
      if (d.avgHr > 0) add('avgHr', 'Frecuencia cardiaca', Math.round(d.avgHr), 'LPM · FC MEDIA');
      if (f.number) add('number', 'Número de entreno', f.number, 'Nº DE ENTRENO');
      if (f.sets) add('sets', 'Series', f.sets, 'SERIES');
      if (f.vol) add('volumeKg', 'Volumen', thousands(f.vol), 'KG MOVIDOS');
      if (d.kcal > 0) add('kcal', 'Calorías', thousands(d.kcal), 'KCAL');
      if (d.elevationM > 0) add('elevationM', 'Desnivel', thousands(d.elevationM), 'M DE DESNIVEL');
      if (d.effort > 0) add('effort', 'Esfuerzo', Math.round(d.effort) + '/10', 'ESFUERZO');
      if (f.date) add('ds', 'Fecha', f.date);
      if (f.exercises.length) add('exercises', 'Ejercicios y mejores series', f.exercises.map((e) => e.name + (e.best ? ' · ' + e.best : '')).join(' / '));
    }
    return rows;
  }

  function selectedFields(kind, d) {
    return stickerFields(kind, d).filter((r) => !Array.isArray(d.fields) || d.fields.includes(r.id));
  }

  // Tres gramáticas, una marca: firma de 320 px de ancho sobre lienzo de 1080.
  // El contenido crece hacia abajo; nunca se encoge la firma por añadir información.
  function editorialLayout(kind, variant, d, measure) {
    const rows = selectedFields(kind, d), ops = [];
    const card = variant === 'ficha', compact = variant === 'compacto';
    const ink = card ? 'inv' : 'fg';
    const x = 88, maxW = WIDTH - x * 2;
    let y = 86;
    const put = (text, max, min, weight, color, spacing) => {
      const t = fitText(measure, String(text), (px) => F(weight, px), maxW, max, min, spacing || 0);
      y += t.px * CAP;
      ops.push(textOp(measure, t.text, F(weight, t.px), { x, y, spacing: t.spacing, color: color || ink }));
      y += t.px * 0.28;
    };
    put(kind === 'week' ? 'MI SEMANA' : 'MI ENTRENO', 32, 32, 600, ink, .18);
    y += 42;
    const title = rows.find((r) => r.id === 'title');
    if (title) { put(title.value.toUpperCase(), compact ? 68 : 90, 38, 800); y += 24; }
    const metrics = rows.filter((r) => !r.id.startsWith('discipline:') && !['title', 'ds', 'weekStart', 'days', 'sessions', 'daily'].includes(r.id));
    metrics.forEach((r, i) => {
      if (compact) {
        if (i) y += 22;
        const base = y;
        const label = fitText(measure, r.unit || r.label.toUpperCase(), (p) => F(500, p), 310, 30, 30);
        ops.push(textOp(measure, label.text, F(500, label.px), { x, y: base + 44, color: ink, alpha: .75 }));
        const value = fitText(measure, r.value, (p) => F(700, p), 550, 76, 38);
        ops.push(textOp(measure, value.text, F(700, value.px), { x: WIDTH - x, y: base + 56, align: 'right', color: ink }));
        y += 92;
        ops.push({ op: 'line', x1: x, x2: WIDTH - x, y1: y, y2: y, stroke: 2, color: ink, alpha: .22 });
      } else if (i === 0) {
        put(r.value, 200, 48, 800);
        y += 12;
        put(r.unit || r.label.toUpperCase(), 30, 30, 500, ink, .1);
        y += 42;
      } else {
        // Dos columnas: añadir datos no encoge toda la composición.
        const col = (i - 1) % 2;
        if (col === 0) {
          ops.push({ op: 'line', x1: x, x2: WIDTH - x, y1: y, y2: y, stroke: 2, color: ink, alpha: .22 });
          y += 36;
        }
        const start = x + col * 474;
        const t = fitText(measure, r.value, (p) => F(700, p), 420, 86, 38);
        ops.push(textOp(measure, t.text, F(700, t.px), { x: start, y: y + 72, color: ink }));
        const label = fitText(measure, r.unit || r.label.toUpperCase(), (p) => F(500, p), 420, 30, 30);
        ops.push(textOp(measure, label.text, F(500, label.px), { x: start, y: y + 128, color: ink, alpha: .8 }));
        if (col === 1 || i === metrics.length - 1) y += 166;
      }
    });
    if (rows.some((r) => r.id === 'days')) {
      y += 42;
      const days = weekFacts(d).days;
      'LMMJVSD'.split('').forEach((letter, i) => {
        const cx = x + 36 + i * 132;
        ops.push({ op: 'circle', cx, cy: y + 30, r: 28, stroke: days[i] ? 0 : 2, color: ink, alpha: days[i] ? 1 : .3 });
        ops.push(textOp(measure, letter, F(600, 30), { x: cx, y: y + 100, align: 'center', color: ink }));
      });
      y += 112;
    }
    if (kind === 'week') { const block = disciplineBlock(d, measure, x, y + 32, maxW, ink); ops.push(...block.ops); y += block.height; }
    const date = rows.find((r) => r.id === 'ds' || r.id === 'weekStart');
    if (date) { y += 36; put(date.value, 32, 32, 500); }
    y += 64;
    const probe = lockupLayout(0, 0, 40, measure);
    const brand = lockupOps(measure, x, y, Math.round(40 * 320 / probe.width), 'left', ink);
    ops.push(...brand.ops);
    y += brand.height + 80;
    if (card) ops.unshift({ op: 'rect', x: 20, y: 20, w: WIDTH - 40, h: y - 20, r: 44 });
    return { kind: variant, width: WIDTH, height: Math.ceil(y + 20), ops };
  }

  for (const kind of ['workout', 'week']) {
    KINDS[kind].styles.unshift(...[
      ['editorial', 'Editorial'], ['ficha', 'Ficha'], ['compacto', 'Compacto']
    ].map(([id, label]) => ({ id, label, customizable: true, layout: (d, m) => editorialLayout(kind, id, d, m) })));
  }

  // La semana tiene su propio lenguaje: calendario, boleto, cifras, sello y tipografía.
  // Siempre parte de la misma lista ya seleccionada; ningún diseño consulta métricas ocultas.
  function weeklyStudioLayout(id, d, measure) {
    const rows = selectedFields('week', d), ops = [];
    const filled = ['bitacora', 'carnet'].includes(id);
    const ink = filled ? 'inv' : 'fg';
    const left = 88, right = WIDTH - left, inner = right - left;
    let y = 92;
    function text(value, px, atY, opts) {
      opts = opts || {};
      const t = fitText(measure, String(value), (p) => F(opts.weight || 700, p, opts.italic), opts.width || inner, px, Math.min(px, 32), opts.spacing || 0);
      ops.push(textOp(measure, t.text, F(opts.weight || 700, t.px, opts.italic), {
        x: opts.x == null ? left : opts.x, y: atY, align: opts.align || 'left',
        spacing: t.spacing, color: ink, alpha: opts.alpha == null ? 1 : opts.alpha, stroke: opts.stroke
      }));
      return t.px;
    }
    const rule = (atY, dash) => ops.push({ op: 'line', x1: left, x2: right, y1: atY, y2: atY, color: ink, alpha: .3, dash });
    const center = (value, px, atY, opts) => text(value, px, atY, { ...opts, x: WIDTH / 2, align: 'center' });
    const metrics = rows.filter((r) => !r.id.startsWith('discipline:') && !['weekStart', 'days', 'sessions', 'daily'].includes(r.id));
    const main = (id === 'racha' && metrics.find((r) => r.id === 'streak')) || metrics[0];
    const rest = metrics.filter((r) => r !== main);
    const date = rows.find((r) => r.id === 'weekStart');
    const hasDays = rows.some((r) => r.id === 'days');
    const centered = ['semana', 'insignia', 'heroe', 'crew', 'racha'].includes(id);
    const heading = id === 'bitacora' ? 'MI SEMANA / REGISTRO' : id === 'ritual' ? 'EL HÁBITO SE CONSTRUYE.' : 'MI SEMANA';
    (centered ? center : text)(heading, 32, y, { weight: 600, spacing: .14 });
    y += 58;
    // Calendario protagonista: cada celda muestra presencia, nunca una intensidad inventada.
    const calendar = (large) => {
      const step = inner / 7, box = large ? 108 : 64;
      'LMMJVSD'.split('').forEach((day, i) => {
        const cx = left + step * (i + .5), active = !!(d.days && d.days[i]);
        const cy = y + (large ? 74 : 42);
        if (large) {
          ops.push({ op: 'rect', x: cx - box / 2, y: cy - box / 2, w: box, h: box, r: 28, color: ink, stroke: active ? 0 : 2, alpha: active ? 1 : .25 });
          if (active) ops.push(textOp(measure, '✓', F(700, 52), { x: cx, y: cy + 18, align: 'center', color: filled ? 'fg' : 'inv' }));
        } else {
          ops.push({ op: 'circle', cx, cy, r: box / 2, color: ink, stroke: active ? 0 : 2, alpha: active ? 1 : .3 });
        }
        text(day, 30, cy + box / 2 + 44, { x: cx, align: 'center', weight: 500 });
      });
      y += large ? 218 : 154;
    };
    if (id === 'ritual' && hasDays) { calendar(true); rule(y); y += 64; }
    if (id === 'crew') {
      // Firma de tamaño constante; la tipografía protagonista es la frase, no otro logo enorme.
      center('MAKE IT', 142, y + 106, { weight: 900 });
      center('A HABIT.', 142, y + 246, { weight: 900 });
      y += 310;
    }
    if (id === 'datos' || id === 'balance') {
      // Dos columnas como máximo para que un tiempo largo siga siendo legible.
      metrics.forEach((r, i) => {
        const col = i % 2, x = left + col * 474;
        if (!col && i) { y += 190; }
        text(r.value, 110, y + 96, { x, width: 420, weight: 800 });
        text(r.unit, 30, y + 152, { x, width: 420, weight: 500 });
      });
      if (metrics.length) y += 206;
    } else if (main) {
      if (id === 'insignia') {
        const cy = y + 280;
        ops.push({ op: 'circle', cx: WIDTH / 2, cy, r: 270, stroke: 3, color: ink });
        ops.push({ op: 'circle', cx: WIDTH / 2, cy, r: 248, stroke: 1, color: ink, alpha: .35 });
        center(main.value, 210, cy + 35, { width: 420, weight: 900 });
        center(main.unit, 30, cy + 114, { width: 420, spacing: .1 });
        y += 610;
      } else if (id === 'bitacora') {
        rule(y, [10, 9]); y += 64;
        text(main.unit, 32, y, { weight: 500, spacing: .12 });
        y += 206;
        text(main.value, 240, y, { weight: 800 }); y += 90;
      } else if (id === 'racha') {
        const label = main.id === 'streak' ? 'SEMANAS / SEGUIDAS' : main.unit;
        center(main.value, 300, y + 240, { weight: 800, italic: true });
        center(label, 36, y + 330, { spacing: .12 }); y += 410;
      } else {
        const px = id === 'carnet' ? 230 : 300;
        const align = centered ? center : text;
        align(main.value, px, y + px * .8, { weight: 900, stroke: id === 'heroe' ? 4 : undefined });
        align(main.unit, 34, y + px * .8 + 80, { weight: 600, spacing: .12 });
        y += px * .8 + 160;
      }
      rest.forEach((r) => {
        rule(y, id === 'bitacora' ? [10, 9] : undefined); y += 76;
        text(r.unit, 30, y, { width: 360, weight: 500, alpha: .8 });
        text(r.value, 68, y + 8, { x: right, align: 'right', width: 490, weight: 700 });
        y += 60;
      });
    }
    if (hasDays && id !== 'ritual') { y += 24; calendar(id === 'semana'); }
    const sports = disciplineBlock(d, measure, left, y + 24, inner, ink); ops.push(...sports.ops); y += sports.height;
    if (date) { y += 28; (centered ? center : text)(date.value, 32, y, { weight: 500, spacing: .06 }); y += 32; }
    if (id === 'bitacora') { y += 20; rule(y, [10, 9]); y += 38; ops.push(...barcode(rows.map((r) => r.value).join('|'), left, y, inner, 64).map((o) => ({ ...o, color: ink }))); y += 96; }
    y += 58;
    const probe = lockupLayout(0, 0, 40, measure);
    const brand = lockupOps(measure, centered ? WIDTH / 2 : left, y, Math.round(40 * 320 / probe.width), centered ? 'center' : 'left', ink);
    ops.push(...brand.ops); y += brand.height + 80;
    if (filled) {
      if (id === 'bitacora') {
        ops.unshift({ op: 'poly', pts: [...zigzag(24, WIDTH - 24, 24, 12, 24, false), ...zigzag(24, WIDTH - 24, y, 12, 24, true).reverse()], color: 'fg' });
      } else ops.unshift({ op: 'rect', x: 24, y: 24, w: WIDTH - 48, h: y - 24, r: 48, color: 'fg' });
    }
    return { kind: id, width: WIDTH, height: Math.ceil(y + 24), ops };
  }

  // Restaurar el catálogo completo: las casillas no son un filtro de diseños.
  for (const style of KINDS.workout.styles) style.customizable = true;
  for (const style of KINDS.week.styles) {
    if (style.customizable) continue;
    const original = style.layout;
    style.customizable = true;
    style.layout = (d, m) => Array.isArray(d.fields) || normalizeDisciplines(d).length ? weeklyStudioLayout(style.id, d, m) : original(d, m);
  }
  KINDS.week.styles.unshift(...[
    ['ritual', 'Ritual'], ['bitacora', 'Bitácora'], ['balance', 'Balance']
  ].map(([id, label]) => ({ id, label, customizable: true, layout: (d, m) => weeklyStudioLayout(id, d, m) })));

  KINDS.week.styles.unshift(...[
    ['thisweek', 'This Week'], ['mix', 'Mix'], ['pasaporte', 'Pasaporte'], ['tipografico', 'Tipográfico']
  ].map(([id, label]) => ({ id, label, customizable: true, layout: (d, m) => disciplineWeekLayout(id, d, m) })));

  KINDS.week.styles.unshift(...[
    ['diario', 'Diario'], ['notas', 'Notas'], ['barras', 'Barras'], ['tabla', 'Tabla'], ['impacto', 'Impacto']
  ].map(([id, label]) => ({ id, label, customizable: true, layout: (d, m) => weeklyReferenceLayout(id, d, m) })));

  // ── Dibujo (navegador) ─────────────────────────────────────────────────

  let fontsReady = null;
  // Inter ya la carga cada app (Google Fonts), pero sin los pesos 100–200, el 900 ni la itálica,
  // y puede no haber terminado: sin esperar, el canvas dibuja con la fuente del sistema y no avisa.
  function ensureFonts(doc) {
    if (fontsReady) return fontsReady;
    doc = doc || global.document;
    let sheetReady = Promise.resolve();
    if (doc.head && !doc.getElementById('hs-inter')) {
      const link = doc.createElement('link');
      link.id = 'hs-inter'; link.rel = 'stylesheet'; link.href = FONT_HREF;
      sheetReady = new Promise((r) => { link.onload = r; link.onerror = r; });
      doc.head.appendChild(link);
    }
    const wanted = [F(200, 80), F(300, 60), F(300, 60, true), F(400, 40), F(500, 40), F(600, 40), F(700, 40), F(800, 40), F(800, 80, true), F(900, 80)];
    const load = sheetReady.then(() => (doc.fonts && doc.fonts.load
      ? Promise.all(wanted.map((f) => doc.fonts.load(f, 'HABIT0123456789“”áéíóúÁÉÍÓÚñÑ·:/.,Nº')))
      : null));
    const timeout = new Promise((r) => setTimeout(r, 3500));
    fontsReady = Promise.race([load, timeout]).catch(() => {}).then(() => true);
    return fontsReady;
  }

  // El logo es el PNG blanco del encabezado (mismo origen, así que no "ensucia" el canvas).
  let logoReady = null;
  function loadLogo() {
    if (logoReady) return logoReady;
    logoReady = new Promise((resolve, reject) => {
      const img = new global.Image();
      img.onload = () => resolve(img);
      img.onerror = () => { logoReady = null; reject(new Error('No se pudo cargar el logo')); };
      img.src = LOGO_SRC;
    });
    return logoReady;
  }

  function newCanvas(doc, w, h) {
    const c = (doc || global.document).createElement('canvas');
    c.width = Math.ceil(w); c.height = Math.ceil(h);
    return c;
  }

  function canvasMeasure(ctx) {
    return (text, font) => { ctx.font = font; return ctx.measureText(text).width; };
  }

  function drawSpaced(ctx, text, x, y, spacing, stroke) {
    let cx = x;
    [...text].forEach((c) => {
      if (stroke) ctx.strokeText(c, cx, y); else ctx.fillText(c, cx, y);
      cx += ctx.measureText(c).width + spacing;
    });
  }

  // Las disposiciones miden el logo por lo que se ve: `box` es su tinta. El PNG trae margen
  // (la tinta es LOGO_INK de su cuadro), así que se dibuja entero, más grande y centrado en
  // ella; medirlo por el cuadro dejaba cada logo en dos tercios del tamaño que se pedía.
  // Viene blanco; en cualquier otro color se tiñe en un lienzo aparte (source-in pinta solo
  // donde el logo tiene tinta, y conserva sus bordes suaves).
  function drawLogo(ctx, img, box, color, doc) {
    const full = box.size / LOGO_INK, x = box.x - (full - box.size) / 2, y = box.y - (full - box.size) / 2;
    if (String(color).toLowerCase() === COLORS.blanco) { ctx.drawImage(img, x, y, full, full); return; }
    const off = newCanvas(doc, full, full);
    const o = off.getContext('2d');
    o.drawImage(img, 0, 0, full, full);
    o.globalCompositeOperation = 'source-in';
    o.fillStyle = color; o.fillRect(0, 0, full, full);
    ctx.drawImage(off, x, y, full, full);
  }

  function drawLockup(ctx, L, img, color, doc) {
    drawLogo(ctx, img, L.logo, color, doc);
    ctx.font = L.word.font; ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
    drawSpaced(ctx, L.word.text, L.word.x, L.word.y, L.word.spacing);
    ctx.font = L.crew.font;
    drawSpaced(ctx, L.crew.text, L.crew.x, L.crew.y, L.crew.spacing);
  }

  function roundRectPath(ctx, x, y, w, h, r) {
    r = Math.max(0, Math.min(r || 0, w / 2, h / 2));
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  // Los trazos de los estilos nuevos. 'fg' es el color del sticker; 'inv', la tinta que va
  // encima de él (`pal.ink`: negro o blanco, la que contraste).
  function drawOps(ctx, ops, img, pal, doc) {
    ops.forEach((o) => {
      const color = o.color === 'inv' ? pal.ink : pal.fg;
      ctx.save();
      ctx.globalAlpha = o.alpha == null ? 1 : o.alpha;
      ctx.fillStyle = color; ctx.strokeStyle = color;
      if (o.op === 'text') {
        ctx.font = o.font; ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
        if (o.scaleX) { ctx.translate(o.x, o.y); ctx.scale(o.scaleX, 1); }
        const tx = o.scaleX ? 0 : o.x, ty = o.scaleX ? 0 : o.y;
        const put = (stroke) => {
          if (o.spacing) drawSpaced(ctx, o.text, o.x, o.y, o.spacing, stroke);
          else if (stroke) ctx.strokeText(o.text, tx, ty);
          else ctx.fillText(o.text, tx, ty);
        };
        if (o.stroke) {
          // Inter variable trae contornos encimados dentro de algunas letras (el 4): trazarlos
          // dibuja esas líneas. Se traza al doble y se borra el relleno: queda solo el borde.
          ctx.lineWidth = o.stroke * 2; ctx.lineJoin = 'round';
          put(true);
          ctx.globalCompositeOperation = 'destination-out';
          put(false);
        } else put(false);
      } else if (o.op === 'sport') {
        const mark = SPORT_MARKS[o.type] || SPORT_MARKS.other;
        ctx.translate(o.x, o.y); ctx.scale(o.size / 26, o.size / 26); ctx.translate(1, 1);
        ctx.lineWidth = 2.6; ctx.lineCap = 'square'; ctx.lineJoin = 'miter';
        (mark.dots || []).forEach(([x, y, r]) => { ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill(); });
        (mark.rings || []).forEach(([x, y, r]) => { ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.stroke(); });
        (mark.paths || []).forEach((points) => { ctx.beginPath(); points.forEach(([x, y], i) => i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)); ctx.stroke(); });
      } else if (o.op === 'logo') {
        // `clip`: el logo se corta en esa forma (la marca de agua del carnet sale de su borde).
        if (o.clip) { roundRectPath(ctx, o.clip.x, o.clip.y, o.clip.w, o.clip.h, o.clip.r); ctx.clip(); }
        drawLogo(ctx, img, o, color, doc);
      } else if (o.op === 'rect') {
        roundRectPath(ctx, o.x, o.y, o.w, o.h, o.r);
        if (o.stroke) { ctx.lineWidth = o.stroke; ctx.stroke(); } else ctx.fill();
      } else if (o.op === 'circle') {
        ctx.beginPath(); ctx.arc(o.cx, o.cy, o.r, 0, Math.PI * 2);
        if (o.stroke) { ctx.lineWidth = o.stroke; ctx.stroke(); } else ctx.fill();
      } else if (o.op === 'line') {
        ctx.lineWidth = o.w || 2; ctx.lineCap = 'round';
        if (o.dash) ctx.setLineDash(o.dash);
        ctx.beginPath(); ctx.moveTo(o.x1, o.y1); ctx.lineTo(o.x2, o.y2); ctx.stroke();
      } else if (o.op === 'poly') {
        ctx.beginPath();
        o.pts.forEach((p, i) => (i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])));
        ctx.closePath(); ctx.fill();
      } else if (o.op === 'arc') {
        // Texto alrededor de un círculo (la «Insignia»), letra por letra como el sello.
        ctx.font = o.font; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        o.chars.forEach((c) => {
          ctx.save();
          ctx.translate(o.cx, o.cy);
          ctx.rotate(c.angle);
          ctx.fillText(c.ch, 0, -o.radius);
          ctx.restore();
        });
      }
      ctx.restore();
    });
  }

  const DRAW = {
    frase(ctx, L, img, color, doc) {
      ctx.font = L.font; ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic';
      L.lines.forEach((l) => ctx.fillText(l.text, l.x, l.y));
      drawLockup(ctx, L.lockup, img, color, doc);
    },
    logotipo(ctx, L, img, color, doc) {
      drawLockup(ctx, L.lockup, img, color, doc);
      ctx.font = L.sub.font; ctx.textAlign = 'left';
      drawSpaced(ctx, L.sub.text, L.sub.x, L.sub.y, L.sub.spacing);
    },
    sello(ctx, L, img, color, doc) {
      drawLogo(ctx, img, L.logo, color, doc);
      ctx.font = L.font; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      L.chars.forEach((c) => {
        ctx.save();
        ctx.translate(L.cx, L.cy);
        ctx.rotate(c.angle);
        ctx.fillText(c.ch, 0, -L.radius);
        ctx.restore();
      });
    }
  };

  // Los estilos que sí tienen qué mostrar con estos datos.
  function stylesFor(kind, data, measure) {
    const K = KINDS[kind] || KINDS.quote;
    return K.styles.filter((s) => { try { return !!s.layout(data || {}, measure); } catch (_) { return false; } });
  }

  // Un sticker: un canvas transparente del tamaño justo. `logo` es la imagen ya cargada.
  function renderSticker(doc, kind, styleId, data, colorKey, logo) {
    const style = (KINDS[kind] || KINDS.quote).styles.find((s) => s.id === styleId);
    if (!style) throw new Error('Estilo desconocido: ' + styleId);
    const pal = resolveColor(colorKey);
    const probe = newCanvas(doc, 1, 1).getContext('2d');
    const L = style.layout(data || {}, canvasMeasure(probe));
    if (!L) throw new Error('El estilo ' + styleId + ' no aplica a estos datos');
    const canvas = newCanvas(doc, L.width, L.height);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = pal.fg;
    if (L.ops) drawOps(ctx, L.ops, logo, pal, doc);
    else DRAW[L.kind](ctx, L, logo, pal.fg, doc);
    return canvas;
  }

  function toBlob(canvas) {
    return new Promise((resolve, reject) => {
      canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('No se pudo crear la imagen'))), 'image/png');
    });
  }

  // La hoja del teléfono con el PNG: Instagram, WhatsApp, Guardar imagen, Copiar. Sin hoja de
  // compartir (una computadora), se descarga. Devuelve 'shared', 'cancelled' o 'downloaded'.
  async function shareImage(blob, filename) {
    const nav = global.navigator || {};
    const name = filename || 'habit-sticker.png';
    const File_ = global.File;
    if (File_ && nav.canShare && nav.share) {
      const file = new File_([blob], name, { type: 'image/png' });
      if (nav.canShare({ files: [file] })) {
        try { await nav.share({ files: [file] }); return 'shared'; }
        catch (e) { if (e && e.name === 'AbortError') return 'cancelled'; }
      }
    }
    const url = URL.createObjectURL(blob);
    const a = global.document.createElement('a');
    a.href = url; a.download = name; global.document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
    return 'downloaded';
  }

  // ── La galería (navegador) ─────────────────────────────────────────────

  const SHARE_ICON = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12"/><path d="M8 7l4-4 4 4"/><path d="M7 10H6a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-7a2 2 0 0 0-2-2h-1"/></svg>';

  // Arriba de todo lo de las dos apps (sus hojas llegan a 10000; sus avisos van más arriba).
  // Con muchos estilos, una lista era un scroll larguísimo: ahora se desliza de uno a otro,
  // con miniaturas debajo para saltar, y un solo botón Compartir para el que se ve.
  const CSS = `
.hs-overlay{position:fixed;inset:0;z-index:10040;background:rgba(6,7,9,.66);display:none;align-items:flex-end;justify-content:center;font-family:${INTER}}
.hs-overlay.open{display:flex;animation:hsFade .18s ease both}
.hs-sheet{width:100%;max-width:480px;max-height:94vh;background:#141518;color:#f4f5f7;border-radius:22px 22px 0 0;display:flex;flex-direction:column;overflow:hidden;animation:hsUp .3s cubic-bezier(.2,.8,.2,1) both;padding-bottom:env(safe-area-inset-bottom,0px)}
.hs-options{margin:12px 20px;color:#cdd0d6;font-size:13px}.hs-options[hidden]{display:none}.hs-options summary{cursor:pointer;padding:10px 0;font-weight:600}.hs-fields{max-height:180px;overflow-y:auto;overscroll-behavior:contain;display:grid;grid-template-columns:1fr 1fr;gap:12px;padding:12px 0}.hs-fields label{display:flex;align-items:center;gap:8px}.hs-fields input{flex:0 0 18px;min-width:18px;min-height:18px;padding:0;margin:0;accent-color:#d4ff3a;width:18px;height:18px}.hs-presets{display:flex;gap:8px;padding:10px 0}.hs-presets[hidden]{display:none}.hs-presets button{border:1px solid #45474d;background:#222429;color:#eee;border-radius:999px;padding:8px 12px;font:600 12px ${INTER};cursor:pointer}.hs-options p{font-size:12px;line-height:1.5;color:#9298a3}
.hs-head{display:flex;align-items:center;gap:12px;padding:16px 16px 6px}
.hs-title{flex:1;text-align:center;font-size:17px;font-weight:700;margin:0;letter-spacing:0;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.hs-close{background:none;border:0;color:#9aa0aa;font-size:24px;line-height:1;cursor:pointer;padding:4px 6px}
.hs-head-gap{width:26px;flex-shrink:0}
.hs-colors{display:flex;gap:10px;overflow-x:auto;padding:14px 20px 4px;scrollbar-width:none;-webkit-overflow-scrolling:touch}
.hs-colors::-webkit-scrollbar{display:none}
.hs-colors::after{content:'';flex:0 0 8px}
.hs-color{flex:0 0 30px;width:30px;height:30px;border-radius:50%;border:1px solid rgba(255,255,255,.22);padding:0;margin:0;cursor:pointer;position:relative;box-sizing:border-box}
.hs-color.on{outline:2px solid #fff;outline-offset:3px}
.hs-custom{background:conic-gradient(#ef4444,#ffd60a,#d4ff3a,#10b981,#7cc4ff,#2563eb,#8b5cf6,#ff8fb8,#ef4444)}
.hs-custom.has{background:radial-gradient(circle,var(--c) 0 44%,transparent 46%),conic-gradient(#ef4444,#ffd60a,#d4ff3a,#10b981,#7cc4ff,#2563eb,#8b5cf6,#ff8fb8,#ef4444)}
.hs-custom input{position:absolute;inset:0;width:100%;height:100%;opacity:0;border:0;padding:0;margin:0;cursor:pointer}
.hs-body{overflow-y:auto;overscroll-behavior:contain;padding-bottom:10px}
.hs-sub{text-align:center;font-size:13px;color:#9aa0aa;margin:0 20px 12px;min-height:1px}
.hs-stage{margin:0 16px;border-radius:20px;overflow:hidden;background:#1f2024}
.hs-stage.light,.hs-thumb.light{background:#d9dbe0}
.hs-track{display:flex;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;-webkit-overflow-scrolling:touch;overscroll-behavior-x:contain}
.hs-track::-webkit-scrollbar,.hs-thumbs::-webkit-scrollbar{display:none}
.hs-slide{flex:0 0 100%;scroll-snap-align:center;scroll-snap-stop:always;height:min(44vh,340px);display:flex;align-items:center;justify-content:center;padding:24px;box-sizing:border-box}
.hs-slide img{display:block;max-width:100%;max-height:100%;object-fit:contain}
.hs-slide img[hidden]{display:none}
.hs-slide .hs-wait{padding:0}
.hs-meta{display:flex;align-items:baseline;justify-content:space-between;margin:12px 22px 10px;font-size:13px}
.hs-label{font-weight:700;color:#f4f5f7;letter-spacing:.02em}
.hs-count{color:#7d828c;font-variant-numeric:tabular-nums}
.hs-thumbs{display:flex;gap:8px;overflow-x:auto;padding:4px 16px;scrollbar-width:none}
.hs-thumb{flex:0 0 54px;height:54px;border-radius:12px;background:#1f2024;border:0;padding:7px;cursor:pointer;opacity:.55;transition:opacity .15s}
.hs-thumb.on{opacity:1;outline:2px solid #fff;outline-offset:2px}
.hs-thumb img{display:block;width:100%;height:100%;object-fit:contain}
.hs-actions{padding:14px 16px 4px}
.hs-share-main{width:100%;display:flex;align-items:center;justify-content:center;gap:9px;border:0;border-radius:999px;background:#fff;color:#0b0b0b;font:700 16px ${INTER};padding:15px 18px;cursor:pointer}
.hs-share-main:disabled{opacity:.45;cursor:default}
.hs-share-main:active:not(:disabled){transform:scale(.98)}
.hs-share-main svg,.hs-chip svg{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
.hs-hint{text-align:center;font-size:12px;line-height:1.45;color:#8a8f99;margin:10px 24px 8px}
.hs-wait{padding:40px 0;text-align:center;color:#9aa0aa;font-size:13px}
.hs-chip{display:inline-flex;align-items:center;gap:6px;color:inherit;font-weight:600;cursor:pointer}
.hs-chip svg{width:17px;height:17px}
.hs-chip-row{position:relative;z-index:1;display:flex;justify-content:center;margin-top:12px;font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#d7dae0}
[data-hs-share]{cursor:pointer}
@keyframes hsFade{from{opacity:0}to{opacity:1}}
@keyframes hsUp{from{transform:translateY(40px);opacity:.4}to{transform:none;opacity:1}}
@media (prefers-reduced-motion:reduce){.hs-overlay.open,.hs-sheet{animation:none}}`;

  let sheet = null, state = null, seq = 0;

  function readColor() {
    try { const c = global.localStorage.getItem(COLOR_KEY); return paletteHex(c) || isHex(c) ? c : 'blanco'; } catch (_) { return 'blanco'; }
  }
  function saveColor(c) { try { global.localStorage.setItem(COLOR_KEY, c); } catch (_) { /* sin almacenamiento: no pasa nada */ } }
  function say(msg, type) { if (typeof global.toast === 'function') global.toast(msg, type); }
  const escHtml = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  // Los estilos entran al cargar, no al abrir la galería: el botón Compartir de cada app (el
  // ícono, el cursor) se pinta antes de que nadie abra nada.
  function injectCss(doc) {
    if (!doc || !doc.head || doc.getElementById('hs-css')) return;
    const style = doc.createElement('style');
    style.id = 'hs-css';
    style.textContent = CSS;
    doc.head.appendChild(style);
  }

  function buildSheet(doc) {
    if (sheet) return sheet;
    injectCss(doc);
    const el = doc.createElement('div');
    el.className = 'hs-overlay';
    el.innerHTML = '<div class="hs-sheet" role="dialog" aria-modal="true" aria-labelledby="hs-title">'
      + '<div class="hs-head"><span class="hs-head-gap"></span>'
      + '<h2 class="hs-title" id="hs-title"></h2>'
      + '<button type="button" class="hs-close" aria-label="Cerrar">×</button></div>'
      + '<div class="hs-body"><p class="hs-sub"></p>'
      + '<details class="hs-options"><summary>Qué quiero mostrar</summary><div class="hs-presets" hidden><button type="button" data-selection="sports">Solo disciplinas</button><button type="button" data-selection="all">Resumen completo</button></div><div class="hs-fields"></div><p>Solo aparecen datos disponibles. La vista previa muestra exactamente lo que compartirás.</p></details>'
      + '<div class="hs-stage"><div class="hs-track"></div></div>'
      // Los colores, debajo del sticker: con doce y uno libre ya no caben en la cabeza.
      + '<div class="hs-colors" role="radiogroup" aria-label="Color del sticker">'
      + PALETTE.map((c) => '<button type="button" class="hs-color" role="radio" data-c="' + c.key + '" aria-label="' + c.label + '" style="background:' + c.hex + '"></button>').join('')
      + '<label class="hs-color hs-custom" aria-label="Otro color"><input type="color" value="#ff6b2c"></label></div>'
      + '<div class="hs-meta"><span class="hs-label"></span><span class="hs-count"></span></div>'
      + '<div class="hs-thumbs" role="tablist" aria-label="Estilos"></div>'
      + '<div class="hs-actions"><button type="button" class="hs-share-main" disabled>' + SHARE_ICON + 'Compartir</button></div>'
      + '<p class="hs-hint">Desliza para ver los estilos. En Compartir, toca <b>Copiar</b> y pégalo en tu historia: el fondo es transparente, va encima de tu foto.</p>'
      + '</div></div>';
    doc.body.appendChild(el);
    el.addEventListener('click', (e) => {
      if (e.target === el || e.target.closest('.hs-close')) { close(); return; }
      const preset = e.target.closest('[data-selection]');
      if (preset && state) {
        const fields = stickerFields(state.kind, state.data);
        setFields(fields.filter((r) => preset.dataset.selection === 'all' || r.id.startsWith('discipline:') || ['sessions', 'daily'].includes(r.id)).map((r) => r.id));
        return;
      }
      const c = e.target.closest('.hs-color');
      if (c && c.dataset.c) { setColor(c.dataset.c); return; }
      const t = e.target.closest('.hs-thumb');
      if (t) { goTo(Number(t.dataset.i)); return; }
      if (e.target.closest('.hs-share-main')) shareCurrent();
    });
    el.addEventListener('change', (e) => {
      if (!e.target.matches('[data-field]') || !state) return;
      setFields(Array.from(el.querySelectorAll('[data-field]:checked'), (b) => b.dataset.field));
    });
    // El color libre: el selector del teléfono avisa mientras se mueve; se pinta al detenerse.
    let colorTimer = 0;
    el.addEventListener('input', (e) => {
      if (!e.target.matches('.hs-custom input')) return;
      const v = e.target.value;
      clearTimeout(colorTimer);
      colorTimer = setTimeout(() => setColor(v), 180);
    });
    const track = el.querySelector('.hs-track');
    let raf = 0;
    track.addEventListener('scroll', () => {
      if (raf) return;
      raf = global.requestAnimationFrame(() => {
        raf = 0;
        const w = track.clientWidth || 1;
        setCurrent(Math.round(track.scrollLeft / w));
      });
    }, { passive: true });
    doc.addEventListener('keydown', (e) => {
      if (!el.classList.contains('open')) return;
      if (e.key === 'Escape') close();
      else if (e.key === 'ArrowRight') goTo(state.current + 1);
      else if (e.key === 'ArrowLeft') goTo(state.current - 1);
    });
    sheet = el;
    return el;
  }

  function freeItems() {
    if (state && state.items) state.items.forEach((it) => it && it.url && URL.revokeObjectURL(it.url));
  }

  function setCurrent(i) {
    if (!state || !state.styles) return;
    i = Math.max(0, Math.min(state.styles.length - 1, i));
    state.current = i;
    const s = state.styles[i];
    sheet.querySelector('.hs-label').textContent = s ? (referenceCopy(state.data).styles[s.id] || s.label) : '';
    sheet.querySelector('.hs-count').textContent = state.styles.length ? (i + 1) + ' / ' + state.styles.length : '';
    sheet.querySelectorAll('.hs-thumb').forEach((b, j) => { b.classList.toggle('on', j === i); b.setAttribute('aria-selected', j === i ? 'true' : 'false'); });
    const on = sheet.querySelector('.hs-thumb.on');
    if (on && on.scrollIntoView) on.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    sheet.querySelector('.hs-share-main').disabled = !(state.items && state.items[i]);
  }

  // El salto desde una miniatura es directo, no animado: con scroll-snap, un deslizamiento
  // suave que se cruza con un sticker recién pintado se regresa al estilo de donde salió.
  function goTo(i) {
    if (!state || !state.styles) return;
    i = Math.max(0, Math.min(state.styles.length - 1, i));
    const track = sheet.querySelector('.hs-track');
    track.scrollLeft = i * track.clientWidth;
    setCurrent(i);
  }

  // Dibuja los estilos uno por uno y los va poniendo: el primero sale en cuanto está, y el
  // botón Compartir de cada uno entrega una imagen que ya existe (el iPhone no espera).
  async function paint() {
    const doc = global.document;
    const my = ++seq;
    freeItems();
    state.items = null;
    sheet.querySelector('.hs-share-main').disabled = true;
    const kind = KINDS[state.kind] || KINDS.quote;
    sheet.querySelector('.hs-title').textContent = state.title || kind.title;
    sheet.querySelector('.hs-sub').textContent = state.subtitle || '';
    sheet.querySelectorAll('.hs-color[data-c]').forEach((b) => {
      const on = b.dataset.c === state.color;
      b.classList.toggle('on', on); b.setAttribute('aria-checked', on ? 'true' : 'false');
    });
    const custom = sheet.querySelector('.hs-custom');
    const isCustom = !paletteHex(state.color) && isHex(state.color);
    custom.classList.toggle('on', isCustom);
    custom.classList.toggle('has', isCustom);
    if (isCustom) { custom.style.setProperty('--c', state.color); custom.querySelector('input').value = state.color; }
    // El fondo de la vista previa, el que deje ver el color: oscuro para los claros, claro
    // para los oscuros.
    const fg = resolveColor(state.color).fg;
    const light = contrast(fg, '#d9dbe0') > contrast(fg, '#1f2024');
    sheet.querySelector('.hs-stage').classList.toggle('light', light);
    const track = sheet.querySelector('.hs-track'), thumbs = sheet.querySelector('.hs-thumbs');
    if (!state.styles) {
      const probe = newCanvas(doc, 1, 1).getContext('2d');
      state.styles = stylesFor(state.kind, state.data, canvasMeasure(probe));
      if (state.preferredStyle) state.current = Math.max(0, state.styles.findIndex((s) => s.id === state.preferredStyle));
      // Cada lámina nace con su <img>: pintar un sticker solo le cambia el src, sin mover nada.
      track.innerHTML = state.styles.map((s) => '<div class="hs-slide"><img alt="Sticker ' + escHtml(referenceCopy(state.data).styles[s.id] || s.label) + '" hidden><div class="hs-wait">Preparando…</div></div>').join('');
      thumbs.innerHTML = state.styles.map((s, i) => '<button type="button" class="hs-thumb" role="tab" data-i="' + i + '" aria-label="' + escHtml(referenceCopy(state.data).styles[s.id] || s.label) + '"></button>').join('');
      goTo(state.current || 0);
    }
    thumbs.querySelectorAll('.hs-thumb').forEach((t) => t.classList.toggle('light', light));
    let logo;
    try { [, logo] = await Promise.all([ensureFonts(doc), loadLogo()]); }
    catch (e) { track.innerHTML = '<div class="hs-slide"><div class="hs-wait">No se pudo cargar el logo. Revisa tu conexión.</div></div>'; return; }
    if (my !== seq) return;
    freeItems();
    state.items = state.styles.map(() => null);
    setCurrent(state.current);
    // El que se ve primero, luego los demás.
    const order = state.styles.map((_, i) => i).sort((a, b) => Math.abs(a - state.current) - Math.abs(b - state.current));
    for (const i of order) {
      const s = state.styles[i];
      let blob;
      try { blob = await toBlob(renderSticker(doc, state.kind, s.id, state.data, state.color, logo)); }
      catch (e) { console.error('HabitShare ' + s.id + ':', e); continue; }
      if (my !== seq) return; // cambiaron el color o cerraron a media pintura
      const url = URL.createObjectURL(blob);
      state.items[i] = { blob, url, label: s.label, name: `habit-crew-${state.kind}-${s.id}-${String(state.color).replace('#', '')}.png` };
      const slide = track.children[i], thumb = thumbs.children[i];
      const img = slide && slide.querySelector('img');
      if (img) { img.src = url; img.hidden = false; const w = slide.querySelector('.hs-wait'); if (w) w.remove(); }
      if (thumb) thumb.innerHTML = '<img src="' + url + '" alt="">';
      if (i === state.current) setCurrent(i);
    }
  }

  function setFields(fields) {
    if (!state) return;
    state.preferredStyle = state.styles && state.styles[state.current] && state.styles[state.current].id;
    state.data = { ...state.data, fields };
    sheet.querySelectorAll('[data-field]').forEach((input) => { input.checked = fields.includes(input.dataset.field); });
    freeItems(); state.items = null; state.styles = null;
    paint().catch(() => say('No se pudo actualizar la vista previa', 'err'));
  }

  function setColor(c) {
    if (!state || c === state.color) return;
    state.color = c; saveColor(c); paint();
    const on = sheet.querySelector('.hs-color.on, .hs-custom.on');
    if (on && on.scrollIntoView) on.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }

  async function shareCurrent() {
    const it = state && state.items && state.items[state.current];
    if (!it) return;
    const how = await shareImage(it.blob, it.name);
    if (how === 'downloaded') say('Imagen guardada', 'ok');
  }

  // Abre la galería. kind: 'quote' | 'workout' | 'week'; data: lo de ese tipo (arriba);
  // title y subtitle, opcionales, para la cabeza de la hoja.
  function open(opts) {
    const doc = global.document;
    opts = opts || {};
    buildSheet(doc);
    freeItems();
    seq++;
    state = {
      kind: KINDS[opts.kind] ? opts.kind : 'quote', data: { ...(opts.data || {}), lang: opts.lang || (opts.data && (opts.data.lang || opts.data.locale)) || doc.documentElement.lang || 'es' }, color: readColor(),
      title: opts.title || '', subtitle: opts.subtitle || '', items: null, styles: null, current: 0,
      onClose: typeof opts.onClose === 'function' ? opts.onClose : null
    };
    const options = sheet.querySelector('.hs-options');
    options.hidden = state.kind === 'quote';
    options.open = false;
    sheet.querySelector('.hs-presets').hidden = state.kind !== 'week' || !normalizeDisciplines(state.data).length;
    if (state.kind !== 'quote') {
      const fields = stickerFields(state.kind, state.data);
      if (!Array.isArray(state.data.fields)) {
        const defaults = state.kind === 'week' ? ['count', 'durationSec', 'days', 'weekStart', 'sessions', 'daily'] : ['title', 'durationSec', 'distanceM'];
        state.data = { ...state.data, fields: fields.filter((r) => defaults.includes(r.id) || r.id.startsWith('discipline:')).map((r) => r.id) };
      }
      sheet.querySelector('.hs-fields').innerHTML = fields.map((r) => '<label><input type="checkbox" data-field="' + r.id + '"' + (state.data.fields.includes(r.id) ? ' checked' : '') + '><span>' + escHtml(r.label) + '</span></label>').join('');
    }
    sheet.classList.add('open');
    state.bodyOverflow = doc.body.style.overflow;
    doc.body.style.overflow = 'hidden';
    paint().catch((e) => { console.error('HabitShare:', e); say('No se pudieron dibujar los stickers', 'err'); });
  }

  function close() {
    if (!sheet) return;
    sheet.classList.remove('open');
    global.document.body.style.overflow = (state && state.bodyOverflow) || '';
    freeItems();
    const done = state && state.onClose;
    if (state) { state.items = null; state.styles = null; state.onClose = null; }
    seq++;
    if (done) done();
  }

  // El botón que cada app pone junto a lo que se comparte (la frase del día…).
  function chipHtml(label) {
    return '<span class="hs-chip">' + SHARE_ICON + (label || 'Compartir') + '</span>';
  }

  // Lo compartible se marca con data-hs-share; un solo escucha para toda la página, así las
  // apps no necesitan su propio onclick (y HABIT, congelada, casi no cambia).
  if (global.document && global.document.addEventListener) {
    injectCss(global.document);
    global.document.addEventListener('click', (e) => {
      const el = e.target && e.target.closest && e.target.closest('[data-hs-share]');
      if (!el) return;
      open({ kind: el.getAttribute('data-hs-share'), data: { text: el.getAttribute('data-hs-text') || '', ds: el.getAttribute('data-hs-date') || '' } });
    });
  }

  const api = {
    COLORS, PALETTE, WIDTH, LOGO_INK, KINDS, ACTIVITY_TYPES, SHARE_ICON, contrast, inkFor, resolveColor,
    wrapText, balancedWrap, spacedWidth, lockupLayout, quoteLayout, signatureLayout, sealLayout, shortDate,
    dayName, thousands, distanceText, clock, minutesText, paceText, workoutFacts, weekFacts, stylesFor, stickerFields, selectedFields, normalizeDisciplines, selectedDisciplines, compactWeekTime, normalizeWeekSessions, weeklyReferenceLayout, referenceCopy,
    ensureFonts, loadLogo, renderSticker, toBlob, shareImage, open, close, chipHtml
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.HabitShare = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
