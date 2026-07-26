# Landfall Firestore スキーマ(iOS / Web 共通の契約)

このファイルが **スキーマの正典**。iOS(Swift)と Web(TypeScript)はコードを共有できないため、
コレクション構造・フィールド型・docID 規約・上限値はここに合わせる。
変更するときは、このファイル・iOS・Web・`firestore.rules` を **同一コミット** で更新すること。

- Firebase プロジェクト: `landfall---study-log`
- 認証: Firebase Auth(Apple / Google)。全コレクションでサインイン必須。
- 時刻はすべて Firestore `timestamp`。競合解決は `updatedAt` による Last-Write-Wins。

---

## 1. `users/{uid}/…` — 個人の記録(本人のみ読み書き)

iOS はローカル(SwiftData)が真実で Firestore はバックアップ/端末間コピー。
Web はローカルストアを持たず Firestore を直接読み書きする(同じ書式で書けば iOS 側へも
リアルタイムに同期される)。

### `users/{uid}/items/{itemUUID}` — 学習項目(タイル)

docID = 項目の UUID 文字列(大文字ハイフン形式。Web で新規作成するときは `crypto.randomUUID()` を大文字化)。

| フィールド | 型 | 備考 |
|---|---|---|
| `name` | string | 項目名。表示上限60文字 |
| `styleToken` | string | `midnight / coral / ink / seaGreen / violet / sunYellow`(項目タイルはこの6色のみ) |
| `symbolToken` | string | `anchor / compass / wheel / lighthouse / island / phoenix / book / pen`(旧: `wave→anchor, comet→compass, sun→lighthouse` に読み替え) |
| `sortOrder` | number(int) | グリッドの並び順 |
| `createdAt` | timestamp | |
| `updatedAt` | timestamp? | LWW。v1.0 の書類には無い場合がある |

表紙写真(`photoData`)は **同期対象外**(iOS 端末ローカルのみ)。

### `users/{uid}/sessions/{sessionUUID}` — 1回の作業記録

| フィールド | 型 | 備考 |
|---|---|---|
| `date` | timestamp | 作業開始日時。日への帰属はこの日付 |
| `minutes` | number(int) | 分。0〜6000 |
| `note` | string? | ひとこと。上限120文字 |
| `itemUUID` | string? | 紐づく項目の docID |
| `updatedAt` | timestamp? | LWW |

### `users/{uid}/days/{yyyy-MM-dd}` — 「学んだ日」の刻印

docID = `yyyy-MM-dd`(端末ローカルのタイムゾーンでの startOfDay)。
**StudyDay の存在そのものが「学んだ日」**。セッションが全て消えた日は days も消す。

| フィールド | 型 | 備考 |
|---|---|---|
| `date` | timestamp | その日の startOfDay |
| `note` | string? | その日のひとこと(セッションのメモとは別)。上限120文字 |
| `updatedAt` | timestamp? | LWW |

### `users/{uid}/voyageLogs/{yyyy-MM-dd}` — 航海日録

航海誌に残す一日一件の自由記録。作業記録がない日にも書けるため、`days` の
「学んだ日」刻印とは独立している。docID は端末ローカル日付の `yyyy-MM-dd`。

| フィールド | 型 | 備考 |
|---|---|---|
| `date` | timestamp | その日の startOfDay |
| `body` | string | 本文。1〜260文字 |
| `updatedAt` | timestamp | LWW |

### `users/{uid}/destinations/{uuid}` — 目的地(島)

学習の目標を「島」として置く。到達した日が Landfall(着岸)。アクティブは1つまで(クライアント制約、`MAX_ACTIVE_DESTINATIONS`)。

