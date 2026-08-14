# Epic Online Services iOS 導入判断・セットアップ

- 最終調査日: 2026-08-15
- 対象: Landfall iOS（Swift / SceneKit、最低 iOS 17）
- 対象 SDK: Epic Online Services iOS C SDK 1.19.1.2（公式 archive ID 879）

この文書は、EOS Connect、Lobbies、P2P を Landfall のプライベート航海へ導入するための実装・審査・運用ゲートを定義する。現時点の推奨構成は次のとおり。

- 認証は Epic Account Services（`EOS_Auth`）ではなく EOS Connect（`EOS_Connect`）だけを使う。
- 既存の Sign in with Apple / Google は Firebase Authentication に集約し、Firebase ID token をカスタム OpenID credential として EOS Connect に渡す。
- Lobby は招待制、RTC は無効、P2P は `EOS_RC_ForceRelays` を既定にする。
- 人間向け招待コードは Firebase の短期 broker で解決し、EOS の公開 lobby attribute 検索には載せない。
- SDK 1.19.1.2 は実機 arm64 専用である。Simulator は EOS をリンクしない別実装・別ターゲットを維持する。
- 下記「リリースを止める条件」が一つでも未解決なら、本番導入は行わない。

## リリースを止める条件

1. Epic から、archive ID 879 の `SDK/Bin/IOS/EOSSDK.xcframework` が配布可能な Distributable Code であり、組織内 private SCM / private artifact registry / CI に保管できる旨の書面回答がない。
2. EOS Developer Portal の本番 Sandbox で Firebase ID token による OpenID login、token refresh、無効化済み Firebase user の拒否を実機で確認していない。
3. Simulator 用 stub/fallback と実機 EOS 実装を分離できず、通常の Simulator build が壊れる。
4. EOS が保持する Product User ID（PUID）、外部 account link、telemetry に対する削除・DSAR の運用経路を Epic と確認していない。
5. 2 台以上の実機で lobby、強制 relay P2P、background/foreground、Wi-Fi/携帯回線切替を完走していない。
6. Privacy Policy、App Store Connect の App Privacy、利用規約/EULA、第三者ライセンス表示、通報・ブロック導線が更新されていない。
7. signed Release archive の Validate と TestFlight 実機確認が終わっていない。

## 1. SDK 1.19.1.2 の実物検証

### 1.1 検証済み内容

公式取得物を `/tmp/eos-ios-sdk.A3NgMX` に展開して確認した。これは一時パスであり、ビルド設定へは記録しない。

| 項目 | 検証結果 |
| --- | --- |
| 取得元 | Epic 公式 iOS C SDK、archive ID 879 |
| version header | `1.19.1.2` |
| runtime version string | `1.19.1.2-53289219` |
| XCFramework library | `ios-arm64/EOSSDK.framework` の 1 library のみ |
| architecture / platform | Mach-O dynamic library、`arm64`、`iOS` |
| Simulator slice | なし。`ios-arm64-simulator`、`x86_64` ともになし |
| 最低 OS | iOS 15.0（Landfall の最低 iOS 17 は適合） |
| build SDK | iPhoneOS 18.1、Xcode 16.1 |
| install name | `@executable_path/Frameworks/EOSSDK.framework/EOSSDK` |
| privacy manifest | framework 内に `PrivacyInfo.xcprivacy` あり |
| SDK bundle内の法務資料 | `ThirdPartyNotices/ThirdPartySoftwareNotice.txt` のみ。SDK license/readme はなし |

供給物を pin する SHA-256 は次のとおり。ZIP は `/tmp/EOS-SDK-IOS-53289219-Release-v1.19.1.2.zip` でも再検証し、期待値と一致した。

| 対象 | SHA-256 |
| --- | --- |
| 公式 ZIP `EOS-SDK-IOS-53289219-Release-v1.19.1.2.zip` | `5f07ffe31db78ed0a5b71cfa344644221684cccea00eefe3a54514960660d179` |
| `EOSSDK.xcframework/ios-arm64/EOSSDK.framework/EOSSDK` | `65ed324049eed62aa56ec377225ac66bf6cbe2cff36d093f7162e1b71ce0160f` |
| `EOSSDK.xcframework/Info.plist` | `bb8f81ce985a36219cc81ebaca45b240b712257047760d9ec0df61db913d1afd` |
| framework `PrivacyInfo.xcprivacy` | `3147a293938c65366494138671313e33fadfa3b6ca112836d2fd723d4ea56413` |
| `ThirdPartySoftwareNotice.txt` | `9aa38890a43af9304c06ac03f8ba6288bba7373ad73474633b6200caf3198c32` |

archive には standalone の `SDK/Bin/IOS/EOSSDK.framework` もあるが、XCFramework 内の binary とは byte-identical ではない。採用品を途中で入れ替えてはならない。

### 1.2 署名の注意

