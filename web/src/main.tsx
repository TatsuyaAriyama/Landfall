import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./theme.css";
import { watchViewport } from "./viewport";

// 海の時間帯が外観を決めるため、旧版のライト/ダーク選択は廃止した。
// 保存済みのライト設定で文字色だけ古いままになるのを防ぎ、単一テーマへ移行する。
// 保存領域を拒否するプライベートブラウズでも、ここで起動を止めない。
try {
  localStorage.removeItem("appTheme");
} catch {
  // テーマ値が残っても、直後にDOM属性を外すため表示は継続できる。
}
document.documentElement.removeAttribute("data-theme");

// デザイン確認用の #demo は開発環境だけで使う。本番端末に以前の確認URLが
// 残っていても、認証状態を待たず本物の港へ戻し、実データが消えたように見せない。
if (!import.meta.env.DEV && window.location.hash === "#demo") {
  history.replaceState(
    null,
    "",
    `${window.location.pathname}${window.location.search}#harbor`,
  );
}

// Service Worker廃止前に失敗したメインJSのHTTPキャッシュとURLを分離する。
// 今後の障害調査でも、表示中の配信世代をDOMから確認できる。
const APP_BUILD = "2026-07-27-harbor-tent-v1";
document.documentElement.dataset.appBuild = APP_BUILD;

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

const wait = (ms: number) => new Promise<void>((resolve) => window.setTimeout(resolve, ms));

/// 動的importの例外から、取得に失敗した同一オリジンの分割JSだけを取り出す。
/// Firebase等の別種の例外では無関係なURLへ通信しない。
function failedAssetUrl(error: unknown): string | null {
  if (!(error instanceof Error)) return null;
  const found = error.message.match(/https?:\/\/[^\s)]+/)?.[0];
  if (!found) return null;
  try {
    const url = new URL(found);
    return url.origin === location.origin && url.pathname.startsWith("/assets/")
      ? url.href
      : null;
  } catch {
    return null;
  }
}

/// デプロイ直後、CDNのHTMLと分割JSが一瞬だけ別世代になる場合がある。
/// 失敗したJSが実際に取得可能になるまで短く待ち、HTTPキャッシュを正常な応答で
/// 更新してから再読込する。即時再読込だけだと、同じ404を繰り返してしまう。
async function recoverTransientLoad(error: unknown): Promise<boolean> {
  const url = new URL(location.href);
  const sameBuild = url.searchParams.get("recover") === APP_BUILD;
  const previousTry = sameBuild ? Number(url.searchParams.get("recoverTry") ?? "0") : 0;
  if (previousTry >= 2) return false;

  root.innerHTML = '<div class="harbor-loading"></div>';
  const assetUrl = failedAssetUrl(error);
  if (assetUrl) {
    for (const delay of [500, 1200, 2500]) {
      await wait(delay);
      try {
        const response = await fetch(assetUrl, { cache: "reload" });
        if (response.ok) break;
      } catch {
        // 次の間隔で再確認する。
      }
    }
  }

  url.searchParams.set("recover", APP_BUILD);
  url.searchParams.set("recoverTry", String(previousTry + 1));
  location.replace(url);
  return true;
}

function clearRecoveryUrl() {
  const url = new URL(location.href);
  if (url.searchParams.get("recover") !== APP_BUILD) return;
  url.searchParams.delete("recover");
  url.searchParams.delete("recoverTry");
  history.replaceState(null, "", `${url.pathname}${url.search}${url.hash}`);
}

try {
  const { default: App } = await import("./App.tsx");
  clearRecoveryUrl();
  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
} catch (error) {
  // 表示用には詳細を出さないが、端末上の診断で原因を区別できるようDOMへ控える。
  // 値は例外名だけに絞り、設定値やURLなどを露出させない。
  document.documentElement.dataset.loadError =
    error instanceof Error ? error.name : "UnknownError";
  if (error instanceof Error) {
    document.documentElement.dataset.loadErrorDetail = error.message
      .replace(/https?:\/\/\S+/g, "[url]")
      .slice(0, 160);
  }
  if (!(await recoverTransientLoad(error))) renderFatalError();
}
