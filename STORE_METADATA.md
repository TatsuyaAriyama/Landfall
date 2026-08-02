# App Store 掲載文(ドラフト)

> **【最優先・審査リスク】App Privacy の是正が必要。**
> このアプリはサインイン(Apple/Google)・端末間同期・港での共有を持ち、`PrivacyInfo.xcprivacy` は
> メール/名前/ユーザーID/ユーザーコンテンツの収集(Linked・非トラッキング・App機能目的)を宣言している。
> 一方、下の説明文と App Privacy 回答は「収集なし・完全ローカル」と書いており **バイナリと矛盾**する。
> これは審査(5.1.1 / 2.3.1)で拒否される典型。**App Store Connect で App Privacy 回答を今すぐ修正すること**
> (下の「App Privacy」節に正しい回答を記載)。説明文の該当箇所も本ファイルで是正済み。

## App Name / アプリ名
- EN: `KeelMira`
- JA: `KeelMira`

## Subtitle(30文字以内)/ サブタイトル
- EN: `Turn Focus Into a Voyage`
- JA: `集中時間を航海に変える`

## Category / カテゴリ
- Primary: Productivity(仕事効率化)
- Secondary: Education(教育)— 任意

## Promotional Text(170文字以内、随時更新可)/ プロモーションテキスト
- EN: `Choose a work item, start the timer, and watch your voyage move forward. As the due date nears, your destination draws closer.`
- JA: `作業項目を選び、タイマーを始める。記録した時間だけ船が進み、期日が近づくほど目的地の島も近づきます。`

## Description / 説明文

### EN
```
KeelMira turns focused time into a 3D voyage.

FOCUS AND MOVE FORWARD
Choose a work item, then start a standard or Pomodoro timer. Every recorded minute becomes part of today's voyage. You can also add time manually, or start, pause, and finish a session from the widget.

SET A DESTINATION
Tap the sea and choose a distant island. Give it a name and due date. The island draws closer as the date approaches, making your goal feel present in the world around you.

LOOK BACK
Review and edit daily records in Trace. In the Logbook, leave a short reflection for today or yesterday. Turn a day's voyage into a shareable card whenever you want.

SAIL ALONE OR TOGETHER
The core experience works without an account. Sign in to sync across devices and enter the Harbor. Meet sailors with similar goals in public harbors, or use chat and a shared timer in a private harbor for up to four people.

MAKE IT YOURS
Customize your ship, sails, sailor, app icon, language, and appearance.

There are no streaks or leaderboards. Motivation comes in waves. Keep sailing anyway.
```

### JA
```
KeelMiraは、集中した時間を3Dの航海として残す作業・学習タイマーです。

■ 集中すると、船が進む
作業項目を選び、通常タイマーまたはポモドーロを開始。記録した時間が今日の航海になります。時間は手入力でき、ウィジェットから開始・休憩・着岸も操作できます。

■ 目的地を決める
海をタップして、遠くの島に名前と期日を設定。期日が近づくにつれて島も近づき、目標を景色の中で感じられます。

■ 振り返る
軌跡で日々の記録を確認・編集。航海誌には今日または昨日の短い感想を残せます。その日の航海は共有カードにして持ち出せます。

■ ひとりでも、仲間とも
基本機能はサインインなしで使えます。サインインすると端末間同期と港が利用可能。パブリック港で同じ目的を持つ航海士と出会い、プライベート港では最大4人でチャットと共通タイマーを使えます。

■ 自分らしい航海
船、帆、航海士、アプリアイコン、言語、外観をカスタマイズできます。

連続記録も順位もありません。モチベーションの波はある。それでも、航海を続けよう。
```

## Keywords(100文字以内、カンマ区切り、スペース節約)/ キーワード
- EN: `study,habit,log,streak,journal,focus,timer,reading,comeback,tracker,exam,routine`
- JA: `勉強,学習,記録,勉強垢,習慣,タイマー,受験,資格,読書,日記,再開,継続`
  - ※「勉強垢」「受験」「資格」は日本の学習ユーザーの検索意図が強い高価値語。app名・サブタイトルは
    別途インデックスされるので keyword には入れない。100文字/カンマ区切り(スペースは入れない)。

## What's New

