// HABIT Training Hub — Service Worker
// Caches the app shell for offline use

const CACHE = 'habit-v24';
const ASSETS = [
  '/app.html',
  '/manifest.json',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/icons/icon-180.png',
  'https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@400;600;700;800&family=Barlow:wght@300;400;500;600&display=swap',
  'https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js'
];

// Install: cache all assets
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(cache => {
      // Cache local assets immediately, external ones best-effort
      return cache.addAll(['/app.html', '/manifest.json', '/icons/icon-192.png'])
        .then(() => cache.addAll(ASSETS.filter(u => u.startsWith('http'))).catch(() => {}));
    }).then(() => self.skipWaiting())
  );
});

// Activate: remove old caches
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Fetch: cache-first for local, network-first for external
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  
  // Always network for non-GET
  if (e.request.method !== 'GET') return;
  
  // Cache-first for local assets
  if (url.origin === location.origin) {
    e.respondWith(
      caches.match(e.request).then(cached => {
        if (cached) return cached;
        return fetch(e.request).then(res => {
          if (res.ok) {
            const clone = res.clone();
            caches.open(CACHE).then(cache => cache.put(e.request, clone));
          }
          return res;
        }).catch(() => caches.match('/app.html'));
      })
    );
    return;
  }
  
  // Network-first for fonts and CDN
  if (url.hostname.includes('googleapis') || url.hostname.includes('cloudflare')) {
    e.respondWith(
      fetch(e.request).then(res => {
        if (res.ok) {
          const clone = res.clone();
          caches.open(CACHE).then(cache => cache.put(e.request, clone));
        }
        return res;
      }).catch(() => caches.match(e.request))
    );
  }
});

// Push notifications (for future backend integration)
self.addEventListener('push', e => {
  if (!e.data) return;
  const data = e.data.json();
  e.waitUntil(
    self.registration.showNotification(data.title || 'HABIT', {
      body: data.body || '',
      icon: '/icons/icon-192.png',
      badge: '/icons/icon-32.png',
      vibrate: [200, 100, 200],
      data: data
    })
  );
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(clients.openWindow('/app.html'));
});
