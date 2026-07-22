# Landfall Web

iOS 版と同じ Firebase(landfall---study-log)につながる Web 版。
同じアカウントでサインインすると、記録がリアルタイムに双方向同期される。

- 公開URL: **https://landfall-studylog.com**
- ホスティング: **Cloudflare Pages**(認証・データベースは Firebase のまま。ホスティングだけ Cloudflare)

## 開発

```sh
cd web
npm install
npm run dev
```

Firebase 設定は `web/.env.local`(gitignore 済み)。雛形は `.env.example`。

## デプロイ(Cloudflare Pages / Git 連携)

リポジトリを push すると Cloudflare Pages が自動でビルド・公開する。Pages プロジェクトの設定:

| 項目 | 値 |
|---|---|
| Production branch | `main` |
| Root directory | `web` |
| Build command | `npm run build` |
| Build output directory | `dist` |
| Framework preset | Vite |

**環境変数(Pages の Settings → Environment variables に設定)** — Vite はビルド時に埋め込むので、Pages 側に置く。`web/.env.local` と同じ値:

```
VITE_FB_API_KEY, VITE_FB_AUTH_DOMAIN, VITE_FB_PROJECT_ID, VITE_FB_STORAGE_BUCKET, VITE_FB_APP_ID
```

カスタムドメイン: Pages プロジェクト → Custom domains → `landfall-studylog.com` を追加(同一 Cloudflare アカウントなので CNAME と SSL は自動)。

## 公開までの手順(ユーザー作業)

1. **Firebase コンソールでウェブアプリを登録**
   プロジェクトの設定 → アプリを追加 → ウェブ。表示された `appId` を `web/.env.local`(開発用)と Cloudflare Pages の環境変数 `VITE_FB_APP_ID`(本番用)の両方に入れる。
2. **Auth の承認済みドメイン**
   Authentication → Settings → Authorized domains に **`landfall-studylog.com`** を追加。
   iPad/iPhone の Safari はリダイレクト方式でサインインするため、**このドメインが無いとモバイルでログインできない**。必ず追加すること。
3. **Firestore ルールのデプロイ**(未実施なら)
   `firebase deploy --only firestore:rules`
4. **App Check の enforcement を有効にする場合**
   Web 用に reCAPTCHA プロバイダの登録が必要(iOS の App Attest とは別)。未登録のまま enforcement を ON にすると Web 版が締め出されるので注意。

## スコープ(v1)

- 今日: 項目タイル(作成・編集・削除)+作業記録(分・ひとこと)
- 軌跡: 月カレンダー(学んだ日=黄・休んだ日=緑を同格表示)+日別の記録
- 認証: Google(Apple サインインは Services ID の設定後に追加予定)。
  PC はポップアップ、iPad/iPhone の Safari はリダイレクト方式に自動で切り替わる
- 対応: PC・iPad・スマホの各ブラウザ(レスポンシブ)

### まだ無いもの(次フェーズ)

- 港(パブリック/プライベート)の表示・チャット
- 港への記録の自動反映(現状、Web で記録すると iOS 側の港には即時反映されない。
  iOS アプリを開いて記録すると反映される)
- 航海誌(Wrapped)カード・共有画像

スキーマの正典は `docs/SCHEMA.md`。変更時は iOS・Web・`firestore.rules` を同一コミットで。