### v1.1
- EN:
```
KeelMira now begins in a living 3D voyage.

• Set a distant island as your destination.
• Use standard and Pomodoro timers, manual entry, and the new widget controls.
• Review records in Trace and write short reflections in the Logbook.
• Meet sailors in public harbors or sail privately with up to four people.
• Customize your ship, sails, sailor, appearance, and app icon.
```
- JA:
```
KeelMiraの航海体験を新しくしました。

・3Dの海で遠くの島を目的地に設定できます。
・通常／ポモドーロタイマー、手入力、ウィジェット操作に対応しました。
・軌跡で記録を振り返り、航海誌に短い感想を残せます。
・パブリック港と、最大4人で使えるプライベート港を整えました。
・船、帆、航海士、外観、アプリアイコンをカスタマイズできます。
```

## Copyright
- `© 2026 Tatsuya Ariyama`

## App Privacy(質問票の回答 — `PrivacyInfo.xcprivacy` と一致させる)

**「Data Not Collected」は誤り。以下を App Store Connect に入力すること。**

- Tracking: **No**(トラッキングなし。IDFA/広告なし)
- KeelMira自身が扱うデータ(いずれも **Linked to identity=Yes / Used for tracking=No /
  用途=App Functionality**):
  1. **Contact Info → Email Address**(Apple/Google サインイン)
  2. **Contact Info → Name**(表示名・プレイヤー名)
  3. **Identifiers → User ID**(Firebase UID)
  4. **User Content → Other User Content**(学習記録・ひとこと・港のチャット/共同タイマー)
- 組み込みSDKの `PrivacyInfo.xcprivacy` が追加で宣言する項目も、App Store Connectで開示する:
  1. **Contact Info → Phone Number**(Google Sign-In / Linked / App Functionality)
  2. **Location → Coarse Location**(Google Sign-In / Linked / App Functionality)
  3. **Identifiers → User ID**(Google Sign-In / Linked / Analytics。App Functionalityと併記)
  4. **Identifiers → Device ID**(Google Sign-In / Linked / Analytics)
  5. **Usage Data → Other Usage Data**(Google Sign-In / Linked / Analytics)
  6. **Diagnostics → Other Diagnostic Data**(Firebase Auth/Firestore / Not Linked / Analytics)
  7. **Other Data → Other Data Types**(Google Sign-In / Linked / App Functionality + Analytics)

> Google Sign-Inの電話番号・概算位置などはKeelMiraの画面やFirestoreで直接保存しないが、
> 同梱SDKの公式プライバシーマニフェストが収集を宣言しているため、第三者SDK分として回答する。
> 全項目で **Used for tracking=No**。

> 記録の中核は端末内(SwiftData)だが、サインイン時に上記が Firebase(Auth/Firestore)へ同期・共有されるため
> 収集扱いになる。トラッキングは一切していない(NSPrivacyTracking=false)。

## Age Rating
- プライベート港にユーザー間チャットあり。年齢レーティング質問票では
  **Messaging and Chat / User-Generated Content を実態どおり回答**する。
- 有害表現の送信前フィルター、通報、ブロック、運営連絡先を実装済み。

## App Review Notes
```
KeelMira can be reviewed without an account: on the first screen, choose
"Continue without signing in." Work items, destinations, timers, Trace,
Logbook, appearance, notifications, and Settings are available in local mode.

Harbor and cross-device sync require an account. Sign in with Apple is available
on the first screen and provides access to those features. Private Harbor rooms
support up to four members, chat, and a shared timer. User-generated content has
pre-send filtering, reporting, blocking, sender deletion, and published support
contact information.

Account deletion is available in Settings > Account > Delete account. The app
reauthenticates the user, deletes associated Firebase and Harbor data, and
revokes the Apple token for accounts created with Sign in with Apple.

Voyage Pass is an optional auto-renewable subscription sold through StoreKit.
It lets the subscriber create one private Harbor for up to four sailors; invited
members can join that Harbor without purchasing. Restore Purchases and subscription
management are available in Settings. Notifications are local, optional, and off by default.
```

## Support URL / Marketing URL / Privacy Policy URL
- Support URL: `https://aftide.app/privacy#support`
- Marketing URL: `https://aftide.app`
- Privacy Policy URL: `https://aftide.app/privacy`
