// Service worker: offline caching for Just Life (Phase 12.4).
//
// Cache-first with network fallback, populated at request time (so the large
// WASM binary and assets are cached as they're first fetched rather than all
// up front). Bump CACHE to invalidate after a new deploy.
const CACHE = 'justlife-v1';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  event.respondWith(
    caches.open(CACHE).then(async (cache) => {
      const cached = await cache.match(event.request);
      if (cached) return cached;
      try {
        const response = await fetch(event.request);
        if (response.ok) cache.put(event.request, response.clone());
        return response;
      } catch (err) {
        // Offline and not cached: let the request fail as usual.
        return cached || Response.error();
      }
    })
  );
});