| フィールド | 型 | 備考 |
|---|---|---|
| `name` | string | 島の名前。≤60 |
| `itemUUID` | string? | 紐づく項目。省略時は全記録が進捗に数えられる |
| `targetMinutes` | number? | 累計時間の目標(分)。作成時刻以降の記録を数える |
| `targetDate` | timestamp? | 期日の目標。経過時間で船が近づく。`manual=true` のときは締切のメモ表示のみ(進捗には影響しない) |
| `targetHasTime` | boolean? | `targetDate` に時刻まで含まれるか。false/未設定なら「その日いっぱい」= 締切はその日の 23:59:59.999(`destinationDeadline`) |
| `manual` | boolean? | 完了ゴール(3つ目の目標種類)。時間や日数で測れない課題向け |
| `manualDone` | boolean? | 完了ゴールで本人が「完了にする」を押したか。**このアプリで唯一の手動達成** — 記録からは自動導出しない |
| `steps` | array? | ステップ目標(4つ目の目標種類)。長期の大きな目標を小さな目印に分解。要素 `{ id: string, name: string(≤60), scheduledAt?: timestamp, doneAt?: timestamp }`。`scheduledAt` は予定日時、`doneAt` は達成日時。最大20(`MAX_STEPS`)。非空なら他の目標種類とは排他 |
| `createdAt` | timestamp | 進捗の起点 |
| `achievedAt` | timestamp? | 着岸した日。設定後は「到達した島」として航海誌に残る |
| `updatedAt` | timestamp | |

目標種類は4つ: 期日(`targetDate`)/ 累計時間(`targetMinutes`)/ 完了(`manual`+`manualDone`)/ ステップ(`steps`)。
完了ゴールは `manualDone`、ステップ目標は全 `steps` の `doneAt` が立った瞬間に `destinationProgress` が
`reached: true` を返し、既存の「到達検知→`achievedAt`を刻んで着岸を祝う」処理(`DestinationsSection`)が
そのまま働く。ステップ目標の進捗は「達成数/全数」で、航路にブイの目印が浮かぶ(点灯=達成)。
期日の締切は `destinationDeadline()` に一本化してある。**日付だけの期日は「その日の終わり」が締切**で、
`targetHasTime` が立っているときだけ `targetDate` の時刻をそのまま締切に使う。日付を 00:00 として扱うと
今日を期日にした瞬間に締切を過ぎたことになり即着岸してしまうため、この解釈を必ず通すこと。進捗の比率も
日単位に丸めず実時刻で計算する(丸めると同じ日のうち船が動かない)。

Web / iOS は同一 Firestore を共有し、`steps.scheduledAt` と `steps.doneAt` を相互に同期する。

---

## 2. `rooms/{code}` — プライベートの港(招待コード制・最大4人)

docID = 6文字の招待コード(コードが合鍵)。定員4人・参加は3港まで・作成は1人1港(`ownerUid`)。

| フィールド | 型 | 備考 |
|---|---|---|
| `name` | string | 港名 1〜80文字。作成後は不変 |
| `memberIds` | string[] | uid の配列。更新は「自分だけを出し入れ」のみ |
| `ownerUid` | string | 作成者。不変。権限はない(作成数制限のためだけ) |
| `createdAt` | timestamp | 不変 |

### `rooms/{code}/members/{uid}` — プレイヤーカード

読みは同じ港のメンバーのみ。書き・消しは本人のみ。

| フィールド | 型 | 上限 |
|---|---|---|
| `displayName` | string | 60 |
| `styleToken` | string | 24 |
| `symbolToken` | string | 24 |
| `resolve` | string | 80 |
| `sinceDay` | string? | 10 |
| `joinedAt` | timestamp | |
| `boatSail` | string? | 24 |
| `boatJib` | string? | 24 |
| `boatHull` | string? | 24 |
| `boatStripe` | string? | 24 |
| `boatFlag` | string? | 24 |

`boat*` は船の見た目の部位 id(`BOAT_OPTIONS` の id。例 `sand / coral / none / pennant`)。
港の「みんなの海」で各メンバーの船を再現するために使う。**任意**フィールド —
書かない旧クライアント(iOS v1.x)の従来5フィールド書き込みもそのまま有効。
未知・欠損の id は読み手が既定(砂色/なし)に落とす。

