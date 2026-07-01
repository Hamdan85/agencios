const CACHE = 'agencios-v2'
const PRECACHE_URLS = ['/offline.html', '/errors/base.css', '/errors/dino.js', '/branding/mark.svg']

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.addAll(PRECACHE_URLS))
      .then(() => self.skipWaiting()),
  )
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    Promise.all([
      self.clients.claim(),
      caches.keys().then((keys) =>
        Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))),
      ),
    ]),
  )
})

// A fetch handler is required for Chrome to offer the install prompt. Keep it
// minimal: never touch the API, cache hashed static assets, and fall back to the
// cached shell for navigations when offline.
self.addEventListener('fetch', (event) => {
  const { request } = event
  const url = new URL(request.url)
  if (request.method !== 'GET' || url.origin !== location.origin) return
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/cable')) return

  if (url.pathname.match(/\.(png|jpe?g|svg|ico|webp|woff2?|ttf|eot)(\?.*)?$/) || url.pathname.startsWith('/vite/')) {
    event.respondWith(
      caches.match(request).then((cached) =>
        cached ||
        fetch(request).then((response) => {
          if (response.ok) {
            const clone = response.clone()
            caches.open(CACHE).then((cache) => cache.put(request, clone))
          }
          return response
        }),
      ),
    )
    return
  }

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (response.ok) {
            const clone = response.clone()
            caches.open(CACHE).then((cache) => cache.put(request, clone))
          }
          return response
        })
        .catch(() =>
          caches.match(request)
            .then((c) => c || caches.match('/painel'))
            .then((c) => c || caches.match('/offline.html')),
        ),
    )
  }
})

// Web Push — show the notification sent by Vendors::WebPush::Client.
self.addEventListener('push', (event) => {
  let data = {}
  try { data = event.data ? event.data.json() : {} } catch { data = {} }
  const title = data.title || 'agencios'
  const options = data.options || { body: data.body || '' }
  event.waitUntil(self.registration.showNotification(title, options))
})

// Focus an existing tab on the target path, or open a new one.
self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const path = (event.notification.data && event.notification.data.path) || '/painel'
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        const clientPath = new URL(client.url).pathname
        if (clientPath === path && 'focus' in client) return client.focus()
      }
      if (clients.openWindow) return clients.openWindow(path)
    }),
  )
})
