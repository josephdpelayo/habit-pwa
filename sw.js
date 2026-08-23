// HABIT Training Hub — Service Worker
// Push notifications + app shell caching

const CACHE_VERSION = '20260822-15'; // keep in sync with APP_VERSION in app.html
const CACHE = `habit-${CACHE_VERSION}`;

// Librerías compartidas con Skandi Fit: la app no arranca sin ellas, así que
// entran al shell cacheado igual que app.html. Van con ?v= para que la versión
// nueva invalide la vieja.
// Skandi Fit vive en el mismo origen y bajo el mismo alcance ('/'), así que este
// service worker sirve las dos apps: cada una tiene su propio shell offline.
const SHELL = ['/app.html', '/skandi.html', `/skandi-recovery.js?v=${CACHE_VERSION}`, `/body-figure.js?v=${CACHE_VERSION}`, `/skandi-nutrition.js?v=${CACHE_VERSION}`];

// Qué shell le toca a una navegación. Sin esto, abrir /skandi sin señal servía el
// fallback de HABIT: la app equivocada, con la sesión equivocada.
const shellFor = pathname => (pathname === '/skandi' || pathname.startsWith('/skandi.html')) ? '/skandi.html' : '/app.html';

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(SHELL))
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
  // una entrada vieja caduca sola al subir la versión)
  if (url.pathname.startsWith('/icons/')
      || url.pathname === '/skandi-recovery.js'
      || url.pathname === '/body-figure.js'
      || url.pathname === '/skandi-nutrition.js') {
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
  // Rebuilding a plain Response from the body strips that flag; Chrome is unaffected.
  if (request.mode === 'navigate') {
    const shell = shellFor(url.pathname);
    e.respondWith(
      fetch(request).then(res => {
        // Refrescar el shell guardado con lo que acaba de bajar de la red: si no,
        // la copia offline se quedaba congelada en la versión del último install
        // y podía servir HTML viejo durante semanas.
        if (res.ok && res.type === 'basic') {
          const copy = res.clone();
          e.waitUntil(caches.open(CACHE).then(c => c.put(shell, copy)));
        }
        if (!res.redirected) return res;
        return res.blob().then(body => new Response(body, {
          status: res.status,
          statusText: res.statusText,
          headers: res.headers,
        }));
      }).catch(() => caches.match(shell))
    );
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
