import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./theme.css";
import { watchViewport } from "./viewport";
import { storage } from "./storage";

// 海の時間帯が外観を決めるため、旧版のライト/ダーク選択は廃止した。
// 保存済みのライト設定で文字色だけ古いままになるのを防ぎ、単一テーマへ移行する。
// 保存領域を拒否するプライベートブラウズでも、ここで起動を止めない。
storage.remove("appTheme");
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
const APP_BUILD = "2026-07-28-security-v1";
document.documentElement.dataset.appBuild = APP_BUILD;

// キーボード/ピッカーで実際に見えている高さを :root に流す(全階層のCSSが参照する)。
watchViewport();

const root = document.getElementById("root")!;

function loadingIndicator(label = "読み込み中") {
  const indicator = document.createElement("div");
  indicator.className = "harbor-loading";
  indicator.setAttribute("role", "status");
  indicator.setAttribute("aria-label", label);
  return indicator;
}

// App本体と認証ライブラリは分割して読み込むため、回線や端末によってはReactが
// マウントされるまで少し間が空く。ここを空のままにすると正常な読込中でも
// 「起動しない」ように見えるため、最初のimportより前に必ず海の灯りを置く。
root.replaceChildren(loadingIndicator());

/// 起動そのものが失敗した場合の最後の安全網。CSSの地色が暗いため、
/// 何もマウントされないと「真っ黒で再読込しても変わらない」ように見える。
/// 案内文だけでも出して、次に取れる行動(再読込)を示す。
function renderFatalError() {
  const container = document.createElement("div");
  Object.assign(container.style, {
    minHeight: "100vh",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    gap: "12px",
    padding: "24px",
    textAlign: "center",
    color: "#F4F1EC",
    fontFamily: "-apple-system, sans-serif",
  });

  const title = document.createElement("p");
  title.textContent = "読み込みに失敗しました。";
  Object.assign(title.style, { fontSize: "17px", margin: "0" });

  const detail = document.createElement("p");
  detail.textContent = "しばらくしてから再読込してください。";
  Object.assign(detail.style, { fontSize: "14px", opacity: "0.6", margin: "0" });

  const retry = document.createElement("button");
  retry.type = "button";
  retry.textContent = "再読込する";
  retry.addEventListener("click", () => location.reload());
  Object.assign(retry.style, {
    marginTop: "12px",
    minHeight: "48px",
    padding: "0 28px",
    borderRadius: "20px",
    background: "#EADEBD",
    color: "#141414",
    fontSize: "15px",
    border: "none",
  });

  container.append(title, detail, retry);
  root.replaceChildren(container);
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
async function recoverTransientLoad(
  error: unknown,
  waitForAsset = true,
): Promise<boolean> {
  const url = new URL(location.href);
  const sameBuild = url.searchParams.get("recover") === APP_BUILD;
  const previousTry = sameBuild ? Number(url.searchParams.get("recoverTry") ?? "0") : 0;
  if (previousTry >= 2) return false;

  root.replaceChildren(loadingIndicator());
  const assetUrl = failedAssetUrl(error);
  if (waitForAsset && assetUrl) {
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
  if (!url.searchParams.has("recover") && !url.searchParams.has("recoverTry")) return;
  url.searchParams.delete("recover");
  url.searchParams.delete("recoverTry");
  history.replaceState(null, "", `${url.pathname}${url.search}${url.hash}`);
}

// 目的地・港・航海などは、最初に押した時だけ分割JSを読む。公開更新前から
// 開きっぱなしのタブでは、その旧ファイルが配信先から消えていることがある。
// Viteが投げる専用イベントを起動失敗と同じ復旧経路へ渡し、新しいHTMLとJSへ
// 一度だけ自動更新する。短時間に繰り返す場合は無限再読込を止め、手動案内へ落とす。
function installLazyLoadRecovery() {
  let recovering = false;
  window.addEventListener("vite:preloadError", (event) => {
    event.preventDefault();
    if (recovering) return;
    recovering = true;

    const storageKey = `landfall.lazy-recovery.${APP_BUILD}`;
    let previous = 0;
    try {
      previous = Number(sessionStorage.getItem(storageKey) ?? "0");
    } catch {
      // sessionStorageを拒否するブラウザでも、URL側の回数制限で復旧を続ける。
    }
    if (Date.now() - previous < 60_000) {
      renderFatalError();
      return;
    }
    try {
      sessionStorage.setItem(storageKey, String(Date.now()));
    } catch {
      // 保存できなくても、復旧そのものは止めない。
    }

    const payload = (event as Event & { payload?: unknown }).payload;
    void recoverTransientLoad(payload, false).then((recovered) => {
      if (!recovered) renderFatalError();
    });
  });
}

try {
  const { default: App } = await import("./App.tsx");
  clearRecoveryUrl();
  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
  // 初回のApp読込は外側のtry/catchへ任せる。ここより前に監視すると、
  // preventDefaultによって起動エラーがundefinedへ変わり、原因URLを失ってしまう。
  installLazyLoadRecovery();
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
