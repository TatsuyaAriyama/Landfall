# App Store 提出チェックリスト

Landfall を App Store に提出するための手順と、記載が必要な項目のまとめ。
署名・アップロード・ストア掲載情報の入力は Apple ID 認証が必要なため、**あなた自身が**行う必要があります(Claude では代行不可)。

## ✅ プロジェクト側で対応済み

- **プライバシーマニフェスト** `Landfall/PrivacyInfo.xcprivacy`
  - トラッキングなし / データ収集なし / Required Reason API は UserDefaults(CA92.1)のみ宣言
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
- **App Privacy**: **Data Not Collected**(何も収集しない)を選択
- **Privacy Policy URL**(全アプリで必須): 「データを収集しない」旨の簡単なポリシーをどこかに公開してURLを登録
- **Support URL**(必須): 問い合わせ先ページのURL
- **Description / Keywords / Promotional text**: ストア説明文(英語・任意で日本語も)
- **Screenshots**: 必須サイズ(6.9インチ/6.5インチ iPhone 等)。シミュレータのスクショから用意可能 — 必要なら生成を手伝えます
- **Export Compliance**: プロジェクトで宣言済みのため、アップロード後の質問はスキップされる想定

### 4. 提出
ビルドを選択 → 各項目を埋めて **Add for Review / Submit**。

## 補足

- サインイン不要のアプリなのでレビュー用デモアカウントは不要
- 通知・計測SDK・外部通信なし(完全ローカル)なので、審査で問われやすい項目は少ない
- ストア説明文の英語ドラフトが必要なら用意します
