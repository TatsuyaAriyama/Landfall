# App Store 提出チェックリスト

Landfall を App Store に提出するための手順と、記載が必要な項目のまとめ。
署名・アップロード・ストア掲載情報の入力は Apple ID 認証が必要なため、**あなた自身が**行う必要があります(Claude では代行不可)。

## ✅ プロジェクト側で対応済み

- **プライバシーマニフェスト** `Landfall/PrivacyInfo.xcprivacy`
  - トラッキングなし。**収集あり**: メール/名前/ユーザーID/ユーザーコンテンツ(いずれも Linked・非トラッキング・App機能目的)。
    サインイン(Apple/Google)+ 同期(Firestore)に伴うもの。Required Reason API は UserDefaults(CA92.1)を宣言。
- **輸出コンプライアンス** `ITSAppUsesNonExemptEncryption = NO`(Info.plist)→ 提出時の暗号化質問は不要
- **アプリアイコン** 1024pt を含むフルセット(ミッドナイト/コーラルの2種)
- **ローカライズ** 英語(既定)+ 日本語
- **Bundle ID** `com.tatsuyaariyama.Landfall` / **バージョン** 1.0 (build 1)
- **写真の権限**: 写真は PhotosPicker(PHPicker)経由のため `NSPhotoLibraryUsageDescription` は不要(アプリはフォトライブラリに直接アクセスしない)

## 🧑‍💻 あなたが行う手順

### 1. Apple Developer Program(有料・年99USD)
未加入なら https://developer.apple.com/programs/ から登録。

### 2. Xcode で署名 → Archive → アップロード
1. Xcode で `Landfall.xcodeproj` を開く
2. ターゲット > Signing & Capabilities で **あなたの Team** を選択(Automatically manage signing)
3. 実行先を **Any iOS Device (arm64)** に変更
4. メニュー **Product > Archive**
5. Organizer で **Distribute App > App Store Connect > Upload**

> シミュレータ用ビルドは提出できません。必ず実機(Any iOS Device)向けに Archive します。

### 3. App Store Connect でアプリ登録・掲載情報
https://appstoreconnect.apple.com で新規アプリを作成し、以下を入力:

- **Primary Language**: English (U.S.)
- **Name**: Landfall(重複時は要調整)/ **Bundle ID**: com.tatsuyaariyama.Landfall / **SKU**: 任意
- **Category**: Productivity(第2カテゴリは任意で Education など)
- **Age Rating**: 質問票に回答 → 本アプリは該当項目なしで **4+** 見込み
- **App Privacy**: ⚠️ **「Data Not Collected」は誤り。** STORE_METADATA.md の「App Privacy」節の通り、
  メール/名前/ユーザーID/ユーザーコンテンツの収集(Linked・非トラッキング・App機能目的)を宣言すること。
  マニフェスト `PrivacyInfo.xcprivacy` と一致させる。**審査中でも修正可能なので最優先で直す。**
- **Privacy Policy URL**(全アプリで必須): サインイン・Firestore 同期・港での共有・保持と削除を反映した
  ポリシーを公開してURLを登録(`docs/privacy-policy.html` を土台に)。「収集しない」旨のポリシーは使えない。
- **Support URL**(必須): 問い合わせ先ページのURL
- **Description / Keywords / Promotional text**: ストア説明文(英語・任意で日本語も)
- **Screenshots**: 必須サイズ(6.9インチ/6.5インチ iPhone 等)。シミュレータのスクショから用意可能 — 必要なら生成を手伝えます
- **Export Compliance**: プロジェクトで宣言済みのため、アップロード後の質問はスキップされる想定

### 4. 提出
ビルドを選択 → 各項目を埋めて **Add for Review / Submit**。

## 次のアップデートを提出するとき(v1.0 承認後)

1. **バージョンを上げる**(必須)。現状 pbxproj に不整合がある:
   - アプリ本体 `MARKETING_VERSION = 1.0`、ウィジェット拡張 `= 1.1` で **食い違っている**。
     アップロード検証で「拡張のバージョンが本体と一致しない」で弾かれる。
   - 提出前に **本体と LandfallWidget の MARKETING_VERSION を同じ値**(例 1.1)にそろえ、
     両方の `CURRENT_PROJECT_VERSION`(ビルド番号)を **2 以上**(前回=1 より大きく)にする。
2. App Store Connect で **App Privacy の回答を是正**(上記。最優先)。
3. 港/同期を使うなら Firestore ルールをデプロイ、App Check を有効化(順序注意。docs/SECURITY.md)。
4. What's New を STORE_METADATA.md の下書きから貼る。スクショは新機能を含める。
5. 公開されたら `LandfallLink.appStoreID` と `isPubliclyAvailable=true` を入れて再ビルド
   (共有カード・入港証にQR/リンクが出る)。

## 補足(実装は Firebase 版。以下は現状に合わせて更新済み)

- **サインインが必須の画面がある**(SignInView が入口を塞ぐ)。Apple のガイドライン上、
  **Sign in with Apple を提供済み**なのでこの点は満たす。Google サインインを審査員が試す場合に備え、
  App Review 情報の「Notes」に「Sign in with Apple で全機能を確認できます」と一言添えると安全。
- **アカウント削除を実装済み**(設定 → アカウント削除。5.1.1(v) 要件を満たす)。審査 Notes に明記推奨。
- 通知(ローカルのみ・既定オフ)・Firebase(Auth/Firestore)・App Check を含む。「完全ローカル」ではない。
- **App Check** をコンソールで enforcement ON にする場合は、審査ビルドが弾かれないよう
  デバッグトークン登録と監視での確認を先に(`docs/SECURITY.md` 参照)。**審査前に enforcement を
  いきなり ON にしないこと。**
- Firestore ルールの強化版は `firestore.rules` にあり、`firebase deploy` が必要(未デプロイ)。
- ストア説明文は STORE_METADATA.md を最新に是正済み(港=任意サインインを反映)。
