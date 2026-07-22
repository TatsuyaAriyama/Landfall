import {
  getRedirectResult,
  signInWithPopup,
  signInWithRedirect,
} from "firebase/auth";
import { auth, googleProvider } from "./firebase";

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

/// リダイレクトから戻ってきたときの認証情報を取り込む。アプリ起動時に一度呼ぶ。
/// これを呼ばないと、リダイレクト方式のサインインが反映されない場合がある。
export async function completeRedirectSignIn(): Promise<void> {
  try {
    await getRedirectResult(auth);
  } catch {
    // 取り込み失敗は握りつぶす(未サインインのまま続行し、再度サインインできる)。
  }
}

// サインイン処理が同時に走らないようにするモジュール内ガード。連打やボタンの
// disabled をすり抜けたイベントでポップアップ/リダイレクトが二重に起きるのを防ぐ。
let signInInFlight = false;

/// Google サインイン。モバイル Safari はリダイレクト、それ以外はポップアップ。
/// ポップアップが塞がれた場合もリダイレクトに切り替えて確実にログインさせる。
export async function signInWithGoogle(): Promise<void> {
  if (signInInFlight) return;
  signInInFlight = true;
  try {
    if (prefersRedirect()) {
      await signInWithRedirect(auth, googleProvider);
      return; // ここでページが遷移するため戻らない
    }
    try {
      await signInWithPopup(auth, googleProvider);
    } catch (e) {
      const code = (e as { code?: string }).code ?? "";
      if (
        code === "auth/popup-blocked" ||
        code === "auth/operation-not-supported-in-this-environment" ||
        code === "auth/cancelled-popup-request"
      ) {
        await signInWithRedirect(auth, googleProvider);
        return;
      }
      throw e;
    }
  } finally {
    signInInFlight = false;
  }
}
