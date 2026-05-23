// HABIT Training Hub — Service Worker
// Push notifications + app shell caching

const CACHE_VERSION = '20260523-02'; // keep in sync with APP_VERSION in app.html
const CACHE = `habit-${CACHE_VERSION}`;

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(cache => cache.add('/app.html'))
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

  // Icons: cache-first (served with versioned URLs so stale entries auto-expire on update)
  if (url.pathname.startsWith('/icons/')) {
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
  // We pass the original request through (Vercel rewrites handle it server-side without
  // a redirect), so Chrome never sees a redirected response from the SW.
  if (request.mode === 'navigate') {
    e.respondWith(
      fetch(request).catch(() => caches.match('/app.html'))
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
