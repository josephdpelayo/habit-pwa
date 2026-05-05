// HABIT Training Hub — Service Worker v67
// Strategy: Network first for app.html, cache only for icons/fonts

const CACHE = 'habit-static-v67';
const STATIC = [
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/icons/icon-180.png',
  '/manifest.json'
];

// Install: cache only static assets, NOT app.html
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(cache => cache.addAll(STATIC).catch(()=>{}))
      .then(() => self.skipWaiting())
  );
});

// Activate: delete all old caches immediately
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// Fetch: ALWAYS network for app.html — never serve from cache
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  
  // Skip non-GET
  if (e.request.method !== 'GET') return;
  
  // NEVER cache app.html — always fresh from network
  if (url.pathname === '/app.html' || url.pathname === '/' || url.pathname === '') {
    e.respondWith(
      fetch(e.request, {cache: 'no-store'})
        .catch(() => caches.match('/app.html'))
    );
    return;
  }
  
  // Cache-first for icons and manifest
  if (url.pathname.startsWith('/icons/') || url.pathname === '/manifest.json') {
    e.respondWith(
      caches.match(e.request)
        .then(cached => cached || fetch(e.request)
          .then(res => {
            if(res.ok){
              const clone=res.clone();
              caches.open(CACHE).then(c=>c.put(e.request,clone));
            }
            return res;
          })
        )
    );
    return;
  }
  
  // Everything else: network first
  e.respondWith(
    fetch(e.request, {cache: 'no-store'}).catch(() => caches.match(e.request))
  );
});
