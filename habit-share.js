// HABIT Share — stickers para historias de Instagram (docs/HISTORIAS_INSTAGRAM.md).
//
// Un sticker es un PNG con fondo transparente, dibujado a mano en un canvas: tocarlo lo copia y
// en Instagram se pega encima de tu foto; mantenerlo lo guarda (el menú nativo de la imagen).
// Blanco o negro, nada más. La marca es la de la app: el logo de /icons/logo-original.png (no un
// anillo dibujado) y la palabra HABIT en Inter 800 espaciada, como en el encabezado.
//
// La disposición (qué renglones, de qué tamaño, dónde) es pura y se prueba en Node
// (scripts/check-share.js): recibe `measure(texto, font)` en lugar de un canvas. El dibujo y el
// portapapeles son solo del navegador.
(function (global) {
  'use strict';

  const COLORS = { blanco: '#ffffff', negro: '#0b0b0b' };
  const WIDTH = 1080;          // ancho de una historia: el sticker sale nítido a cualquier escala
  const PAD = 72;
  const INTER = '"Inter", -apple-system, system-ui, sans-serif';
  const LOGO_SRC = '/icons/logo-original.png';

  const quoteFont = (px) => `600 ${px}px ${INTER}`;
  const wordFont = (px) => `800 ${px}px ${INTER}`;
  const subFont = (px) => `600 ${px}px ${INTER}`;

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

  // El logotipo de HABIT: el logo y la palabra HABIT a su derecha, centrados en `cx`. Mismas
  // proporciones que el encabezado de la app (logo ≈ 1.75× la altura de la letra, espaciado .1em).
  function lockupLayout(cx, top, wordPx, measure) {
    const spacing = Math.round(wordPx * 0.1);
    const logo = Math.round(wordPx * 1.75);
    const gap = Math.round(wordPx * 0.45);
    const wordW = spacedWidth('HABIT', spacing, (c) => measure(c, wordFont(wordPx)));
    const width = logo + gap + wordW;
    const x0 = cx - width / 2;
    return {
      width, height: logo,
      logo: { x: x0, y: top, size: logo },
      word: { text: 'HABIT', font: wordFont(wordPx), spacing, x: x0 + logo + gap, y: top + logo / 2 + wordPx * 0.36 }
    };
  }

  // Frase del día: la frase en Inter, centrada y en renglones parejos; debajo el logotipo.
  // Una frase larga baja de tamaño en lugar de pasar de cinco renglones.
  function quoteLayout(text, measure) {
    const quote = '“' + String(text || '').trim() + '”';
    const inner = WIDTH - PAD * 2;
    // Los renglones siempre se calculan con el tamaño que se queda: si ninguno baja de cinco
    // renglones (una frase larguísima), se usa el más chico con sus propios renglones.
    const SIZES = [76, 70, 64, 58, 52, 46, 40];
    let size = SIZES[0], lines = [];
    for (const px of SIZES) {
      size = px;
      lines = balancedWrap(quote, inner, (s) => measure(s, quoteFont(px)));
      if (lines.length <= 5) break;
    }
    const lineH = Math.round(size * 1.22);
    const top = PAD;
    const textBottom = top + lineH * lines.length;
    const lockup = lockupLayout(WIDTH / 2, textBottom + 56, 30, measure);
    return {
      kind: 'quote', width: WIDTH,
      height: Math.round(lockup.logo.y + lockup.height + PAD),
      font: quoteFont(size), size, lineH,
      lines: lines.map((t, i) => ({ text: t, x: WIDTH / 2, y: top + lineH * i + size })),
      lockup
    };
  }

  // La firma: el logotipo de HABIT en grande y MAKE IT A HABIT debajo.
  function signatureLayout(measure) {
    const wordPx = 112;
    const lockup = lockupLayout(0, PAD, wordPx, measure);
    const width = Math.ceil(lockup.width + PAD * 2);
    const cx = width / 2;
    const placed = lockupLayout(cx, PAD, wordPx, measure);
    const subPx = 30, subSpacing = Math.round(subPx * 0.22);
    const subText = 'MAKE IT A HABIT';
    const subW = spacedWidth(subText, subSpacing, (c) => measure(c, subFont(subPx)));
    const subY = placed.logo.y + placed.height + 44 + subPx;
    return {
      kind: 'signature', width, height: Math.ceil(subY + PAD * 0.8),
      lockup: placed,
      sub: { text: subText, font: subFont(subPx), spacing: subSpacing, x: cx - subW / 2, y: subY }
    };
  }

  // ── Navegador ──────────────────────────────────────────────────────────

  let fontsReady = null;
  // Inter ya la carga la app (Google Fonts, 300–800), pero puede no haber terminado: sin esperar,
  // el canvas dibuja con la fuente del sistema y no avisa.
  function ensureFonts(doc) {
    if (fontsReady) return fontsReady;
    doc = doc || global.document;
    const wanted = [quoteFont(76), wordFont(112), subFont(30)];
    const load = doc.fonts && doc.fonts.load
      ? Promise.all(wanted.map((f) => doc.fonts.load(f, 'HABIT“”áé')))
      : Promise.resolve();
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

  function canvasMeasure(ctx) {
    return (text, font) => { ctx.font = font; return ctx.measureText(text).width; };
  }

  // El logo viene blanco; para el sticker negro se tiñe en un lienzo aparte (source-in pinta
  // solo donde el logo tiene tinta, y conserva sus bordes suaves).
  function drawLogo(ctx, img, box, color, doc) {
    if (color === COLORS.blanco) { ctx.drawImage(img, box.x, box.y, box.size, box.size); return; }
    const off = newCanvas(doc, box.size, box.size);
    const o = off.getContext('2d');
    o.drawImage(img, 0, 0, box.size, box.size);
    o.globalCompositeOperation = 'source-in';
    o.fillStyle = color; o.fillRect(0, 0, box.size, box.size);
    ctx.drawImage(off, box.x, box.y);
  }

  function drawLockup(ctx, L, img, color, doc) {
    drawLogo(ctx, img, L.logo, color, doc);
    ctx.font = L.word.font; ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
    drawSpaced(ctx, L.word.text, L.word.x, L.word.y, L.word.spacing);
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

  // Cada render devuelve un canvas transparente del tamaño justo del sticker. `logo` es la
  // imagen ya cargada (loadLogo): dibujar no espera nada.
  function renderQuote(doc, text, colorKey, logo) {
    const color = COLORS[colorKey] || COLORS.blanco;
    const probe = newCanvas(doc, 1, 1).getContext('2d');
    const L = quoteLayout(text, canvasMeasure(probe));
    const canvas = newCanvas(doc, L.width, L.height);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = color; ctx.textBaseline = 'alphabetic';
    ctx.font = L.font; ctx.textAlign = 'center';
    L.lines.forEach((l) => ctx.fillText(l.text, l.x, l.y));
    drawLockup(ctx, L.lockup, logo, color, doc);
    return canvas;
  }

  function renderSignature(doc, colorKey, logo) {
    const color = COLORS[colorKey] || COLORS.blanco;
    const probe = newCanvas(doc, 1, 1).getContext('2d');
    const L = signatureLayout(canvasMeasure(probe));
    const canvas = newCanvas(doc, L.width, L.height);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = color;
    drawLockup(ctx, L.lockup, logo, color, doc);
    ctx.font = L.sub.font; ctx.textAlign = 'left';
    drawSpaced(ctx, L.sub.text, L.sub.x, L.sub.y, L.sub.spacing);
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
    wrapText, balancedWrap, spacedWidth, lockupLayout, quoteLayout, signatureLayout,
    ensureFonts, loadLogo, renderQuote, renderSignature, toBlob, copyOrShare, shareImage
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.HabitShare = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
