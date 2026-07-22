import { initializeApp } from "firebase/app";
import { getAuth, GoogleAuthProvider } from "firebase/auth";
import {
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

// オフライン永続化を有効にする。オフライン中の書き込みは端末にキューされ、
// 接続が戻ると自動で同期される(複数タブ間でも1つのキャッシュを共有)。
export const db = initializeFirestore(app, {
  localCache: persistentLocalCache({ tabManager: persistentMultipleTabManager() }),
});

export const googleProvider = new GoogleAuthProvider();
