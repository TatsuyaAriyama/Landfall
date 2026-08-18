import {
  browserLocalPersistence,
  getRedirectResult,
  inMemoryPersistence,
  indexedDBLocalPersistence,
  setPersistence,
  signInWithPopup,
  type AuthProvider,
} from "firebase/auth";
import { appleProvider, auth, googleProvider } from "./firebase";
import { isEmbeddedWebViewUserAgent } from "./authStrategy";

// リダイレクト認証は使わない。Safari 16.1+などのストレージ分離では、
// Firebase標準ドメインから自サイトへ戻る際に認証状態を引き継げないことがある。
// ボタンの直接タップから開くポップアップに全環境を統一する。

/// Instagram/LINE/X などアプリ内の埋め込みブラウザ(WebView)か。
/// Google は WebView からの OAuth を仕様でブロックしており(disallowed_useragent)、
/// コード側でどう工夫してもサインインできない。検出して「Safariで開いて」と
/// 案内するのが唯一の対処(iPhone/iPadで「サインインできない」の実例で多い原因)。
export function isEmbeddedWebView(): boolean {
  if (typeof navigator === "undefined") return false;
  return isEmbeddedWebViewUserAgent(navigator.userAgent);
}

/// この端末・状況で想定される、認証まわりの注意点(あれば)。
/// サインインを試す前に案内できるよう、エラーではなく事前チェックとして提供する。
export function authEnvironmentNotice(): "embedded-webview" | null {
  return isEmbeddedWebView() ? "embedded-webview" : null;
}

/// Safari のプライベートブラウズ・ITP設定などで永続化(IndexedDB)が使えない場合に
/// 備え、より緩い方式へ段階的にフォールバックする。ここが失敗して例外が漏れると
/// サインインボタンを押しても何も起きない(=「反応しない」ように見える)原因になる。
let persistenceReady: Promise<void> | null = null;
function ensurePersistence(): Promise<void> {
  persistenceReady ??= (async () => {
    for (const mode of [indexedDBLocalPersistence, browserLocalPersistence, inMemoryPersistence]) {
      try {
        await setPersistence(auth, mode);
        return;
      } catch {
        // 次のフォールバックへ。全滅しても致命的にはせず、既定の永続化のまま進める。
      }
    }
  })();
  return persistenceReady;
}

/// モバイルのリダイレクト復帰と、旧版で遷移した途中の人を取り込む。
/// 失敗コードは呼び出し側で文言化する。
export async function completeRedirectSignIn(): Promise<string | null> {
  try {
    await ensurePersistence();
    await getRedirectResult(auth);
    return null;
  } catch (e) {
    // 未サインインのまま続行し、再度サインインできるようにする(致命的にしない)。
    return (e as { code?: string }).code ?? "unknown";
  }
}

// サインイン処理が同時に走らないようにするモジュール内ガード。連打やボタンの
// disabled をすり抜けたイベントでポップアップが二重に開くのを防ぐ。
let signInInFlight = false;

/// 共通のサインイン。直接のユーザー操作からポップアップを開く。
async function signInWith(provider: AuthProvider): Promise<void> {
  if (signInInFlight) return;
  signInInFlight = true;
  try {
    // 永続化の準備でつまずいてもサインイン自体は試す(ここで例外を投げると
    // ボタンが無反応に見えるため)。
    await ensurePersistence().catch(() => {});
    await signInWithPopup(auth, provider);
  } finally {
    signInInFlight = false;
  }
}

/// Google サインイン。
export function signInWithGoogle(): Promise<void> {
  return signInWith(googleProvider);
}

/// Apple サインイン(Sign in with Apple)。
export function signInWithApple(): Promise<void> {
  return signInWith(appleProvider);
}
