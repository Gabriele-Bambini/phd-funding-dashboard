// PhD Funding Command Center - offline support
// Strategy: NETWORK-FIRST with runtime cache.
// Online you always get fresh content (no staleness during development);
// offline you get the last cached copy of the full dossier.
const CACHE = 'phdfund-v1';
const PRECACHE = [
  './',
  './index.html',
  './funding.html',
  './deadlines.ics',
  './icon.svg',
  './proposals/p53-sheaf-gnn.pdf',
  './proposals/p53-sheaf-gnn.html',
  './proposals/te-mosquito.pdf',
  './proposals/te-mosquito.html',
  './proposals/immuno-uncertainty.pdf',
  './proposals/immuno-uncertainty.html'
];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(PRECACHE)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  e.respondWith(
    fetch(e.request).then(r => {
      const cp = r.clone();
      caches.open(CACHE).then(c => c.put(e.request, cp));
      return r;
    }).catch(() => caches.match(e.request))
  );
});
