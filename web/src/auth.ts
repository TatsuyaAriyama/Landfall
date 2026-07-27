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

// 【重要】signInWithRedirect は使わない。
//
// かつては「モバイル Safari はポップアップが塞がれやすいのでリダイレクト」が定石だったが、
// Safari 16.1+ / Chrome の Storage Partitioning により、認証ドメイン
// (*.firebaseapp.com)と自サイト(aftide.app)が別オリジンの場合、
// リダイレクトで戻ってきても認証状態を引き継げなくなった。
// 結果、Googleのログイン画面までは進むのに、戻ると未サインインのまま——という
// 「iPhone/iPadでログインできない」症状になる(Firebase 公式も既知の制約として、
// カスタムドメイン運用では signInWithPopup を推奨している)。
//
// ポップアップはボタンのタップという明確なユーザー操作から直接開くため、
// iOS Safari でもブロックされない。よって全環境でポップアップに統一する。

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

/// 過去にリダイレクト方式でサインインした人が戻ってきた場合の取り込み。
/// 現在はポップアップ方式に統一したので通常は何もしないが、旧版で遷移した
/// 途中の人を取りこぼさないために残す。失敗コードは呼び出し側で文言化する。
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

/// 共通のサインイン。全環境でポップアップを使う(上のコメント参照:
/// クロスドメインの signInWithRedirect は Safari/iOS で認証状態を引き継げない)。
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
