import { initializeApp } from "firebase/app";
import {
  initializeAppCheck,
  ReCaptchaEnterpriseProvider,
} from "firebase/app-check";
import {
  browserLocalPersistence,
  browserPopupRedirectResolver,
  GoogleAuthProvider,
  indexedDBLocalPersistence,
  initializeAuth,
  inMemoryPersistence,
  OAuthProvider,
} from "firebase/auth";
import {
  getFirestore,
  initializeFirestore,
  persistentLocalCache,
  persistentMultipleTabManager,
} from "firebase/firestore";

// 設定値は web/.env.local(gitignore 済み)から。apiKey は公開情報だが方針としてコードに直書きしない。
const appId = import.meta.env.VITE_FB_APP_ID as string | undefined;

export const app = initializeApp({
  apiKey: import.meta.env.VITE_FB_API_KEY,
  // OAuth helper は Firebase が管理する標準ドメインを使う。
  // aftide.app を authDomain にすると、Cloudflare の透過プロキシ越しに
  // Firebase の popup/iframe 初期化が auth/internal-error で失敗する。
  authDomain: import.meta.env.VITE_FB_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FB_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FB_STORAGE_BUCKET,
  ...(appId ? { appId } : {}),
});

// Web版の正規クライアントからの通信であることをApp Checkトークンで証明する。
// 公開サイトキーが設定済みの本番だけで有効化し、未設定・初期化失敗でも
// 認証画面そのものは落とさない。遮断はコンソールでメトリクス確認後に有効化する。
// 正式名は VITE_FB_APP_CHECK_SITE_KEY。初期のローカル設定で使われていた
// VITE_FB_APPCHECK_SITE_KEY も読み、手動のproduction buildだけApp Checkが
// 無効になる名前違いを吸収する。
const appCheckSiteKey = (
  import.meta.env.VITE_FB_APP_CHECK_SITE_KEY
  ?? import.meta.env.VITE_FB_APPCHECK_SITE_KEY
) as string | undefined;
if (import.meta.env.PROD && appCheckSiteKey) {
  try {
    initializeAppCheck(app, {
      provider: new ReCaptchaEnterpriseProvider(appCheckSiteKey),
      isTokenAutoRefreshEnabled: true,
    });
  } catch {
    // 二重初期化やブラウザー制限時は、Firestore側の認証・ルールを安全網として継続する。
  }
}

// 永続化の初期化がサインイン操作と競合しないよう、初回から優先順位を明示する。
// SafariのプライベートブラウズでIndexedDBが使えなくても、
// localStorage、それも無理ならメモリへ自動で落ちる。
export const auth = initializeAuth(app, {
  persistence: [
    indexedDBLocalPersistence,
    browserLocalPersistence,
    inMemoryPersistence,
  ],
  popupRedirectResolver: browserPopupRedirectResolver,
});
auth.useDeviceLanguage();

// オフライン永続化(IndexedDB)を試みる。プライベートブラウジングや
// トラッキング防止が厳しいSafari・一部の拡張機能ではIndexedDBがブロックされ、
// initializeFirestore がここで同期的に例外を投げることがある。これを
// キャッチせずにいると、Reactが一度もマウントされないまま(=真っ黒な画面の
// まま再読込しても変わらない)アプリ全体が起動不能になるため、必ずフォールバックする。
function createFirestore() {
  try {
    return initializeFirestore(app, {
      localCache: persistentLocalCache({ tabManager: persistentMultipleTabManager() }),
    });
  } catch {
    return getFirestore(app);
  }
}

export const db = createFirestore();

export const googleProvider = new GoogleAuthProvider();

// Apple サインイン。Firebase コンソールで Apple プロバイダを有効にしておく必要がある
// (Apple Developer の Services ID / キーの登録が前提。docs/WEB_APPLE_SIGNIN.md)。
export const appleProvider = new OAuthProvider("apple.com");
appleProvider.addScope("email");
appleProvider.addScope("name");
