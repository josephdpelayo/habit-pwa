// HABIT Share — stickers para historias de Instagram (docs/HISTORIAS_INSTAGRAM.md).
//
// Un sticker es un PNG con fondo transparente, dibujado a mano en un canvas: tocarlo lo copia y
// en Instagram se pega encima de tu foto; mantenerlo lo guarda (el menú nativo de la imagen).
// Blanco o negro, nada más.
//
// La disposición (qué renglones, de qué tamaño, dónde) es pura y se prueba en Node
// (scripts/check-share.js): recibe `measure(texto, font)` en lugar de un canvas. El dibujo y el
// portapapeles son solo del navegador.
(function (global) {
  'use strict';

  const COLORS = { blanco: '#ffffff', negro: '#0b0b0b' };
  const WIDTH = 1080;          // ancho de una historia: el sticker sale nítido a cualquier escala
  const PAD = 72;
  const SERIF = '"Instrument Serif", Georgia, serif';
  const BRAND = '"Space Grotesk", "Inter", system-ui, sans-serif';
  const FONT_CSS = 'https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&display=swap';

  const serifFont = (px) => `italic 400 ${px}px ${SERIF}`;
  const brandFont = (px) => `500 ${px}px ${BRAND}`;

  // Renglones de a lo más `maxWidth`, palabra por palabra.
  function wrapText(text, maxWidth, measure) {
    const words = String(text || '').trim().split(/\s+/).filter(Boolean);
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

  // Frase del día: la frase en serif itálica, centrada y pareja; debajo el anillo y
  // MAKE IT A HABIT. Una frase larga baja de tamaño en lugar de pasar de cinco renglones.
  function quoteLayout(text, measure) {
    const quote = '“' + String(text || '').trim() + '”';
    const inner = WIDTH - PAD * 2;
    // Los renglones siempre se calculan con el tamaño que se queda: si ninguno baja de cinco
    // renglones (una frase larguísima), se usa el más chico con sus propios renglones.
    const SIZES = [92, 84, 76, 68, 60, 54, 48];
    let size = SIZES[0], lines = [];
    for (const px of SIZES) {
      size = px;
      lines = balancedWrap(quote, inner, (s) => measure(s, serifFont(px)));
      if (lines.length <= 5) break;
    }
    const lineH = Math.round(size * 1.16);
    const sigSize = 30, sigSpacing = Math.round(sigSize * 0.16), ringR = 15;
    const sigText = 'MAKE IT A HABIT';
    const sigTextW = spacedWidth(sigText, sigSpacing, (c) => measure(c, brandFont(sigSize)));
    const sigW = ringR * 2 + 18 + sigTextW;
    const top = PAD;
    const textBottom = top + lineH * lines.length;
    const sigY = textBottom + 64;
    return {
      kind: 'quote',
      width: WIDTH,
      height: Math.round(sigY + ringR * 2 + PAD),
      font: serifFont(size), size, lineH,
      lines: lines.map((t, i) => ({ text: t, x: WIDTH / 2, y: top + lineH * i + size })),
      sig: {
        text: sigText, font: brandFont(sigSize), spacing: sigSpacing,
        ring: { cx: (WIDTH - sigW) / 2 + ringR, cy: sigY + ringR, r: ringR, line: 7 },
        textX: (WIDTH - sigW) / 2 + ringR * 2 + 18, textY: sigY + ringR + sigSize * 0.36
      }
    };
  }

  // La firma: el anillo y «Make it a habit.» en serif itálica, en una línea.
  function signatureLayout(measure) {
    const text = 'Make it a habit.';
    const size = 120, ringR = 44, gap = 34;
    const textW = measure(text, serifFont(size));
    const width = Math.ceil(PAD + ringR * 2 + gap + textW + PAD);
    const height = Math.ceil(PAD + size * 1.2 + PAD * 0.6);
    const cy = height / 2;
    return {
      kind: 'signature', width, height,
      ring: { cx: PAD + ringR, cy, r: ringR, line: 20 },
      text, font: serifFont(size), textX: PAD + ringR * 2 + gap, textY: cy + size * 0.32
    };
  }

  // ── Navegador ──────────────────────────────────────────────────────────

  let fontsReady = null;
  // Instrument Serif solo se baja al abrir los stickers, no al abrir la app. Sin esperar a que
  // cargue, el canvas dibuja con la fuente del sistema y no avisa.
  function ensureFonts(doc) {
    if (fontsReady) return fontsReady;
    doc = doc || global.document;
    // Primero la hoja de estilos: pedir la fuente antes de que la hoja la declare resuelve al
    // instante sin bajar nada, y el sticker sale con Georgia.
    let link = doc.querySelector('link[data-habit-share-fonts]');
    const cssReady = new Promise((resolve) => {
      if (link && link.sheet) return resolve();
      if (!link) {
        link = doc.createElement('link');
        link.rel = 'stylesheet'; link.href = FONT_CSS; link.setAttribute('data-habit-share-fonts', '1');
        doc.head.appendChild(link);
      }
      link.addEventListener('load', () => resolve(), { once: true });
      link.addEventListener('error', () => resolve(), { once: true });
    });
    const wanted = [serifFont(92), brandFont(30)];
    const load = cssReady.then(() => (doc.fonts && doc.fonts.load
      ? Promise.all(wanted.map((f) => doc.fonts.load(f, 'Aa“”áé')))
      : null));
    const timeout = new Promise((r) => setTimeout(r, 3500));
    fontsReady = Promise.race([load, timeout]).catch(() => {}).then(() => true);
    return fontsReady;
  }

  function canvasMeasure(ctx) {
    return (text, font) => { ctx.font = font; return ctx.measureText(text).width; };
  }

  function drawRing(ctx, ring, color) {
    ctx.beginPath();
    ctx.arc(ring.cx, ring.cy, ring.r - ring.line / 2, 0, Math.PI * 2);
    ctx.strokeStyle = color; ctx.lineWidth = ring.line; ctx.stroke();
  }

  function drawSpaced(ctx, text, x, y, spacing) {
    let cx = x;
    [...text].forEach((c) => { ctx.fillText(c, cx, y); cx += ctx.measureText(c).width + spacing; });
  }

  function newCanvas(doc, w, h) {
    const c = (doc || global.document).createElement('canvas');
    c.width = Math.ceil(w); c.height = Math.ceil(h);
    return c;
  }

  // Cada render devuelve un canvas transparente del tamaño justo del sticker.
  function renderQuote(doc, text, colorKey) {
    const color = COLORS[colorKey] || COLORS.blanco;
    const probe = newCanvas(doc, 1, 1).getContext('2d');
    const L = quoteLayout(text, canvasMeasure(probe));
    const canvas = newCanvas(doc, L.width, L.height);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = color; ctx.textBaseline = 'alphabetic';
    ctx.font = L.font; ctx.textAlign = 'center';
    L.lines.forEach((l) => ctx.fillText(l.text, l.x, l.y));
    drawRing(ctx, L.sig.ring, color);
    ctx.font = L.sig.font; ctx.textAlign = 'left';
    drawSpaced(ctx, L.sig.text, L.sig.textX, L.sig.textY, L.sig.spacing);
    return canvas;
  }

  function renderSignature(doc, colorKey) {
    const color = COLORS[colorKey] || COLORS.blanco;
    const probe = newCanvas(doc, 1, 1).getContext('2d');
    const L = signatureLayout(canvasMeasure(probe));
    const canvas = newCanvas(doc, L.width, L.height);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = color;
    drawRing(ctx, L.ring, color);
    ctx.font = L.font; ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
    ctx.fillText(L.text, L.textX, L.textY);
    return canvas;
  }

  function toBlob(canvas) {
    return new Promise((resolve, reject) => {
      canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('No se pudo crear la imagen'))), 'image/png');
    });
  }

  // Copiar tiene que llamarse en el mismo toque: Safari pierde el permiso si antes se espera
  // algo. Por eso ClipboardItem recibe la promesa del PNG y no el PNG ya resuelto.
  // Devuelve 'copied', 'shared', 'downloaded' o 'cancelled'.
  async function copyOrShare(blobPromise, filename) {
    const nav = global.navigator || {};
    if (nav.clipboard && nav.clipboard.write && typeof global.ClipboardItem === 'function') {
      try {
        await nav.clipboard.write([new global.ClipboardItem({ 'image/png': blobPromise })]);
        return 'copied';
      } catch (_) { /* sin permiso de portapapeles: se comparte */ }
    }
    return shareImage(await blobPromise, filename);
  }

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

  const api = {
    COLORS, WIDTH,
    wrapText, balancedWrap, spacedWidth, quoteLayout, signatureLayout,
    ensureFonts, renderQuote, renderSignature, toBlob, copyOrShare, shareImage
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.HabitShare = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