- standalone の `SDK/Bin/IOS/EOSSDK.framework` は `Developer ID Application: Epic Games International, S.a.r.l. (96DBZ92D3Y)` で署名され、`codesign --verify --deep --strict` を通過した。
- 採用候補の `EOSSDK.xcframework/ios-arm64/EOSSDK.framework` は、取得物の状態では未署名だった。
- したがって device build では XCFramework の framework を app bundle へ embed し、アプリの distribution identity で署名する。Landfall は後述の device-only embed build phase でこれを行う。
- Epic 署名済み standalone framework の署名を、XCFramework の由来証明として扱ってはならない。供給元は公式 download、archive ID、取得日、ZIP SHA-256、runtime SHA-256 を別途記録する。

検証例:

```sh
shasum -a 256 "$EOS_SDK_ZIP"
shasum -a 256 "$EOS_SDK_ROOT/SDK/Bin/IOS/EOSSDK.xcframework/ios-arm64/EOSSDK.framework/EOSSDK"
plutil -p "$EOS_SDK_ROOT/SDK/Bin/IOS/EOSSDK.xcframework/Info.plist"
file "$EOS_SDK_ROOT/SDK/Bin/IOS/EOSSDK.xcframework/ios-arm64/EOSSDK.framework/EOSSDK"
xcrun vtool -show-build "$EOS_SDK_ROOT/SDK/Bin/IOS/EOSSDK.xcframework/ios-arm64/EOSSDK.framework/EOSSDK"
codesign --verify --deep --strict --verbose=4 \
  "$ARCHIVE_PATH/Products/Applications/Landfall.app/Frameworks/EOSSDK.framework"
```

起動時の diagnostic build では `EOS_GetVersion()` が `1.19.1.2-53289219` を返すことも確認する。version だけを記録し、credential、Firebase token、PUID、lobby ID はログへ出さない。

### 1.3 Xcode 26 build の確認結果

XCFramework を公式 `Samples/IOS/Login` が期待する場所へ置き、次の環境で unsigned generic-device build を実行した。

- Xcode 26.6（build 17F113）
- iPhoneOS 26.5 SDK
- `generic/platform=iOS`
- SDK sample の deployment target iOS 15.0

結果は `BUILD SUCCEEDED`。明示的にリンクされたものは `EOSSDK.xcframework` と `AuthenticationServices.framework` のみで、`OTHER_LDFLAGS` は不要だった。これは compile/link の適合確認であり、Landfall の署名、実機起動、Archive Validate、App Store upload の合格を意味しない。

Landfall での取得は `Scripts/install_eos_ios_sdk.sh` を唯一の標準手順とする。この script は公式 URL の archive ID 879 を取得し、上記 ZIP SHA-256 が一致しない限り展開せず、検証後の XCFramework だけを git-ignored の `Vendor/EOSSDK.xcframework` へ置く。既存 directory がある場合は暗黙に上書きせず、そのまま正常終了するため、CI は clean workspace で実行するか、既存 Vendor runtime の SHA-256 も上表と照合する。「already exists」の表示だけを検証成功とみなさない。SDK 更新では script の URL、version、ZIP/runtime hash を同一 review で更新し、旧/new の release notes と法務条項も再確認する。

## 2. Developer Portal の構成

