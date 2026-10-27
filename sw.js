// HABIT Training Hub — Service Worker
// Push notifications + app shell caching

const CACHE_VERSION = '20261026-4'; // keep in sync with APP_VERSION in app.html
const CACHE = `habit-${CACHE_VERSION}`;

// Librerías compartidas con Skandi Fit: la app no arranca sin ellas, así que
// entran al shell cacheado igual que app.html. Van con ?v= para que la versión
// nueva invalide la vieja.
// Skandi Fit vive en el mismo origen y bajo el mismo alcance ('/'), así que este
// service worker sirve las dos apps: cada una tiene su propio shell offline.
const SHELL = ['/app.html', '/skandi.html', `/skandi-recovery.js?v=${CACHE_VERSION}`, `/skandi-plan.js?v=${CACHE_VERSION}`, `/body-figure.js?v=${CACHE_VERSION}`, `/skandi-nutrition.js?v=${CACHE_VERSION}`, `/skandi-load.js?v=${CACHE_VERSION}`, `/skandi-brief.js?v=${CACHE_VERSION}`, `/skandi-joint-load.js?v=${CACHE_VERSION}`, `/skandi-outbox.js?v=${CACHE_VERSION}`, `/habit-training.js?v=${CACHE_VERSION}`];

// Qué shell le toca a una navegación. Sin esto, abrir /skandi sin señal servía el
// fallback de HABIT: la app equivocada, con la sesión equivocada.
// /competencia (la pantalla de la competencia) también necesita el suyo: la
// navegación guarda lo que baja bajo shellFor(), y sin esta línea abrirla desde
// un teléfono con la app instalada pisaba la copia offline de app.html con el
// marcador. No va en SHELL: sin red no hay marcador que mostrar.
// /crew (HABIT Crew) no es otra página: Vercel la reescribe al mismo app.html, que
// decide la marca por location.pathname. Comparte el shell de HABIT a propósito —
// lo que baja por /crew es byte por byte el mismo archivo—, y la línea está
// explícita para que nadie le agregue un shell propio que se desincronice.
const shellFor = pathname => {
  if (pathname === '/skandi' || pathname.startsWith('/skandi.html')) return '/skandi.html';
  if (pathname === '/competencia' || pathname.startsWith('/competencia.html')) return '/competencia.html';
  if (pathname === '/crew' || pathname.startsWith('/crew/')) return '/app.html';
  return '/app.html';
};

// Vercel contesta /app.html con una redirección a /app (cleanUrls), así que lo
// que se guarda del shell llega marcado como "redirected". Safari se niega a
// entregarle eso a una navegación ("Response served by service worker has
// redirections") y la app instalada en el iPhone se queda en blanco, sin
// siquiera la pantalla de inicio de sesión. Toda respuesta que se guarda o se
// entrega para navegar pasa por aquí y sale limpia.
const clean = res => (res && res.redirected)
  ? res.blob().then(body => new Response(body, { status: res.status, statusText: res.statusText, headers: res.headers }))
  : Promise.resolve(res);

// cache.addAll guardaba la respuesta redirigida tal cual; se baja cada una y se
// guarda la copia limpia. Si una falla, falla la instalación y se queda el
// service worker anterior, igual que con addAll.
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(cache => Promise.all(SHELL.map(path =>
      fetch(path, { cache: 'reload' }).then(res => {
        if (!res.ok) throw new Error(`shell ${path}: ${res.status}`);
        return clean(res).then(copy => cache.put(path, copy));
      })
    )))
  );
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const { request } = e;
  const url = new URL(request.url);

  // Only handle same-origin requests; skip API calls
  if (url.origin !== self.location.origin || url.pathname.startsWith('/api/')) return;

  // Icons y librerías del shell: cache-first (van con URL versionada, así que
  // una entrada vieja caduca sola al subir la versión). skandi-load/brief/joint-load ya
  // estaban en SHELL desde que se escribieron pero nunca entraron aquí, así que siempre
  // salían por red aunque ya estuvieran precacheadas — se corrige de paso, junto con
  // skandi-plan.js, que es el que sí necesitaba esta migración.
  if (url.pathname.startsWith('/icons/')
      || url.pathname === '/skandi-recovery.js'
      || url.pathname === '/skandi-plan.js'
      || url.pathname === '/body-figure.js'
      || url.pathname === '/skandi-nutrition.js'
      || url.pathname === '/skandi-load.js'
      || url.pathname === '/skandi-brief.js'
      || url.pathname === '/skandi-joint-load.js'
      || url.pathname === '/skandi-outbox.js'
      || url.pathname === '/habit-training.js') {
    e.respondWith(
      caches.match(request).then(cached => {
        if (cached) return cached;
        return fetch(request).then(res => {
          caches.open(CACHE).then(c => c.put(request, res.clone()));
          return res;
        });
      })
    );
    return;
  }

  // Navigation: network-first, serve cached shell only when offline.
  // If the network response went through an HTTP redirect (e.g. apex → www),
  // Safari refuses to let a SW hand back a "redirected" Response to respondWith()
  // for a navigation ("Response served by service worker has redirections").
  // clean() strips that flag; Chrome is unaffected. The cached fallback goes
  // through clean() too: it used to be handed back raw, and the copy cache.addAll
  // stored for /app.html is exactly such a redirected response.
  if (request.mode === 'navigate') {
    const shell = shellFor(url.pathname);
    e.respondWith((async () => {
      let res;
      try {
        res = await fetch(request);
      } catch (_) {
        const cached = await caches.match(shell);
        return cached ? clean(cached) : Response.error();
      }
      // Refrescar el shell guardado con lo que acaba de bajar de la red: si no,
      // la copia offline se quedaba congelada en la versión del último install
      // y podía servir HTML viejo durante semanas. Es un extra: antes, si
      // waitUntil fallaba (Safari no siempre lo acepta tan tarde), la página que
      // sí había bajado se cambiaba por la copia guardada. Ahora la red se
      // entrega pase lo que pase con la copia.
      if (res.ok && res.type === 'basic') {
        const save = clean(res.clone())
          .then(copy => caches.open(CACHE).then(c => c.put(shell, copy)))
          .catch(() => {});
        try { e.waitUntil(save); } catch (_) { /* la copia se guarda igual, solo sin alargar la vida del worker */ }
      }
      try { return await clean(res); } catch (_) { return res; }
    })());
  }
});

self.addEventListener('push', e => {
  if (!e.data) return;
  let payload;
  try { payload = e.data.json(); }
  catch { payload = { title: 'HABIT', body: e.data.text() }; }

  const { title = 'HABIT Training Hub', body = '', icon, tag } = payload;

  e.waitUntil(self.registration.showNotification(title, {
    body,
    icon: icon || '/icons/logo-original.png',
    badge: '/icons/logo-original.png',
    tag: tag || 'habit',
    renotify: true,
    vibrate: [200, 100, 200],
    data: payload
  }));
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clients => {
      const c = clients.find(c => c.url.includes(self.location.origin));
      if (c) return c.focus();
      return self.clients.openWindow('/app.html');
    })
  );
});
