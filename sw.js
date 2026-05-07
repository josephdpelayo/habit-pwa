// HABIT Training Hub — Service Worker v2
// Solo maneja push notifications, no intercepta requests

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

// NO fetch handler — no interceptamos nada

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
