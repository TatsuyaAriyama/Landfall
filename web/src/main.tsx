import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./theme.css";
import { watchViewport } from "./viewport";

// 海の時間帯が外観を決めるため、旧版のライト/ダーク選択は廃止した。
// 保存済みのライト設定で文字色だけ古いままになるのを防ぎ、単一テーマへ移行する。
localStorage.removeItem("appTheme");
document.documentElement.removeAttribute("data-theme");
// Service Worker廃止前に失敗したメインJSのHTTPキャッシュとURLを分離する。
// 今後の障害調査でも、表示中の配信世代をDOMから確認できる。
document.documentElement.dataset.appBuild = "2026-07-26-sw-retired";

// キーボード/ピッカーで実際に見えている高さを :root に流す(全階層のCSSが参照する)。
watchViewport();

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
