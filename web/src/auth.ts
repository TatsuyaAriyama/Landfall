import {
  browserLocalPersistence,
  getRedirectResult,
  inMemoryPersistence,
  indexedDBLocalPersistence,
  setPersistence,
  signInWithPopup,
  signInWithRedirect,
  type AuthProvider,
} from "firebase/auth";
import { appleProvider, auth, googleProvider } from "./firebase";

// iPad / iPhone の Safari はトラッキング防止(ITP)とポップアップ制限が厳しく、
// signInWithPopup が失敗・ブロックされやすい。これらの端末では同じタブで遷移して
// 戻る signInWithRedirect の方が確実、というのが Firebase の定石。
// PC のブラウザはポップアップの方が快適なのでそのまま使う。

function prefersRedirect(): boolean {
  if (typeof navigator === "undefined") return false;
  const ua = navigator.userAgent;
  const iPhoneOrPad = /iPad|iPhone|iPod/.test(ua);
  // iPadOS 13+ の Safari は既定で "Macintosh" を名乗るため、タッチ点数で iPad を見分ける。
  const iPadOSAsMac = /Macintosh/.test(ua) && navigator.maxTouchPoints > 1;
  return iPhoneOrPad || iPadOSAsMac;
}

/// Instagram/LINE/X などアプリ内の埋め込みブラウザ(WebView)か。
/// Google は WebView からの OAuth を仕様でブロックしており(disallowed_useragent)、
/// コード側でどう工夫してもサインインできない。検出して「Safariで開いて」と
/// 案内するのが唯一の対処(iPhone/iPadで「サインインできない」の実例で多い原因)。
export function isEmbeddedWebView(): boolean {
  if (typeof navigator === "undefined") return false;
  const ua = navigator.userAgent;
  if (/FBAN|FBAV|Instagram|Line\/|MicroMessenger|TikTok/i.test(ua)) return true;
  // X(Twitter)アプリの内蔵ブラウザ。
  if (/Twitter/i.test(ua)) return true;
  // Android の WebView 全般("; wv)" を名乗る)。iOS 版アプリ内ブラウザは上記個別UAで拾う。
  if (/; wv\)/.test(ua)) return true;
  return false;
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

/// リダイレクトから戻ってきたときの認証情報を取り込む。アプリ起動時に一度呼ぶ。
/// これを呼ばないと、リダイレクト方式のサインインが反映されない場合がある。
/// 失敗した場合は診断用にエラーコードを返す(呼び出し側で文言化して見せられるように)。
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
// disabled をすり抜けたイベントでポップアップ/リダイレクトが二重に起きるのを防ぐ。
let signInInFlight = false;

/// 共通のサインイン。モバイル Safari はリダイレクト、それ以外はポップアップ。
/// ポップアップが塞がれた場合もリダイレクトに切り替えて確実にログインさせる。
async function signInWith(provider: AuthProvider): Promise<void> {
  if (signInInFlight) return;
  signInInFlight = true;
  try {
    await ensurePersistence();
    if (prefersRedirect()) {
      await signInWithRedirect(auth, provider);
      return; // ここでページが遷移するため戻らない
    }
    try {
      await signInWithPopup(auth, provider);
    } catch (e) {
      const code = (e as { code?: string }).code ?? "";
      if (
        code === "auth/popup-blocked" ||
        code === "auth/operation-not-supported-in-this-environment" ||
        code === "auth/cancelled-popup-request"
      ) {
        await signInWithRedirect(auth, provider);
        return;
      }
      throw e;
    }
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
