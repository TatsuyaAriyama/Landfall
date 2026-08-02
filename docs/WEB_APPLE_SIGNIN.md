# Web版「Appleで続ける」を有効にする手順

Web の実装(`src/firebase.ts` の `appleProvider` / `src/auth.ts` の `signInWithApple`)は完了済み。
実際にログインできるようにするには、**Apple Developer と Firebase の設定**が要る(コードでは完結しない)。
設定前にボタンを押すと `auth/operation-not-allowed` などで失敗する。

## 1. Apple Developer(有料の Apple Developer Program が必要)

1. **App ID** を用意する(既に iOS アプリの App ID がある場合はそれを使う)。
   Certificates, Identifiers & Profiles → Identifiers → 対象の App ID →
   **Sign In with Apple** を有効化。
2. **Services ID** を新規作成(これが Web 用の client_id になる)。
   Identifiers → `+` → **Services IDs** → 説明と識別子を入力
   (例: `com.tatsuyaariyama.Landfall.web`)。
3. 作った Services ID を開き **Sign In with Apple** を有効化 → **Configure**:
   - **Primary App ID**: 手順1の App ID
   - **Domains and Subdomains**: `aftide.app`
     (Firebase の authDomain も必要な場合がある: `<project>.firebaseapp.com`)
   - **Return URLs**: `https://<project>.firebaseapp.com/__/auth/handler`
     ※ 正確な値は Firebase コンソールの Apple プロバイダ設定画面に表示される
4. **Key** を作成: Keys → `+` → **Sign In with Apple** を有効化 → Configure で
   Primary App ID を選択 → 作成し **.p8 キーをダウンロード**(再取得不可)。
   **Key ID** と **Team ID** を控える。

## 2. Firebase コンソール

Authentication → Sign-in method → **Apple** を有効化し、以下を入力:

- **Services ID**: 手順2で作った識別子(例 `com.tatsuyaariyama.Landfall.web`)
- **Apple Team ID**
- **Key ID**
- **Private key**: ダウンロードした `.p8` の中身

保存後、**承認済みドメイン**に `aftide.app` が入っていることを確認
(既に Google 用に追加済みのはず)。

## 3. 確認

1. `https://aftide.app` を開き「Appleで続ける」を押す。
2. Apple のログイン画面 → 許可 → アプリに戻ってサインイン完了。
3. 初回は「メールを非公開」を選べる(リレーアドレスが発行される)。
   KeelMira はメールアドレスを表示・利用しないので、どちらでも支障はない。

## メモ

- iOS アプリ側は Firebase Auth の Apple プロバイダを使えば **同じアカウント**として
  扱われる(同じ Apple ID なら uid が一致し、記録も同期される)。
- ユーザーが Apple/Google 両方で入った場合は別アカウント(別 uid)になる。
  同一人物の統合が要るなら `linkWithCredential` の実装が別途必要。
