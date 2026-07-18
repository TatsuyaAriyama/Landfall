# Landfall セキュリティ概要

Landfall の防御は3層です。**それぞれ「有効化」の手順が違う**ので注意してください。

| 層 | どこ | 何を守る | 有効化 |
|----|------|---------|--------|
| Firestore セキュリティルール | `firestore.rules` | 本当の権限境界。誰が何を読み書きできるか | **デプロイが必要**(下記) |
| App Check | アプリ内 `AppCheckProvider.swift` + Firebase コンソール | 本物のアプリからのアクセスか(濫用・なりすまし防止) | コンソールで **enforcement を ON** にして初めて遮断が効く |
| クライアント側の入力上限 | `RoomService.swift` ほか | 肥大データを送らない(多重防御・UX) | ビルドに含まれる(自動) |

## 1. Firestore ルール(最重要)

`firestore.rules` はローカルのファイルにすぎません。**Firebase にデプロイするまで本番には一切効きません。**

### 保証している不変条件
- `users/{uid}/**` … 本人だけが読み書き。他人のバックアップには一切触れない。
- 港(`rooms/{code}`)
  - **乗っ取り防止**: 港名・作成日時・他メンバーは誰も改変できない。
  - 更新は「自分ひとりを加える/外す」だけに限定(在港者による追い出し・強制追加を拒否)。
  - `list`(一覧クエリ)は自分が属する港のみ。コード総当たりでの列挙・UID収集を防ぐ。
    `get`(コードを知っての単票読み)は参加に必要なので許可。
  - 作成・更新はフィールドを既知のものに限定し、型と長さを検証(肥大データ注入を拒否)。
- メンバーカード / 月次共有記録 … 読めるのは同じ港のメンバーだけ。書けるのは本人かつ在港者のみ。

### デプロイ手順
```sh
npm i -g firebase-tools           # 未インストールなら
firebase login                    # ← 認証(手動)
firebase use <your-project-id>    # landfall---study-log
# まず Firebase コンソールの「Rules Playground」で主要ケースを試すことを推奨
firebase deploy --only firestore:rules
```
> デプロイ前に既存データがルールに適合するか確認してください(既存の港は name/memberIds/createdAt を持つため適合します)。

## 2. App Check(濫用対策)

`AppCheck.setAppCheckProviderFactory(...)` を `FirebaseApp.configure()` の前に差し込み済み。
- 本番(実機): **App Attest**(Secure Enclave による端末+アプリの証明)。
- DEBUG(シミュレータ/開発機): デバッグプロバイダ。起動ログに出るデバッグトークンをコンソールに登録すると検証が通る。

**遮断を効かせるには**、Firebase コンソールで:
1. App Check にこのアプリ(App Attest)を登録。
2. 開発用にデバッグトークンを登録。
3. 正規トラフィックがすべて通ることを監視で確認してから、Firestore と Authentication の **enforcement を ON**。

> enforcement が OFF の間は未登録でも通常通信は妨げられません(安全に先行導入できます)。順序を守らないと正規ユーザーを締め出す恐れがあるため、**必ず監視 → 確認 → 有効化**の順で。

## 3. 秘密情報の扱い
- `GoogleService-Info.plist`(Firebase クライアント設定)は `.gitignore` 済み。リポジトリには含めません。
  ビルドには必要なので、Firebase コンソールから取得して `Landfall/GoogleService-Info.plist` に置いてください。
- `Info.plist` の `GIDClientID` と reversed client ID は公開識別子であり秘密ではありません(Google Sign-In の標準)。
- App Transport Security は既定のまま(HTTPS 強制。任意HTTP読み込みの例外なし)。
- Apple サインインはリプレイ防止の nonce(SHA256)を使用。