`sinceDay` は**このサービスを使い始めた日**。書式は `yyyy-MM-dd`(書いた人の暦。
`users/{uid}/days` の docID と同じ規約)で、ルールもこの書式だけを通す。**任意**フィールド —
無い場合、読み手は何も表示しない(「不明」とは書かない)。

値の決め方は Web の `web/src/since.ts`(`serviceStartDay`)が正典で、iOS もこれに合わせる:
基準は**アカウントを作った日**(Firebase Auth の `creationTime`。サーバ由来なので端末を
またいでも同じ)。ただし記録の方が古いこともありうる(手入力・端末の時計ずれ・他プラット
フォームからの移行)ので、`days` / `sessions` の最古日がそれより前ならそちらを採る。
2000-01-01 より前の値は、日付が欠けて 1970 に落ちた書類とみなして無視する。

自分のカードでは毎回その場で計算するが、港のメンバーへはこの `sinceDay` として書き出す
(相手は他人の `days` / `sessions` を全部は読めないため)。読み手は自分のカードと同じ
「2025年3月14日から航海中」(`sailingSince`)の書式でカードに添える。

### `rooms/{code}/members/{uid}/months/{yyyy-MM}` — 月ごとの共有記録

書き・消しは本人のみ。上書き型(その月の全量を毎回書く)。

| フィールド | 型 | 備考 |
|---|---|---|
| `days` | array ≤31 | `{ day: number(1〜31), note?: string }` |
| `sessions` | array ≤1000 | `{ day: number, minutes: number, itemName: string, itemStyle: string, itemSymbol: string, note?: string }` |
| `updatedAt` | timestamp | serverTimestamp |

### `rooms/{code}/voyage/current` — 共同航海(単一ドキュメント)

目的地までの時間を決めると `seed` から海図(3航路: 凪 calm / 嵐 squall / 深み deep)が
ひらき、選んだ1本を全員で進む協力イベント。航路の中身(波形・嵐/海獣の海域の位置)は
`seed` からクライアントが決定的に導出する(`web/src/voyageMap.ts` の `generateRoutes`)ので
ここには置かない。読みは在港者のみ。作成・削除は在港者なら誰でも(友人港なので簡素に)。

| フィールド | 型 | 備考 |
|---|---|---|
| `seed` | number(int) | 海図の種。≥0。全員がここから同じ海図を導出する |
| `targetMinutes` | number(int) | 目的地までの時間(分)。60〜600000 |
| `routeIndex` | number(int) | 選んだ航路。0〜2 |
| `createdAt` | timestamp | 進捗の起点。これ以降の記録だけを数える |
| `createdBy` | string | 作成者(= auth.uid 必須)。権限はない |
| `arrivedAt` | timestamp? | 到着の刻印。**一度だけ** 在港者の誰かが書ける(update は arrivedAt の追加のみ許可) |

**進捗はカウンタを持たない。** 各メンバーの `members/{uid}/months/{yyyy-MM}`(出航月〜当月)の
`sessions` のうち `date >= createdAt` の `minutes` を全員分合算して、閲覧者が導出する。
`date` が無い旧セッションは `day` から日単位で概算する。進捗率が海域の区間に入ると
3Dの海に嵐/海獣が現れ、区間を抜けると晴れる/沈む。合算が `targetMinutes` に達したのを
見た閲覧者が `arrivedAt` を書き、全員の購読(onSnapshot)にライブ反映される。
到着した航路に戦利品があれば、メンバーは限定の船パーツを解放する
(嵐の航路=帆 `moonlight`、深みの航路=旗 `kraken`。解放はクライアントの
ローカルフラグ。サーバー検証はしない)。

### `rooms/{code}/quest/current` — 旧「港の試練」(廃止)

