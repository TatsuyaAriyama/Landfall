(() => {
  "use strict";

  const host = window.location.hostname;
  if (host === "landfall-studylog.com" || host === "www.aftide.app") {
    window.location.replace(
      `https://aftide.app${window.location.pathname}${window.location.search}${window.location.hash}`,
    );
    return;
  }

  // Service Workerは更新時の新旧JS混在を繰り返したため廃止した。
  // 既存端末に登録が残っている場合だけ終了専用Workerへ差し替える。
  const production =
    host === "aftide.app" ||
    host.endsWith(".landfall-studylog.pages.dev");
  if (!production || !("serviceWorker" in navigator)) return;

  navigator.serviceWorker
    .getRegistration()
    .then((registration) => {
      if (!registration) return undefined;
      return navigator.serviceWorker.register("/sw-retire.js?v=1", {
        scope: "/",
        updateViaCache: "none",
      });
    })
    .catch(() => {});
})();
