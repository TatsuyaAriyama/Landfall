// Landfall PWA service worker。
// 方針: ハッシュ付きアセットはキャッシュ優先、ページ本体はネットワーク優先
// (更新をすぐ届けつつ、オフラインでも起動できる)。
// バージョンを上げると activate 時に旧キャッシュが破棄される
// (「真っ黒画面が再読込しても直らない」の一因になり得るため、
//  以前壊れた状態がキャッシュされていた場合の脱出路として機能する)。
const CACHE = "landfall-v2";

self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin) return;

  if (url.pathname.startsWith("/assets/")) {
    e.respondWith(
      caches.open(CACHE).then(async (c) => {
        const hit = await c.match(e.request);
        if (hit) return hit;
        const res = await fetch(e.request);
        c.put(e.request, res.clone());
        return res;
      }),
    );
    return;
  }

  if (e.request.mode === "navigate") {
    e.respondWith(
      fetch(e.request)
        .then((res) => {
          // キーは実際のリクエストで統一する(オフライン時のフォールバックも
          // 同じキーで引けるように)。
          caches.open(CACHE).then((c) => c.put(e.request, res.clone()));
          return res;
        })
        .catch(async () => {
          const c = await caches.open(CACHE);
          return (await c.match(e.request)) ?? (await c.match("/")) ?? Response.error();
        }),
    );
  }
});
