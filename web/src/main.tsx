import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./theme.css";
import { watchViewport } from "./viewport";

// 海の時間帯が外観を決めるため、旧版のライト/ダーク選択は廃止した。
// 保存済みのライト設定で文字色だけ古いままになるのを防ぎ、単一テーマへ移行する。
localStorage.removeItem("appTheme");
document.documentElement.removeAttribute("data-theme");

// キーボード/ピッカーで実際に見えている高さを :root に流す(全階層のCSSが参照する)。
watchViewport();

// PWA: 本番のみ Service Worker を登録(オフライン起動・ホーム画面からアプリとして開ける)。
if (import.meta.env.PROD && "serviceWorker" in navigator) {
  // 新しいSWが制御を引き継いだら(=更新が来たら)、一度だけ再読込して最新を反映する。
  // これがないと、キャッシュ優先のアセットのせいで更新に気づけない。
  // 初回インストール(元々コントローラなし)ではリロードしない。
  const hadController = Boolean(navigator.serviceWorker.controller);
  let reloading = false;
  navigator.serviceWorker.addEventListener("controllerchange", () => {
    if (reloading || !hadController) return;
    reloading = true;
    window.location.reload();
  });
  window.addEventListener("load", () => {
    // updateViaCache: "none" が要る。これが無いと sw.js 自体がHTTPキャッシュから
    // 返されるため、新しいSWの存在に気づけない(Cloudflare側で sw.js は
    // max-age=14400 に固定されており、_headers からは下げられなかった)。
    // これを付けると更新確認だけは必ずネットワークへ行く。
    void navigator.serviceWorker
      .register("/sw.js", { updateViaCache: "none" })
      .then((reg) => {
        // 更新の確認。ホーム画面から開くPWAはナビゲーションが起きないまま
        // 復帰することがあり、放っておくと古いまま動き続ける。
        // 起動時と、前面に戻ってくるたびに確認する。
        const check = () => void reg.update().catch(() => {});
        check();
        document.addEventListener("visibilitychange", () => {
          if (document.visibilityState === "visible") check();
        });
      })
      .catch(() => {});
  });
}

const root = document.getElementById("root")!;

/// 起動そのものが失敗した場合の最後の安全網。CSSの地色が暗いため、
/// 何もマウントされないと「真っ黒で再読込しても変わらない」ように見える。
/// 案内文だけでも出して、次に取れる行動(再読込)を示す。
function renderFatalError() {
  root.innerHTML =
    '<div style="min-height:100vh;display:flex;flex-direction:column;' +
    "align-items:center;justify-content:center;gap:12px;padding:24px;" +
    'text-align:center;color:#F4F1EC;font-family:-apple-system,sans-serif;">' +
    '<p style="font-size:17px;margin:0;">読み込みに失敗しました。</p>' +
    '<p style="font-size:14px;opacity:0.6;margin:0;">' +
    "しばらくしてから再読込してください。" +
    '</p><button onclick="location.reload()" style="margin-top:12px;' +
    "min-height:48px;padding:0 28px;border-radius:20px;background:#EADEBD;" +
    'color:#141414;font-size:15px;border:none;">再読込する</button></div>';
}

try {
  const { default: App } = await import("./App.tsx");
  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
} catch {
  renderFatalError();
}
