// Service Worker廃止用の一回限りの移行Worker。
// 旧キャッシュを全削除し、自分自身も登録解除して、開いている画面を
// キャッシュを通さない通常のWebページへ戻す。
self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(keys.map((key) => caches.delete(key)));

      const windows = await self.clients.matchAll({
        type: "window",
        includeUncontrolled: true,
      });
      await self.registration.unregister();

      await Promise.all(
        windows.map((client) => {
          const url = new URL(client.url);
          url.searchParams.set("_sw", "off");
          return client.navigate(url.href);
        }),
      );
    })(),
  );
});

// 終了処理が完了するまでの短い間も、キャッシュは一切使わない。
self.addEventListener("fetch", (event) => {
  event.respondWith(fetch(event.request, { cache: "no-store" }));
});
