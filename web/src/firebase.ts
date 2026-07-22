import { initializeApp } from "firebase/app";
import { getAuth, GoogleAuthProvider } from "firebase/auth";
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
  authDomain: import.meta.env.VITE_FB_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FB_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FB_STORAGE_BUCKET,
  ...(appId ? { appId } : {}),
});

export const auth = getAuth(app);

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
