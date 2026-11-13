/* Storageku · Service Worker
   - Halaman aplikasi: ambil versi terbaru dari jaringan, pakai salinan tersimpan bila offline.
   - Pustaka (grafik, Excel, PDF, Supabase, font): pakai salinan tersimpan lalu perbarui di latar.
   - Data Supabase TIDAK pernah disimpan di cache (selalu langsung ke server).
   Naikkan angka VERSION setiap kali ingin memaksa semua perangkat membersihkan cache lama. */
const VERSION = 'storageku-v1';
const SHELL = ['./', './index.html', './manifest.webmanifest', './icons/icon-192.png', './icons/icon-512.png', './icons/icon-maskable-512.png', './icons/apple-touch-icon.png', './icons/favicon-32.png'];
const CDN_HOSTS = ['cdn.jsdelivr.net', 'cdnjs.cloudflare.com', 'fonts.googleapis.com', 'fonts.gstatic.com'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Supabase (database, login, realtime): jangan disentuh.
  if (url.hostname.endsWith('.supabase.co') || url.hostname.endsWith('.supabase.in')) return;

  // Halaman aplikasi: jaringan dulu, cadangan dari cache.
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req).then(res => { const copy = res.clone(); caches.open(VERSION).then(c => c.put('./index.html', copy)); return res; })
        .catch(() => caches.match('./index.html').then(r => r || caches.match('./')))
    );
    return;
  }

  // Pustaka dari CDN & file statis milik aplikasi: cache dulu, perbarui di latar.
  if (CDN_HOSTS.includes(url.hostname) || url.origin === self.location.origin) {
    e.respondWith(
      caches.open(VERSION).then(cache => cache.match(req).then(hit => {
        const net = fetch(req).then(res => { if (res && (res.ok || res.type === 'opaque')) cache.put(req, res.clone()); return res; }).catch(() => hit);
        return hit || net;
      }))
    );
  }
});
