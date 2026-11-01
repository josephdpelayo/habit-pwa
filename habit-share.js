// HABIT Share — stickers para historias de Instagram (docs/HISTORIAS_INSTAGRAM.md).
//
// Lo usan las dos apps, HABIT (app.html, congelada) y HABIT Crew (crew.html), y por eso TODO vive
// aquí: el dibujo, la galería (la hoja, su CSS) y compartir. Una app solo carga este archivo y
// marca lo que se puede compartir:
//
//   <section data-hs-share="quote" data-hs-text="…" data-hs-date="2026-10-31"> … </section>
//
// Tocar ese elemento abre la galería con los estilos de ese tipo. Cada sticker es un PNG
// transparente, blanco o negro, con la fuente de HABIT (Inter) y su logo original
// (/icons/logo-original.png); cada uno trae su botón Compartir, que abre la hoja del teléfono
// (Instagram, WhatsApp, Guardar imagen, Copiar).
//
// La disposición de cada estilo es pura y se prueba en Node (scripts/check-share.js): recibe
// `measure(texto, font)` en lugar de un canvas. El dibujo y la hoja son solo del navegador.
(function (global) {
  'use strict';

  const COLORS = { blanco: '#ffffff', negro: '#0b0b0b' };
  const WIDTH = 1080;          // ancho de una historia: el sticker sale nítido a cualquier escala
  const PAD = 72;
  const INTER = '"Inter", -apple-system, system-ui, sans-serif';
  const LOGO_SRC = '/icons/logo-original.png';
  const COLOR_KEY = 'habit_sticker_color';

  const quoteFont = (px) => `600 ${px}px ${INTER}`;
  const wordFont = (px) => `800 ${px}px ${INTER}`;
  const subFont = (px) => `600 ${px}px ${INTER}`;
  const sealFont = (px) => `700 ${px}px ${INTER}`;

  // ── Disposición (pura) ─────────────────────────────────────────────────

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

  // Estilo «Frase»: la frase centrada y en renglones parejos; debajo el logotipo chico. Una
  // frase larga baja de tamaño en lugar de pasar de cinco renglones.
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
    const probe = lockupLayout(0, PAD, wordPx, measure);
    const width = Math.ceil(probe.width + PAD * 2);
    const cx = width / 2;
    const lockup = lockupLayout(cx, PAD, wordPx, measure);
    const subPx = 30, subSpacing = Math.round(subPx * 0.22);
    const text = String(subText || 'MAKE IT A HABIT').toUpperCase();
    const subW = spacedWidth(text, subSpacing, (c) => measure(c, subFont(subPx)));
    const subY = lockup.logo.y + lockup.height + 44 + subPx;
    return {
      kind: 'logotipo', width, height: Math.ceil(subY + PAD * 0.8),
      lockup,
      sub: { text, font: subFont(subPx), spacing: subSpacing, x: cx - subW / 2, y: subY }
    };
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
    const circumference = 2 * Math.PI * radius;
    const widths = [...body].map((c) => measure(c, sealFont(px)));
    const total = widths.reduce((a, b) => a + b, 0);
    const spacing = (circumference - total) / widths.length;
    let along = 0;
    const chars = [...body].map((ch, i) => {
      const mid = along + widths[i] / 2;
      along += widths[i] + spacing;
      return { ch, angle: (mid / circumference) * Math.PI * 2 };
    });
    const logo = Math.round(radius * 0.95);
    return {
      kind: 'sello', width: size, height: size, cx, cy, radius,
      font: sealFont(px), size: px, spacing, chars,
      logo: { x: cx - logo / 2, y: cy - logo / 2, size: logo }
    };
  }

  // 31.10.26, para el sello.
  function shortDate(ds) {
    const m = String(ds || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
    return m ? `${m[3]}.${m[2]}.${m[1].slice(2)}` : '';
  }

  // Los estilos de cada tipo, en el orden en que salen en la galería.
  const KINDS = {
    quote: {
      title: 'Frase del día',
      styles: [
        { id: 'frase', label: 'Frase', layout: (d, m) => quoteLayout(d.text, m) },
        { id: 'logotipo', label: 'Logotipo', layout: (d, m) => signatureLayout(m, 'MAKE IT A HABIT') },
        { id: 'sello', label: 'Sello', layout: (d, m) => sealLayout('MAKE IT A HABIT · ' + (shortDate(d.ds) ? shortDate(d.ds) + ' · ' : ''), m) }
      ]
    }
  };

  // ── Dibujo (navegador) ─────────────────────────────────────────────────

  let fontsReady = null;
  // Inter ya la carga cada app (Google Fonts), pero puede no haber terminado: sin esperar, el
  // canvas dibuja con la fuente del sistema y no avisa.
  function ensureFonts(doc) {
    if (fontsReady) return fontsReady;
    doc = doc || global.document;
    const wanted = [quoteFont(76), wordFont(112), subFont(30), sealFont(66)];
    const load = doc.fonts && doc.fonts.load
      ? Promise.all(wanted.map((f) => doc.fonts.load(f, 'HABIT“”áé·')))
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

  function newCanvas(doc, w, h) {
    const c = (doc || global.document).createElement('canvas');
    c.width = Math.ceil(w); c.height = Math.ceil(h);
    return c;
  }

  function canvasMeasure(ctx) {
    return (text, font) => { ctx.font = font; return ctx.measureText(text).width; };
  }

  function drawSpaced(ctx, text, x, y, spacing) {
    let cx = x;
    [...text].forEach((c) => { ctx.fillText(c, cx, y); cx += ctx.measureText(c).width + spacing; });
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

  // Un sticker: un canvas transparente del tamaño justo. `logo` es la imagen ya cargada.
  function renderSticker(doc, kind, styleId, data, colorKey, logo) {
    const style = (KINDS[kind] || KINDS.quote).styles.find((s) => s.id === styleId);
    if (!style) throw new Error('Estilo desconocido: ' + styleId);
    const color = COLORS[colorKey] || COLORS.blanco;
    const probe = newCanvas(doc, 1, 1).getContext('2d');
    const L = style.layout(data || {}, canvasMeasure(probe));
    const canvas = newCanvas(doc, L.width, L.height);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = color;
    DRAW[style.id](ctx, L, logo, color, doc);
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
  const CSS = `
.hs-overlay{position:fixed;inset:0;z-index:10040;background:rgba(6,7,9,.66);display:none;align-items:flex-end;justify-content:center;font-family:${INTER}}
.hs-overlay.open{display:flex;animation:hsFade .18s ease both}
.hs-sheet{width:100%;max-width:480px;max-height:90vh;background:#141518;color:#f4f5f7;border-radius:22px 22px 0 0;display:flex;flex-direction:column;overflow:hidden;animation:hsUp .3s cubic-bezier(.2,.8,.2,1) both;padding-bottom:env(safe-area-inset-bottom,0px)}
.hs-head{display:flex;align-items:center;gap:12px;padding:16px 16px 12px}
.hs-title{flex:1;text-align:center;font-size:17px;font-weight:700;margin:0;letter-spacing:0}
.hs-close{background:none;border:0;color:#9aa0aa;font-size:24px;line-height:1;cursor:pointer;padding:4px 6px}
.hs-colors{display:flex;gap:10px}
.hs-color{width:24px;height:24px;border-radius:50%;border:1px solid rgba(255,255,255,.28);padding:0;cursor:pointer}
.hs-color[data-c=blanco]{background:#fff}.hs-color[data-c=negro]{background:#0b0b0b}
.hs-color.on{outline:2px solid #fff;outline-offset:3px}
.hs-body{overflow-y:auto;padding:4px 16px 20px;overscroll-behavior:contain}
.hs-hint{text-align:center;font-size:13px;color:#9aa0aa;margin:0 0 14px}
.hs-grid{display:grid;gap:12px}
.hs-tile{background:#1f2024;border-radius:18px;padding:22px 18px 14px;display:flex;flex-direction:column;align-items:center;gap:14px}
.hs-tile.light{background:#d9dbe0}
.hs-tile img{display:block;max-width:100%;max-height:260px}
.hs-row{width:100%;display:flex;align-items:center;justify-content:space-between}
.hs-label{font-size:12px;color:#7d828c;font-weight:600;letter-spacing:.04em}
.hs-tile.light .hs-label{color:#5a5e66}
.hs-share{display:inline-flex;align-items:center;gap:7px;border:0;border-radius:999px;background:#fff;color:#0b0b0b;font:600 14px ${INTER};padding:9px 16px 9px 13px;cursor:pointer}
.hs-tile.light .hs-share{background:#0b0b0b;color:#fff}
.hs-share svg,.hs-chip svg{width:17px;height:17px;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
.hs-share:active{transform:scale(.97)}
.hs-wait{padding:40px 0;text-align:center;color:#9aa0aa;font-size:13px}
.hs-chip{display:inline-flex;align-items:center;gap:6px;color:inherit;font-weight:600;cursor:pointer}
.hs-chip-row{position:relative;z-index:1;display:flex;justify-content:center;margin-top:12px;font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#d7dae0}
[data-hs-share]{cursor:pointer}
@keyframes hsFade{from{opacity:0}to{opacity:1}}
@keyframes hsUp{from{transform:translateY(40px);opacity:.4}to{transform:none;opacity:1}}
@media (prefers-reduced-motion:reduce){.hs-overlay.open,.hs-sheet{animation:none}}`;

  let sheet = null, state = null, seq = 0;

  function readColor() {
    try { const c = global.localStorage.getItem(COLOR_KEY); return c === 'negro' ? 'negro' : 'blanco'; } catch (_) { return 'blanco'; }
  }
  function saveColor(c) { try { global.localStorage.setItem(COLOR_KEY, c); } catch (_) { /* sin almacenamiento: no pasa nada */ } }
  function say(msg, type) { if (typeof global.toast === 'function') global.toast(msg, type); }

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
      + '<div class="hs-head"><div class="hs-colors" role="radiogroup" aria-label="Color del sticker">'
      + '<button type="button" class="hs-color" data-c="blanco" aria-label="Blanco"></button>'
      + '<button type="button" class="hs-color" data-c="negro" aria-label="Negro"></button></div>'
      + '<h2 class="hs-title" id="hs-title"></h2>'
      + '<button type="button" class="hs-close" aria-label="Cerrar">×</button></div>'
      + '<div class="hs-body"><p class="hs-hint">Compártelo en tu historia de Instagram: el fondo es transparente, va encima de tu foto.</p>'
      + '<div class="hs-grid"></div></div></div>';
    doc.body.appendChild(el);
    el.addEventListener('click', (e) => {
      if (e.target === el || e.target.closest('.hs-close')) { close(); return; }
      const c = e.target.closest('.hs-color');
      if (c) { state.color = c.dataset.c; saveColor(state.color); paint(); return; }
      const b = e.target.closest('.hs-share');
      if (b) shareTile(Number(b.dataset.i));
    });
    doc.addEventListener('keydown', (e) => { if (e.key === 'Escape' && el.classList.contains('open')) close(); });
    sheet = el;
    return el;
  }

  function freeItems() {
    if (state && state.items) state.items.forEach((it) => it && URL.revokeObjectURL(it.url));
  }

  // Dibuja todos los estilos antes de mostrarlos: así el botón Compartir entrega una imagen que
  // ya existe, y el iPhone no pierde el toque esperando.
  async function paint() {
    const doc = global.document;
    const my = ++seq;
    const kind = KINDS[state.kind] || KINDS.quote;
    sheet.querySelector('.hs-title').textContent = kind.title;
    sheet.querySelectorAll('.hs-color').forEach((b) => b.classList.toggle('on', b.dataset.c === state.color));
    const grid = sheet.querySelector('.hs-grid');
    if (!state.items) grid.innerHTML = '<div class="hs-wait">Preparando stickers…</div>';
    let logo;
    try { [, logo] = await Promise.all([ensureFonts(doc), loadLogo()]); }
    catch (e) { grid.innerHTML = '<div class="hs-wait">No se pudo cargar el logo. Revisa tu conexión.</div>'; return; }
    const items = [];
    for (const s of kind.styles) {
      const blob = await toBlob(renderSticker(doc, state.kind, s.id, state.data, state.color, logo));
      items.push({ blob, url: URL.createObjectURL(blob), label: s.label, name: `habit-${s.id}-${state.color}.png` });
    }
    if (my !== seq) { items.forEach((it) => URL.revokeObjectURL(it.url)); return; } // cambiaron el color a media pintura
    freeItems();
    state.items = items;
    const light = state.color === 'negro';
    grid.innerHTML = items.map((it, i) => '<div class="hs-tile' + (light ? ' light' : '') + '">'
      + '<img src="' + it.url + '" alt="Sticker ' + it.label + '">'
      + '<div class="hs-row"><span class="hs-label">' + it.label + '</span>'
      + '<button type="button" class="hs-share" data-i="' + i + '">' + SHARE_ICON + 'Compartir</button></div></div>').join('');
  }

  async function shareTile(i) {
    const it = state && state.items && state.items[i];
    if (!it) return;
    const how = await shareImage(it.blob, it.name);
    if (how === 'downloaded') say('Imagen guardada', 'ok');
  }

  // Abre la galería. kind: 'quote' (por ahora). data: { text, ds }.
  function open(opts) {
    const doc = global.document;
    buildSheet(doc);
    freeItems();
    state = { kind: (opts && opts.kind) || 'quote', data: (opts && opts.data) || {}, color: readColor(), items: null };
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
    if (state) state.items = null;
    seq++;
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
    COLORS, WIDTH, KINDS,
    wrapText, balancedWrap, spacedWidth, lockupLayout, quoteLayout, signatureLayout, sealLayout, shortDate,
    ensureFonts, loadLogo, renderSticker, toBlob, shareImage, open, close, chipHtml
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  global.HabitShare = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
