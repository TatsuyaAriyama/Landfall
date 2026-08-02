# App Store 提出チェックリスト

KeelMira を App Store に提出するための手順と、記載が必要な項目のまとめ。
配布プロファイルの作成・アップロード・ストア掲載情報の入力には Apple Account の認証が必要。

## ✅ プロジェクト側で対応済み

- **プライバシーマニフェスト** `Landfall/PrivacyInfo.xcprivacy`
  - トラッキングなし。**収集あり**: メール/名前/ユーザーID/ユーザーコンテンツ(いずれも Linked・非トラッキング・App機能目的)。
    サインイン(Apple/Google)+ 同期(Firestore)に伴うもの。Required Reason API は UserDefaults(CA92.1)を宣言。
  - アーカイブに含まれるGoogle Sign-In / Firebaseのマニフェストも集約確認済み。
    Phone Number / Coarse Location / Device ID / Other Usage Data / Other Diagnostic Data /
    Other Data Types の追加回答は `STORE_METADATA.md` の App Privacy 節を参照。
- **輸出コンプライアンス** `ITSAppUsesNonExemptEncryption = NO`(Info.plist)→ 提出時の暗号化質問は不要
- **アプリアイコン** 標準1種+代替3種。全て1024×1024、アルファチャンネルなし
- **ローカライズ** 英語(既定)+ 日本語
- **Bundle ID** `com.tatsuyaariyama.Landfall` / **バージョン** 1.0 (build 1)
- **写真の権限**: 写真は PhotosPicker(PHPicker)経由のため `NSPhotoLibraryUsageDescription` は不要(アプリはフォトライブラリに直接アクセスしない)
- **App Check**: Release は App Attest を使い、entitlements の環境を `production` に固定。Debug/シミュレータだけデバッグプロバイダを使う。
- **署名方式**: 本体・Widgetとも自動署名へ統一。Developer PortalでApp Group / Sign in with Apple /
  App Attestを有効にした配布プロファイルを生成してから最終Archiveする。

## 🧑‍💻 あなたが行う手順

### 1. Apple Developer Program(有料・年99USD)
未加入なら https://developer.apple.com/programs/ から登録。

### 2. Xcode で署名 → Archive → アップロード
1. Xcode で `Landfall.xcodeproj` を開く
2. ターゲット > Signing & Capabilities で Team `SZ343VGXTL` と **Automatically manage signing** を確認
   - 本体: Sign in with Apple / App Groups / App Attest
   - Widget: App Groups
3. 実行先を **Any iOS Device (arm64)** に変更
4. メニュー **Product > Archive**
5. Organizer で **Distribute App > App Store Connect > Upload**

> シミュレータ用ビルドは提出できません。必ず実機(Any iOS Device)向けに Archive します。

### 3. App Store Connect でアプリ登録・掲載情報
https://appstoreconnect.apple.com で新規アプリを作成し、以下を入力:

- **Primary Language**: English (U.S.)
- **Name**: KeelMira(重複時は要調整)/ **Bundle ID**: com.tatsuyaariyama.Landfall / **SKU**: 任意
- **Category**: Productivity(第2カテゴリは任意で Education など)
- **Age Rating**: プライベート港にチャットがあるため、Messaging and Chat /
  User-Generated Content を実態どおり回答する。推測で「該当なし」にしない。
- **App Privacy**: ⚠️ **「Data Not Collected」は誤り。** STORE_METADATA.md の「App Privacy」節の通り、
  アプリ自身のデータに加え、Google Sign-In / Firebaseのマニフェストが宣言するデータも回答すること。
  マニフェスト `PrivacyInfo.xcprivacy` と一致させる。**審査中でも修正可能なので最優先で直す。**
- **Privacy Policy URL**: `https://aftide.app/privacy`
- **Support URL**: `https://aftide.app/privacy#support`
- **Description / Keywords / Promotional text**: ストア説明文(英語・任意で日本語も)
- **Screenshots**: 同じUIを各端末サイズで使う場合、最高解像度の6.9インチiPhone用を1〜10枚用意。
  6.5インチ以下は自動縮小を使えるため任意。PNG/JPEGにアルファチャンネルを含めない。
  日本語・英語とも `marketing/app-store/` に1320×2868、アルファなしの5枚を作成済み。
- **Export Compliance**: プロジェクトで宣言済みのため、アップロード後の質問はスキップされる想定

### 4. 提出
ビルドを選択 → 各項目を埋めて **Add for Review / Submit**。

## 次のアップデートを提出するとき

1. 本体・Widgetの `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を同時に上げる。
2. 機能やSDKの変更に合わせてApp Privacy、Privacy Manifest、年齢レーティングを再確認する。
3. Firestoreスキーマを変える場合は、クライアント公開より先にルールとインデックスをデプロイする。
4. What's Newとスクリーンショットを実際の新機能に合わせる。
5. 初回公開後、`LandfallLink.appStoreID` と `isPubliclyAvailable=true` を入れて更新版をビルド
   (共有カード・入港証にQR/リンクが出る)。

## 補足(実装は Firebase 版。以下は現状に合わせて更新済み)

- **サインインせずに利用可能**。端末内記録は使え、サインインは同期と港にだけ必要。
  App Review 情報の Notes にこの入口と、「Sign in with Apple で港を含む全機能を確認可能」と記載する。
- **アカウント削除を実装済み**。削除前の再認証、Appleトークン失効、共有チャット・共同航海UGC、
  Firestoreバックアップ、Web航海証の解約を含む。審査 Notes に明記推奨。
- 通知(ローカルのみ・既定オフ)・Firebase(Auth/Firestore)・App Check を含む。「完全ローカル」ではない。
- **App Check** をコンソールで enforcement ON にする場合は、審査ビルドが弾かれないよう
  App Attest付き実機リクエストを監視で確認してから(`docs/SECURITY.md` 参照)。**審査前に
  enforcement をいきなり ON にしないこと。**
- Firestoreルール・インデックス・認証削除後クリーンアップ関数は本番デプロイ済み。
- ストア説明文は STORE_METADATA.md を最新に是正済み(港=任意サインインを反映)。