[EOS Developer Portal](https://dev.epicgames.com/portal/) で、次の順に構成する。Portal の表示名は変更され得るため、保存後に得られる ID と権限を証跡として残す。

### 2.1 Organization と契約

1. Landfall を所有する同一法人/個人の Organization を使用する。
2. 開発者個人の Epic account を共有しない。必要な担当者を Team member として招待し、最小権限を付与する。
3. EOS Developer Agreement と利用する Standard Services の条項を Organization 名義で受諾する。
4. EAS を使わない限り、Epic Account Services application、brand review、Epic login permission は作らない。

### 2.2 Product、Sandbox、Deployment

1. Landfall 用 Product を一つ作成し、`ProductId` を記録する。
2. 少なくとも次を分離する。

| 環境 | Sandbox | Deployment | Client credentials | 用途 |
| --- | --- | --- | --- | --- |
| Development | 専用 | 専用 | 専用 | 開発実機、破壊的試験 |
| Staging | 専用 | 専用 | 専用 | TestFlight、審査前試験 |
| Production | 専用 | 専用 | 専用 | App Store 本番 |

3. 本番 credential を Debug/TestFlight の開発 build で使わない。環境の混在を起動時に拒否できるよう、bundle ID / build configuration と Sandbox/Deployment の対応を固定する。

SDK 起動に必要な値は次の 5 つ。

- `ProductId`
- `SandboxId`
- `DeploymentId`
- `ClientId`
- `ClientSecret`

`EncryptionKey` は Player Data Storage / Title Storage 用であり、今回の Connect/Lobbies/P2P だけなら `NULL` にする。RTC も `NULL` にする。

### 2.3 Client と Client Policy

1. 環境ごとに mobile client を作成する。
2. Connect、Lobbies、P2P に必要な action だけを許可する Client Policy を関連付ける。Portal が preset を要求する場合は公式例の `Peer2Peer` preset から始め、Production では実際に不要な action がないか監査する。
3. Reports/Sanctions を EOS 側で利用する場合だけ、その action を追加する。
4. Voice、Player/Title Data Storage、Achievements、E-commerce、Epic Account Services は今回の policy に含めない。
5. credential の失効・rotation 手順を作り、漏えい時に Production client だけを止められるようにする。

`ClientSecret` は iOS binary に組み込む以上、端末から抽出可能であり、サーバー secret にはならない。平文を public repository やログへ置かず、CI の保護された設定から build 時に注入する一方、実際の防御境界は Client Policy の最小権限、EOS/Firebase 側の rate limit、監視と失効に置く。サーバー用 OAuth credential や Firebase service-account key をアプリへ入れてはならない。

### 2.4 Identity Provider

各 Sandbox の Product Settings で custom OpenID provider を作り、有効化する。Landfall の第一候補は Firebase ID token を検証する専用 UserInfo endpoint 方式。

- issuer: `https://securetoken.google.com/<FIREBASE_PROJECT_ID>`
- audience: `<FIREBASE_PROJECT_ID>`
- stable account ID: 検証済み token の `sub` / Firebase UID
- display name: backend が返す検証済み・サニタイズ済み値
- EOS credential type: `EOS_ECT_OPENID_ACCESS_TOKEN`

Portal が JWKS 直接検証を提供していても、本番採用前に実 token で互換性を証明する。Firebase token は `name` claim を常に持つとは限らないため、display-name mapping が必要な構成では UserInfo endpoint の方が明示的である。display name を account ID に使ってはならない。

## 3. Firebase Authentication と EOS Connect

### 3.1 採用する identity flow

既存の Apple / Google sign-in は Firebase に残し、provider の違いにかかわらず一つの Firebase UID を一つの EOS PUID へ対応させる。

1. iOS が Firebase Auth の現在 user を確認する。
2. `getIDTokenForcingRefresh(false)` で **Firebase ID token** を取得する。Firebase custom token を渡してはいけない。
3. EOS SDK の `EOS_Connect_Login` を `EOS_ECT_OPENID_ACCESS_TOKEN` で呼ぶ。
4. EOS が custom OpenID provider を通じて token を検証する。
5. 成功時に PUID をセッション state へ保持する。
6. `EOS_InvalidUser` のときだけ callback の `ContinuanceToken` を一度 `EOS_Connect_CreateUser` へ渡す。他の error で user を作成しない。
7. `EOS_Connect_AddNotifyAuthExpiration` を登録する。通知時は新しい Firebase ID token を取得して `EOS_Connect_Login` を再実行する。
8. Firebase UID が切り替わったら、旧 lobby/P2P を完全に閉じ、旧 PUID callback を破棄してから新 user を login する。

Sign in with Apple の `identityToken` を `EOS_ECT_APPLE_ID_TOKEN` として直接渡す方法は採用しない。Firebase で Apple/Google を link 済みの同一 user が provider ごとに別 PUID になる危険があり、Firebase は Apple provider token を将来の EOS login 用に保持しないためである。すでに異なる PUID を作った user を統合する場合だけ、両方を明示的に再認証したうえで `EOS_Connect_LinkAccount` を使い、誤統合を防ぐ確認 UI と監査ログを用意する。

### 3.2 UserInfo endpoint の契約

EOS backend が Firebase token を検証する専用 HTTPS endpoint を用意する。通常の Firebase callable/App Check 必須 endpoint を流用しない。EOS からの request にはアプリの App Check token が付かないためである。

endpoint は以下を満たすこと。

- Portal で選んだ GET または POST の method と、Portal が定義する token carrier だけを受け付ける。通常は `Authorization: Bearer` だが、Development で EOS からの実 request を確認して固定する。
- Firebase Admin SDK の `verifyIdToken(token, true)` 相当で署名、有効期限、issuer、audience、失効/disabled user を検証する。
- request body/query に含まれた UID を信用せず、account ID は検証済み `sub` だけから作る。
- response は EOS が必要とする最小 field（stable account ID と display name）だけにする。email は返さない。
- display name は server-authoritative profile から取得し、Unicode 制御文字、改行、bidi override を除去し、長さと文字種を制限する。空の場合は非個人情報の固定 fallback を返す。
- token、Authorization header、UID、display name を access/error log へ残さない。Cloud logging の request header/body capture も確認する。
- 厳しい request/response size、timeout、同時実行数、global rate limit、検証後の per-UID rate limit、WAF/abuse alert を設定する。caller は EOS backend なので、固定 source IP を仮定した allowlist や強い per-IP limit は採用しない。
- App Check を外す例外はこの endpoint に限定し、他の Firebase API の認可を広げない。
- Development/Staging/Production で URL と audience を分離する。

Firebase ID token の `aud`、`iss`、`sub` の条件は [Firebase: Verify ID Tokens](https://firebase.google.com/docs/auth/admin/verify-id-tokens) に従う。

### 3.3 account deletion

SDK 1.19.1.2 の Connect header には PUID 自体を削除する公開 client API が見当たらない。`EOS_Connect_DeleteDeviceId` は Device ID credential の削除であり、Firebase/OpenID の PUID 削除ではない。

Landfall の「アカウント削除」は少なくとも次を一つの追跡可能な job として行う。

1. 新規 EOS login と invite 発行を停止する。
2. lobby を leave/destroy し、全 P2P connection と notification を閉じる。
3. Firebase/Firestore/Storage の user data、invite-code mapping、Firebase UID↔PUID mapping、端末 cache を削除する。
4. Sign in with Apple user は Apple token を revoke する。
5. EOS が保持する PUID、external account association、last-seen/telemetry の削除依頼を、Epic が指定する DSAR/support 経路へ送る。
6. 完了/保留/法的保持を user に明示し、再試行可能な状態を保存する。

手順 5 の正式 API/SLA/必要 identifier が Epic から確認できるまでは Production を開始しない。

## 4. Xcode / Swift 統合

### 4.1 framework と linker

法務確認後、`Scripts/install_eos_ios_sdk.sh` で検証・配置した XCFramework を使う。Project へ XCFramework の無条件 PBX file reference を追加しない。現在の device-only 構成は次のとおり。

1. `FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]` だけに `Vendor/EOSSDK.xcframework/ios-arm64` を追加する。
2. `OTHER_LDFLAGS[sdk=iphoneos*]` だけに `-framework EOSSDK` を追加する。`-ObjC` と `-all_load` は追加しない。
3. `SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphoneos*]` に `EOS_SDK_AVAILABLE` を追加し、EOS bridge source をこの条件で囲む。
4. `LD_RUNPATH_SEARCH_PATHS` に `$(inherited)` と `@executable_path/Frameworks` を維持する。
5. `Embed EOSSDK on Device` build phase は `PLATFORM_NAME != iphoneos` なら何もせず終了する。device では source framework を app の `Frameworks` へコピーし、embedded copy の Headers/Modules を除き、署名可能 build なら `EXPANDED_CODE_SIGN_IDENTITY` で codesign する。`PrivacyInfo.xcprivacy` は残す。
6. EOS credential は protected build setting から `EOSProductID`、`EOSSandboxID`、`EOSDeploymentID`、`EOSClientID`、`EOSClientSecret` の generated Info.plist key へ注入する。空のままなら EOS transport を開始しない。
7. Release archive で framework、privacy manifest、署名、arm64 slice を確認する。

公式 iOS Login sample は EOSSDK と `AuthenticationServices.framework` を明示 link し、追加の `OTHER_LDFLAGS` を使わず Xcode 26.6 で成功した。一方、Landfall は既存 Apple sign-in を Swift 側で持ち、EOS の link は上記 device 条件付き `-framework EOSSDK` に限定している。unresolved symbol が出ない限り system framework flag を重複追加しない。

EOS binary 自体は UIKit、Foundation、WebKit、SafariServices、AuthenticationServices、GameKit、StoreKit、DeviceCheck、UserNotifications、AdSupport、iAd などの system framework を参照する。Xcode 26.6 / iPhoneOS 26.5 では公式 sample の link に成功したが、OS beta/GM と SDK 更新ごとに再試験する。

### 4.2 Swift bridge と thread model

公式 sample と同様に、C API の pointer/handle/callback lifetime を Objective-C++ shim（`.mm` + `.h`）へ閉じ込め、Swift へは `async` な値型 API を公開する。SceneKit node や Swift object の pointer を EOS の `ClientData` に直接保持しない。

- 全 EOS API call と `EOS_Platform_Tick` を一つの専用 serial thread/executor に集約する。
- callback は Tick を実行した thread で処理される前提とし、UI/SceneKit 更新前に `MainActor` へ移す。
- callback context は request ID と generation を持ち、logout、Firebase UID 切替、scene teardown 後の古い callback を破棄する。
- EOS handle と notification ID を owner object で管理し、release/remove を一度だけ行う。
- token、PUID、lobby ID、socket name、raw packet を production log に出さない。

初期化順序:

1. `EOS_Initialize` を process lifetime に一度だけ呼ぶ。
2. PII/token を redact する logging callback を設定する。本番は必要最小 log level にする。
3. `EOS_Platform_Create` を `ProductId`、`SandboxId`、`DeploymentId`、client credential で呼ぶ。
4. `bIsServer = EOS_FALSE`、`EncryptionKey = NULL`、`RTCOptions = NULL`、`IntegratedPlatformOptionsContainerHandle = NULL` とする。
5. iOS Social Overlay を使わないため `Flags` に `EOS_PF_DISABLE_OVERLAY` を設定する。
6. 独立した coordinator から `EOS_Platform_Tick` を定期実行する。SceneKit view の render loop だけに結び付けない。
7. Firebase→Connect login、Lobby、P2P の順に開始する。

終了順序:

1. gameplay send を停止する。
2. P2P connection を閉じ、通知を remove する。
3. lobby を leave/destroy し、Lobby 通知を remove する。
4. search/details/modification など全 handle を release する。
5. `EOS_Platform_Release` を一度だけ呼ぶ。
6. process 終了時に `EOS_Shutdown` を一度だけ呼ぶ。

### 4.3 lifecycle、Info.plist、background

- `sceneDidEnterBackground` 相当で gameplay send を停止し、`EOS_Platform_SetApplicationStatus(..., EOS_AS_BackgroundSuspended)` を通知する。
- foreground 復帰時は Tick より先に `EOS_AS_Foreground` を通知し、Firebase token、Connect status、lobby membership、host epoch を再同期する。
- `NWPathMonitor` で offline/online を検知し、`EOS_Platform_SetNetworkStatus` へ反映する。
- EOS P2P の維持を理由に `UIBackgroundModes` を追加しない。既存 `audio` mode は実際の audio playback のためだけに使う。
- Connect-only custom OpenID は browser redirect を使わないため、EOS 用 URL scheme は不要。
- Lobby RTC/voice は無効なので microphone usage description は不要。将来 voice を有効にする変更は別の privacy/permission review とする。
- EOS internet relay は Bonjour/LAN discovery ではないため `NSLocalNetworkUsageDescription` は追加しない。
- ATT は tracking を行わない限り要求しない。

### 4.4 Simulator を壊さない構成

XCFramework の `SupportedPlatform` は `ios`、architecture は `arm64` だけで、`SupportedPlatformVariant = simulator` がない。Apple Silicon Simulator も同じ arm64 だから動く、という扱いはできない。platform ABI が異なるためである。

Landfall では共通の `PrivateIslandRealtimeTransport` protocol の下で、`iphoneos` build だけが `EOS_SDK_AVAILABLE` の EOS adapter を compile/link し、Simulator は Firestore compatibility transport を使う。framework search path、link flag、embed phase の三つすべてを `iphoneos` に限定するため、Simulator は EOS binary を参照しない。Epic が公式 simulator slice を提供した場合だけ、hash と license を再確認してこの判断を見直す。

`EXCLUDED_ARCHS`、`lipo`、binary 書換え、device binary の weak-link で回避しない。App target が XCFramework を無条件参照すると、コードを `#if targetEnvironment(simulator)` で囲んでも XCFramework 選択段階で build が失敗し得る。現在の conditional build setting/embed phase を崩さず、Simulator の link graph から EOS binary dependency 自体を外す。

## 5. Lobby と招待コード

### 5.1 8 人用 lobby の既定値

- `MaxLobbyMembers = 8`
- `PermissionLevel = EOS_LPL_INVITEONLY`
- `bPresenceEnabled = EOS_FALSE`
- `bAllowInvites = EOS_TRUE`
- `bEnableRTCRoom = EOS_FALSE`
- `LocalRTCOptions = NULL`
- `bRejoinAfterKickRequiresInvite = EOS_TRUE`
- host migration は、ゲーム state の authority 移管を実装できる場合だけ有効にする

EOS 1.19.1.2 header 上の上限は、1 user あたり lobby 16、1 lobby 64 members、search results 200、attributes 64、attribute name 64 文字である。Landfall 側ではこれより小さい上限を固定する。

### 5.2 人間向け招待コード

EOS Lobbies に「短い人間向け code の非公開・一意検索」という primitive はない。次を採用する。

1. host が InviteOnly lobby を作成する。
2. Firebase backend が cryptographically random な code（例: Crockford Base32 10 文字以上、約 50 bit）を atomic に予約し、`code → lobby ID / host PUID / expiresAt / generation` を保存する。
3. joiner は Firebase Auth + App Check 付き endpoint へ code を送り、per-UID/per-IP rate limit 下で join request を作る。存在の有無を区別し過ぎない error と一定時間応答を使う。
4. host は認可済み join request を受け、joiner PUID が block/ban 対象でないことを確認して `EOS_Lobby_SendInvite` を呼ぶ。
5. joiner は invite notification から lobby details handle を取得し、`EOS_Lobby_JoinLobby` で参加する。
6. 成功、期限切れ、host 終了、lobby generation 更新時に code と request を無効化する。code の再利用は禁止する。

`bAllowInvites = EOS_TRUE` では、owner 以外の member も invite を送れる。backend broker は改変 client による直接 invite を完全には止められないため、host は member-status notification ごとに approved join-request allowlist を照合し、未承認または block/ban 対象の PUID を即座に kick する。この host-side 検査を実装できない版は、招待制を security boundary とみなさない。

公開 lobby attribute に `JOIN_CODE` を入れて `EOS_LobbySearch_SetParameter` で検索する案は採用しない。`EOS_LPL_PUBLICADVERTISED` と public attribute は検索結果に露出し、短い code の列挙と重複を防げない。

`EOS_Lobby_JoinLobbyById` は SDK header で integrated platform の native invite 向け special case とされている。人間向け code の主経路にはせず、採用する場合は Epic の用途確認、`bEnableJoinById`、lobby ID の安全な配送、推測耐性を別途証明する。4〜60 文字の `LobbyId` override と backend 自動採番を同じ環境で混在させない。

### 5.3 host migration

EOS が lobby owner を移しても、SceneKit/gameplay の authoritative state は自動移管されない。

- migration 有効時は owner-change notification を受け、新 host が snapshot、sequence、member list、socket epoch を再発行する。
- 全 peer は旧 host/旧 epoch の packet を拒否する。
- state 移管を完成できない初期版は `bDisableHostMigration = EOS_TRUE` とし、host 離脱時に session を明示終了する。

## 6. P2P relay と packet 安全性

1. connection を作る前に全 client で `EOS_P2P_SetRelayControl(..., EOS_RC_ForceRelays)` を呼ぶ。これにより peer 間の直接 IP 露出を避ける。Epic relay は通信元 IP/network metadata を処理するため、Privacy Policy で「IP を一切処理しない」とは表現しない。
2. `EOS_P2P_SetPacketQueueSize` で有限 queue を設定し、incoming queue-full notification を監視する。unlimited のままにしない。
3. connection request/established/interrupted/closed、incoming queue-full の notification を登録する。
4. `RemoteUserId` が現在の同一 lobby member で、block/ban 対象でなく、`SocketName` が現在の session secret と一致するときだけ connection を accept する。
5. 8 人では host-star topology を使い、全員 mesh を既定にしない。
6. 1 tick の receive packet 数と処理時間に上限を置く。`EOS_P2P_GetNextReceivedPacketSize` → `EOS_P2P_ReceivePacket` を `EOS_NotFound` まで回すが、frame budget を超えたら次 tick へ送る。
7. packet header の protocol version、lobby/generation、sender membership、host epoch、sequence、channel、payload length を検証してから decode する。
8. SDK 上限の `EOS_P2P_MAX_PACKET_SIZE = 1170` bytes を超えず、Landfall protocol の packet 上限は 1,024 bytes とする。session control、discrete world、chat、snapshot control/delta は `ReliableOrdered`、channel 5 の `SnapshotChunk` は index/hash/missing-bitmap repair 付き `ReliableUnordered`、channel 1 の live motion は sequence 付き `UnreliableUnordered` とする。
9. malformed/oversize/replay/flood packet は SceneKit state へ渡さず破棄し、閾値超過 user を切断・通報できるようにする。
10. leave/logout/background/UID 切替で connection を閉じ、notification を remove し、socket secret と epoch を rotate する。

`SocketName` は最大 32 文字である。短い招待 code をそのまま使わず、lobby ごとの高 entropy secret から生成する。

wire format、channel、host migration、snapshot reassembly、chat evidence の規範は [EOS_MULTIPLAYER_ARCHITECTURE.md](./EOS_MULTIPLAYER_ARCHITECTURE.md) とし、この文書と矛盾するときは protocol version を伴う同時 review で解消する。

## 7. Privacy、App Store、利用者保護

### 7.1 SDK 同梱 privacy manifest

SDK 1.19.1.2 は tracking を `false` とし、次を宣言している。

| data type | linked | purpose |
| --- | --- | --- |
| Gameplay Content | yes | App Functionality |
| Product Interaction | yes | Analytics, App Functionality |
| Performance Data | no | Analytics |
| Email Address | yes | App Functionality |
| User ID | yes | App Functionality |
| Name | yes | App Functionality |

Required Reason API は UserDefaults、reason `CA92.1`。

Apple は app 自身の privacy manifest に third-party SDK の宣言を重複させる必要はないとしているが、Xcode の Privacy Report で framework manifest が最終 archive に統合されることを確認する。App Store Connect の App Privacy は app と第三者 SDK を合わせた実態を申告するため、上記と実測 network/data flow を反映する。Email を UserInfo endpoint から返さない場合でも、EOS manifest と Epic の説明だけで「収集なし」と断定せず、Epic に用途を確認してから申告を狭める。

### 7.2 Privacy Policy に追加する内容

- service provider: Epic Online Services / Epic Games
- Firebase UID に由来する external account ID、EOS PUID、display name、lobby membership/attributes、invite/join metadata、gameplay content/packets
- network/IP metadata と quality-of-service telemetry
- Epic Agreement が示す random session ID、API call count、latency、HTTP/internal status code
- app functionality、multiplayer、security/abuse prevention、service analytics という目的
- linked/unlinked の区別と tracking を行わないこと
- 米国その他での国際処理、Epic の最新 [Subprocessors](https://onlineservices.epicgames.com/services/terms/subprocessors?lang=en-US) への link
- retention、account deletion、DSAR の受付窓口と完了見込み
- relay は peer 同士の direct IP 露出を抑えるが、service provider による network data 処理をなくすものではないこと

### 7.3 App Review

- Guideline 1.2 対応として、user-generated display name/lobby metadata/content の投稿前 filter、通報、timely response、user block、公開 contact を用意する。Public Journal の通報/ブロックが PUID/lobby/P2P にも適用されることを確認する。
- block 済み PUID から lobby invite、connection request、packet を受け付けない。UI で隠すだけにしない。
- account creation があるため、Guideline 5.1.1(v) に従い app 内から全 account と関連 data の削除を開始できるようにする。
- Sign in with Apple user の削除時には Apple token revoke も行う。
- Review Notes に、二つの demo account、二台での lobby 作成/参加手順、招待 code の取得場所、EOS が実機専用であることを記載する。
- EOS を理由に background mode、microphone、local network permission を追加しない。
- EOSSDK は 2026-08-15 時点で Apple の「署名/privacy manifest が必須の listed SDK」一覧にはないが、開発者は third-party code 全体へ責任を負う。リストと SDK を release ごとに再確認する。

## 8. 法務・再配布

これは法的助言ではない。Production へ入れる前に、受諾主体と法務担当が [EOS Developer Agreement](https://onlineservices.epicgames.com/services/terms/agreements?lang=en-US) の最新版を確認する。

特に次が重要。

- §3.1 は Distributable Code を object code の inseparable part として game の end user へ配布する権利を与え、end-user EULA で Epic Materials に関する representations、warranties、conditions、liabilities を明示的に免責することを要求する。
- §12 は Distributable Code を Epic が `Distributable Code` という subdirectory で提供した component と定義する。しかし archive ID 879 にはその名称の directory がなく、framework は `SDK/Bin/IOS` にある。
- 公式 iOS sample が framework の embed を前提にしているため技術的意図は明白だが、契約文言とのずれは解釈で埋めない。Epic Support に archive ID、version、path を示し、App Store 配布と private SCM/artifact/CI 保管の可否を書面で確認する。
- public repository への SDK/framework/header/sample の掲載は、end user への inseparable object-code distribution ではないため行わない。
- private repository も、同一契約主体の必要最小 member のみに限定する。外部 contractor/CI vendor が Licensed EOS Developer に該当するか不明なら access を与える前に確認する。
- Client credential は Agreement §3.3.2 に従って扱う。第三者や public source へ共有しない。
- §5.1 により SDK Update は原則 3 年以内に追随する。四半期ごとに release notes と security update を確認する owner を置く。
- §6.5 により `ThirdPartyNotices/ThirdPartySoftwareNotice.txt` の attribution/license を遵守する。全文を Legal/Open Source Licenses 画面または同梱文書から到達可能にする。
- §6.6 の QoS metrics と §11 の国際 data processing を Privacy Policy と data inventory に反映する。
- 契約終了時の SDK/Service 停止・copy 破棄要件を dependency removal runbook に含める。

XCFramework だけを private artifact registry に保存し、SDK archive、Tools、Samples、top-level framework/header の別コピーを repository へ入れない。ただし XCFramework 内の Headers/Modules/PrivacyInfo を削除・改変してはならない。

## 9. 実装 API 順序

最小の成功経路は次の順序で実装・テストする。

1. device-only bridge: `EOS_Initialize` → logging → `EOS_Platform_Create` → Tick/lifecycle/network status。
2. Connect: Firebase ID token → `EOS_Connect_Login` → `EOS_InvalidUser` のみ `EOS_Connect_CreateUser` → auth-expiration notification。
3. Lobby notifications を登録し、InviteOnly lobby の create/leave/destroy を実装する。
4. Firebase invite-code broker と `EOS_Lobby_SendInvite` → invite details → `EOS_Lobby_JoinLobby` を実装する。
5. P2P を ForceRelays、有限 queue、membership/socket validation 付きで接続する。
6. host-authoritative state と packet codec の version/epoch/sequence/rate validation を実装する。
7. kick/block/report、account deletion、UID switch、background/foreground の teardown/recovery を実装する。
8. Simulator stub、unit/fuzz test、実機 matrix、TestFlight、Privacy/EULA/Review metadata の順に release gate を通す。

## 10. 実機受入条件

### Build / supply chain

- [ ] `Scripts/install_eos_ios_sdk.sh` が archive ID 879 を取得し、ZIP SHA-256 `5f07ffe31db78ed0a5b71cfa344644221684cccea00eefe3a54514960660d179` を検証してから Vendor へ配置した。
- [ ] 既存 Vendor を再利用した build でも runtime SHA-256 `65ed324049eed62aa56ec377225ac66bf6cbe2cff36d093f7162e1b71ce0160f` を照合した。
- [ ] 公式 download の archive ID、取得日、ZIP SHA-256、runtime SHA-256 を CI inventory に保存した。
- [ ] Xcode の Release archive が `arm64` で成功し、Archive Validate と upload が成功した。
- [ ] archive 内 `Frameworks/EOSSDK.framework` が app の distribution identity で署名され、`PrivacyInfo.xcprivacy` を含む。
- [ ] `EOS_GetVersion()` が pin 済み version を返す。
- [ ] Simulator scheme は EOS binary を参照せず、既存 Simulator test/install を完走する。

### Identity

- [ ] Apple/Google の既存 Firebase user が同じ Firebase UID→同じ PUID になる。
- [ ] 新規 user は `EOS_InvalidUser` のときだけ一度作成され、retry で重複しない。
- [ ] token expiration 通知後に session を落とさず再 login できる。
- [ ] revoked/disabled/deleted Firebase user は UserInfo endpoint と EOS login で拒否される。
- [ ] UID switch、logout、account deletion 後に旧 callback/packet/state が表示されない。
- [ ] endpoint の load、rate limit、timeout、error normalization、log redaction を確認した。

### Lobby / invite

- [ ] 同時参加 8 人上限、9 人目拒否、重複 join、二重 callback を確認した。
- [ ] 正常 code、誤 code、期限切れ、総当たり、replay、同時 redeem を確認した。
- [ ] block/ban user は invite、join、rejoin、P2P の全層で拒否される。
- [ ] host leave/app kill/network loss で、選択した migration 方針どおり復旧または明示終了する。
- [ ] lobby destroy 後に code mapping と pending request が残らない。

### P2P / SceneKit

- [ ] 全 client が connection 前に `EOS_RC_ForceRelays` を設定したことを diagnostic で確認した。
- [ ] iOS 17 と現行 iOS、Wi-Fi同士、携帯回線同士、Wi-Fi↔携帯、IPv6-only/NAT 条件で接続する。
- [ ] background/foreground、画面 lock、network 切替、host interruption から安全に復旧する。
- [ ] malformed、1170 bytes 超、unknown channel、wrong lobby/epoch、replay、flood を安全に破棄する。
- [ ] queue 上限と frame budget 下で memory が増え続けず、SceneKit main thread が stall しない。
- [ ] relay latency、packet loss、帯域を計測し、8 人 host-star の UX 基準を満たす。
- [ ] peer IP、token、PUID、lobby/socket secret が UI、analytics、log、crash report に出ない。

### Privacy / review / operations

- [ ] Xcode Privacy Report と App Store Connect App Privacy が EOS manifest と実通信に一致する。
- [ ] Privacy Policy、利用規約/EULA、third-party notices、support contact が app から到達可能である。
- [ ] lobby participant の report/block と運用 SLA を確認した。
- [ ] app 内 account deletion が Firebase、user content、invite data、EOS DSAR job まで追跡する。
- [ ] Epic agreement、client policy、identity-provider config、subprocessor list の変更監視 owner が決まっている。
- [ ] TestFlight の二台実機 smoke test と reviewer 用 demo account/手順が用意されている。

## 11. 公式資料

### Epic

- [EOS SDK download / Get Started](https://onlineservices.epicgames.com/sdk?lang=en-US)
- [EOS Developer Portal](https://dev.epicgames.com/portal/)
- [EOS Get Started Guide](https://dev.epicgames.com/docs/epic-online-services/eos-get-started/get-started-guide)
- [Client Policy Guide](https://dev.epicgames.com/docs/epic-online-services/eos-fundamentals/client-and-client-policy/client-policy-guide)
- [Online Subsystem EOS: Connect-only login behavior](https://dev.epicgames.com/documentation/en-us/unreal-engine/online-subsystem-eos-plugin-in-unreal-engine)
- [Lyra with EOS: Portal client and Peer2Peer policy example](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-lyra-with-epic-online-services-in-unreal-engine)
- [Identity Provider Management](https://dev.epicgames.com/docs/epic-online-services/eos-fundamentals/identity-provider-management)
- [Social Overlay features by SDK/platform](https://dev.epicgames.com/docs/epic-online-services/accounts-and-social/social-overlay/features-by-SDK-version)
- [External Credential Types](https://dev.epicgames.com/docs/api-ref/enums/eos-e-external-credential-type?lang=en-US)
- [EOS Connect Login](https://dev.epicgames.com/docs/api-ref/functions/eos-connect-login)
- [EOS Connect Create User](https://dev.epicgames.com/docs/api-ref/functions/eos-connect-create-user)
- [EOS Connect Auth Expiration Notification](https://dev.epicgames.com/docs/api-ref/functions/eos-connect-add-notify-auth-expiration)
- [EOS Lobby Create](https://dev.epicgames.com/docs/api-ref/functions/eos-lobby-create-lobby)
- [EOS Lobby Join by ID](https://dev.epicgames.com/docs/api-ref/functions/eos-lobby-join-lobby-by-id)
- [EOS P2P Relay Control](https://dev.epicgames.com/docs/api-ref/functions/eos-p-2-p-set-relay-control)
- [EOS Developer Agreement and Service Addenda](https://onlineservices.epicgames.com/services/terms/agreements?lang=en-US)
- [EOS Subprocessors](https://onlineservices.epicgames.com/services/terms/subprocessors?lang=en-US)
- [EOS Licensing](https://onlineservices.epicgames.com/licensing)

### Firebase / Apple

- [Firebase: Verify ID Tokens](https://firebase.google.com/docs/auth/admin/verify-id-tokens)
- [Firebase iOS: Authenticate Using Apple](https://firebase.google.com/docs/auth/ios/apple)
- [Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple: Offering Account Deletion in Your App](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [Apple: Describing Data Use in Privacy Manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests)
- [Apple: App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple: Manage App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [Apple: Third-party SDK Requirements](https://developer.apple.com/support/third-party-SDK-requirements/)
