import { useState } from "react";
import { isEmbeddedWebView, signInWithApple, signInWithGoogle } from "../auth";
import { BoatSvg, CoastSvg } from "../symbols";
import { t } from "../i18n";

// 「夜の入港」。星と月の空、水平線に落ちる月光、静かに揺れる帆船、迎える海岸。
// harborTeal 一色の地に harborSand のフラット塗りのみ(グラデーション・影なし)。
// サインイン=入港、という iOS と同じ物語を、Web ではポスターの構図で描く。

const STARS: Array<{ top: string; left: string; size: number }> = [
  { top: "16%", left: "10%", size: 4 },
  { top: "8%", left: "24%", size: 3 },
  { top: "20%", left: "36%", size: 3 },
  { top: "6%", left: "52%", size: 4 },
  { top: "14%", left: "68%", size: 3 },
  { top: "9%", left: "83%", size: 4 },
  { top: "24%", left: "91%", size: 3 },
  { top: "30%", left: "17%", size: 2 },
  { top: "12%", left: "44%", size: 2 },
  { top: "28%", left: "60%", size: 2 },
  { top: "18%", left: "76%", size: 2 },
];

/// Apple のマーク(公式の意匠に沿った単色シルエット)。
function AppleGlyph() {
  return (
    <svg viewBox="0 0 384 512" width="17" height="17" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"
      />
    </svg>
  );
}

/// Google のマーク(公式4色)。ブランド規定に沿って原色のまま置く。
function GoogleGlyph() {
  return (
    <svg viewBox="0 0 48 48" width="18" height="18" aria-hidden="true" focusable="false">
      <path
        fill="#4285F4"
        d="M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17z"
      />
      <path
        fill="#34A853"
        d="M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46z"
      />
      <path
        fill="#FBBC05"
        d="M11.69 28.18C11.25 26.86 11 25.45 11 24s.25-2.86.69-4.18v-5.7H4.34C2.85 17.09 2 20.45 2 24s.85 6.91 2.34 9.88l7.35-5.7z"
      />
      <path
        fill="#EA4335"
        d="M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07z"
      />
    </svg>
  );
}

/// Firebase のエラーコード(サインイン試行時・リダイレクト復帰時 共通)を、
/// この画面で見せる一言に変換する。ユーザーが取れる行動がある場合はそれを言う。
function messageForCode(code: string): string | null {
  if (code === "auth/popup-closed-by-user" || code === "auth/cancelled-popup-request") {
    return null; // 本人が閉じただけなので、エラーとしては見せない。
  }
  if (code === "auth/web-storage-unsupported" || code === "auth/operation-not-supported-in-this-environment") {
    return t("signInStorageBlocked");
  }
  return t("signInFailed");
}

export function SignInView({ redirectError }: { redirectError?: string | null }) {
  const [error, setError] = useState<string | null>(
    redirectError ? messageForCode(redirectError) : null,
  );
  const [working, setWorking] = useState<"google" | "apple" | null>(null);
  // Instagram/LINEなどのアプリ内ブラウザは、Googleの仕様でサインインが必ず失敗する
  // (disallowed_useragent)。押させる前に、対処法(ブラウザで開く)を案内する。
  const [embedded] = useState(() => isEmbeddedWebView());

  const run = async (which: "google" | "apple") => {
    if (working) return;
    setWorking(which);
    setError(null);
    try {
      // モバイル Safari はここでリダイレクトし、戻ってきたら自動でサインイン完了。
      // PC はポップアップで完結する。
      await (which === "google" ? signInWithGoogle() : signInWithApple());
    } catch (e) {
      const code = (e as { code?: string }).code ?? "";
      const message = messageForCode(code);
      if (message) setError(message);
    } finally {
      setWorking(null);
    }
  };

  return (
    <div className="harbor-signin">
      <p className="harbor-topbar">{t("wordmark")}</p>

      {STARS.map((s, i) => (
        <span
          key={i}
          className="harbor-star"
          style={{ top: s.top, left: s.left, width: s.size, height: s.size }}
        />
      ))}
      <span className="harbor-moon" />

      <div className="harbor-content">
        <h1 className="harbor-enter">{t("signInEnter")}</h1>
        <p className="harbor-sync">{t("signInSync")}</p>
        {embedded && <p className="harbor-webview-warning">{t("signInWebviewWarning")}</p>}
        <div className="harbor-actions">
          <button
            className="harbor-signin-button harbor-apple"
            onClick={() => void run("apple")}
            disabled={working !== null}
          >
            <AppleGlyph />
            <span>{t("signInWithApple")}</span>
          </button>
          <button
            className="harbor-signin-button harbor-google"
            onClick={() => void run("google")}
            disabled={working !== null}
          >
            <GoogleGlyph />
            <span>{t("signInWithGoogle")}</span>
          </button>
          <p className="harbor-note">{t("signInNote")}</p>
          {error && <p className="harbor-error">{error}</p>}
        </div>
      </div>

      <div className="harbor-sea">
        <div className="harbor-horizon" />
        {/* 月光の道: 月の真下に落ちて、手前ほど広がって崩れる */}
        <span className="harbor-moonpath" />
        <span className="harbor-glint harbor-glint-1" />
        <span className="harbor-glint harbor-glint-2" />
        <span className="harbor-glint harbor-glint-3" />
        <div className="harbor-boat-wrap">
          <div className="harbor-boat">
            <BoatSvg />
          </div>
        </div>
        <div className="harbor-coast">
          <CoastSvg />
        </div>
      </div>
    </div>
  );
}
