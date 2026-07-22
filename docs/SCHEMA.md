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
| `styleToken` | string | `midnight / coral / ink / seaGreen / violet / sunYellow` |
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

### `users/{uid}/destinations/{uuid}` — 目的地(島)

学習の目標を「島」として置く。到達した日が Landfall(着岸)。アクティブは3つまで(クライアント制約)。

| フィールド | 型 | 備考 |
|---|---|---|
| `name` | string | 島の名前。≤60 |
| `itemUUID` | string? | 紐づく項目。省略時は全記録が進捗に数えられる |
| `targetMinutes` | number? | 累計時間の目標(分)。作成時刻以降の記録を数える |
| `targetDate` | timestamp? | 期日の目標。経過時間で船が近づく |
| `createdAt` | timestamp | 進捗の起点 |
| `achievedAt` | timestamp? | 着岸した日。設定後は「到達した島」として航海誌に残る |
| `updatedAt` | timestamp | |

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

### `rooms/{code}/members/{uid}/months/{yyyy-MM}` — 月ごとの共有記録

書き・消しは本人のみ。上書き型(その月の全量を毎回書く)。

| フィールド | 型 | 備考 |
|---|---|---|
| `days` | array ≤31 | `{ day: number(1〜31), note?: string }` |
| `sessions` | array ≤1000 | `{ day: number, minutes: number, itemName: string, itemStyle: string, itemSymbol: string, note?: string }` |
| `updatedAt` | timestamp | serverTimestamp |

### `rooms/{code}/quest/current` — 港の試練(単一ドキュメント)

島の手前に海獣(kraken)または嵐(storm)が立ちはだかり、メンバー全員の学習時間の
合算で退ける協力イベント。読みは在港者のみ。作成・削除は在港者なら誰でも(友人港なので簡素に)。

| フィールド | 型 | 備考 |
|---|---|---|
| `kind` | string | `kraken / storm` |
| `targetMinutes` | number(int) | 目標時間(分)。60〜600000 |
| `createdAt` | timestamp | 進捗の起点。これ以降の記録だけを数える |
| `createdBy` | string | 作成者(= auth.uid 必須)。権限はない |
| `defeatedAt` | timestamp? | 討伐の刻印。**一度だけ** 在港者の誰かが書ける(update は defeatedAt の追加のみ許可) |

**進捗はカウンタを持たない。** 各メンバーの `members/{uid}/months/{yyyy-MM}`(創設月〜当月)の
`sessions` のうち `date >= createdAt` の `minutes` を全員分合算して、閲覧者が導出する。
`date` が無い旧セッションは `day` から日単位で概算する。合算が `targetMinutes` に達したのを
見た閲覧者が `defeatedAt` を書き、全員の購読(onSnapshot)にライブ反映される。
討伐済みの港のメンバーは限定の船パーツ(帆 `moonlight` / 旗 `kraken`)を解放する
(解放はクライアントのローカルフラグ。サーバー検証はしない)。

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
| `reactions` | map | `{ [uid]: 'lighthouse' | 'anchor' | 'phoenix' }`。更新は自分の枠のみ |

削除は自分の発言のみ。

---

## 3. `publicHarbors/{slug}/…` — パブリックの港(公式5港)

slug は固定: `language / certification / student / reading / making`(ルールの許可リストと一致)。
参加すると名前・アイコン・作業記録がその港に表示される。
**読みはサインイン済みなら誰でも。書き・消しは本人のみ。** チャットは無い。

### `publicHarbors/{slug}/members/{uid}`

`rooms/{code}/members/{uid}` と同じフィールド(displayName / styleToken / symbolToken / resolve / joinedAt + 任意の boatSail / boatJib / boatHull / boatStripe / boatFlag)。

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
