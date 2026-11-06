const scope = new URL(self.registration.scope);
const cachePrefix = 'cuadros-pages-shell-';
const cacheName = cachePrefix + 'v1';
const assets = ['', 'index.html', 'style.css', 'app.js', 'manifest.webmanifest', 'icon.svg', 'icon-192.png', 'icon-512.png']
  .map(path => new URL(path, scope).href);

self.addEventListener('install', event => {
  event.waitUntil(caches.open(cacheName).then(cache => cache.addAll(assets)));
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(Promise.all([
    caches.keys().then(keys => Promise.all(keys
      .filter(key => key.startsWith(cachePrefix) && key !== cacheName)
      .map(key => caches.delete(key)))),
    self.clients.claim()
  ]));
});

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== scope.origin || !url.pathname.startsWith(scope.pathname)) return;
  event.respondWith(fetch(event.request).then(response => {
    if (response.ok && assets.includes(url.href)) {
      const copy = response.clone();
      event.waitUntil(caches.open(cacheName).then(cache => cache.put(event.request, copy)));
    }
    return response;
  }).catch(async () => {
    const cache = await caches.open(cacheName);
    return await cache.match(event.request) || (event.request.mode === 'navigate' && await cache.match(scope.href)) ||
      new Response('Abre la aplicación con conexión para consultar tus pagos.', {status: 503});
  }));
});

self.addEventListener('push', event => {
  let notice = {title: 'Cuadros', body: 'Tienes un nuevo aviso', url: './'};
  try { notice = {...notice, ...event.data.json()}; } catch {}
  const icon = new URL('icon-192.png', scope).href;
  event.waitUntil(self.registration.showNotification(notice.title, {
    body: notice.body, icon, badge: icon, tag: notice.tag || 'cuadros', data: {url: notice.url}
  }));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || './', scope);
  const url = new URL(scope);
  if (target.origin === scope.origin) url.search = target.search;
  event.waitUntil(self.clients.matchAll({type: 'window', includeUncontrolled: true}).then(async clients => {
    const client = clients.find(item => item.url.startsWith(scope.href));
    if (client) {
      const destination = await client.navigate(url.href);
      return (destination || client).focus();
    }
    return self.clients.openWindow(url.href);
  }));
});
