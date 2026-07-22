import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./theme.css";
import { THEME_KEY, applyTheme } from "./views/SettingsDialog.tsx";

// 外観設定(システム/ライト/ダーク)を描画前に反映する。
applyTheme(localStorage.getItem(THEME_KEY));

// PWA: 本番のみ Service Worker を登録(オフライン起動・ホーム画面からアプリとして開ける)。
if (import.meta.env.PROD && "serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    void navigator.serviceWorker.register("/sw.js");
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