共同航海(voyage)に置き換え済み。ルールはデプロイ済みの旧クライアントの読み取りの
ために残置している。新規の書き込みはもう発生しない。

### `rooms/{code}/chat/{messageId}` — チャット(プライベートのみ)

| フィールド | 型 | 備考 |
|---|---|---|
| `uid` | string | 送信者(= auth.uid 必須) |
| `kind` | string | `text / landfall / return` |
| `text` | string | kind=text のみ。1〜500文字 |
| `itemName` / `itemStyle` / `itemSymbol` | string | kind=landfall/return のみ。itemName≤60 |
| `minutes` | number(int) | 同上。≤6000 |
| `gapDays` | number(int) | kind=return の空白日数 |
| `createdAt` | timestamp | |
| `reactions` | map | `{ [uid]: 'heart' | 'lighthouse' }`。更新は自分の枠のみ |

削除は自分の発言のみ、かつ `createdAt` から1時間以内(ルールで強制。クライアントも同じ窓で削除ボタンを隠す)。

---

## 3. `publicHarbors/{slug}/…` — パブリックの港(公式5港)

slug は固定: `language / certification / student / reading / making`(ルールの許可リストと一致)。
参加すると名前・アイコン・作業記録がその港に表示される。
**読みはサインイン済みなら誰でも。書き・消しは本人のみ。** チャットは無い。

### `publicHarbors/{slug}/members/{uid}`

`rooms/{code}/members/{uid}` と同じフィールド(displayName / styleToken / symbolToken / resolve / joinedAt + 任意の sinceDay / boatSail / boatJib / boatHull / boatStripe / boatFlag)。

### `publicHarbors/{slug}/members/{uid}/months/{yyyy-MM}`

`rooms` 側の months と同じ書式。記録は月ごとに積み上がって残り、消せるのは本人だけ。
退港 = 自分の members ドキュメントと全 months の削除。

---

## 4. `reports/{reportId}` — 通報(書き捨て)

create のみ可(`reporterUid == auth.uid`)。読みは運営(コンソール)のみ。

| フィールド | 型 |
|---|---|
| `reporterUid` | string |
| `roomId` | string |
| `targetUid` | string |
| `messageId` | string? |
| `text` | string? ≤500 |
| `createdAt` | timestamp |

---

## デザイントークン(参考: 見た目の契約)

Web も iOS と同じパレット・原則(フラット塗りのみ・影/グラデーション/絵文字なし・角丸20px・font-weight ≤500)。

| トークン | Light | Dark |
|---|---|---|
| `ink` | `#141414` | `#F4F1EC` |
| `paper` | `#FFFFFF` | `#161412` |
| `tileInk` | `#141414` | `#2C2A28` |

固定ブランド色: `sunYellow #FFD84D` / `seaGreen #5DCAA5` / `coral #F0997B` / `deepRust #4A1B0C` /
`midnight #1A1130` / `lavender #CECBF6` / `violet #534AB7` / `returnOrange #F5822A` /
`harborTeal #184A40` / `harborSand #EADEBD` / `emberGold #F3C065`

タイル配色(背景/前景): midnight→coral、coral→deepRust、ink(tileInk)→sunYellow、
seaGreen→midnight、violet→lavender、sunYellow→deepRust

プレイヤーカードは上の6色に加えて、次の6色も選べる(既存のブランド色の組み替えのみ。
新しい色は足さない)。項目タイルはグリッドの一覧性を保つため6色のままにする:
harbor(harborTeal→harborSand)、sand(harborSand→deepRust)、ember(emberGold→deepRust)、
rust(deepRust→emberGold)、lavender(lavender→violet)、sunrise(returnOrange→midnight)。
`members/{uid}.styleToken` は自由文字列(≤24)なので、知らないトークンを受け取った
読み手は midnight に落とす。古いクライアントには新しい6色が midnight として見える。
