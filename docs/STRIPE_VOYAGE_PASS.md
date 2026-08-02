# 航海証 / Voyage Pass

KeelMira Web の月額サブスクリプション。Stripe Checkout と Customer Portal を使い、
Stripe Webhook だけが Firestore の利用権限を書き換える。

## 商品

- 日本語名: 航海証
- 英語名: Voyage Pass
- 金額: 月額490円 / JPY 490 per month
- Stripe Productは1個、月額PriceはそのProductに1個作る

## Stripeテストモードの準備

1. Stripe DashboardでProduct「航海証 / Voyage Pass」を作る。
2. JPY 490、月次 recurring のPriceを作る。
3. Customer Portalで支払方法変更と期間末解約を有効にする。
4. 最小権限のRestricted API Keyをテストモードで作る。
   Customers、Checkout Sessions、Billing Portal Sessionsは書込、
   PricesとSubscriptionsは読取、Subscriptionsはアカウント削除時の解約に必要な書込権限を付ける。
5. Stripe DashboardのWebhookに、デプロイ後の `stripeWebhook` URLを登録する。

購読するイベント:

- `checkout.session.completed`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`

## Firebaseの準備

Cloud Functionsを使うためFirebaseプロジェクトをBlazeプランにする。

```sh
cd /path/to/Landfall
firebase functions:secrets:set STRIPE_RESTRICTED_KEY
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
```

秘密鍵はチャット、ソースコード、`.env` に貼らない。`STRIPE_RESTRICTED_KEY`には
可能な限り `rk_test_...` / `rk_live_...` のRestricted API Keyを使う。

Price IDと公開URLはデプロイ時のParameter入力に設定する。

```text
STRIPE_VOYAGE_PASS_PRICE_ID=price_...
PUBLIC_WEB_URL=https://aftide.app
```

## デプロイ

```sh
npm --prefix functions install
npm --prefix functions run build
npm --prefix web run build
firebase deploy --only functions,firestore:rules
```

Cloudflare Pagesは従来どおり `web/dist` を公開する。Functionsのデプロイ後に
表示された `stripeWebhook` のHTTPS URLをStripeへ登録し、そこで発行された
署名シークレットを `STRIPE_WEBHOOK_SECRET` に保存してFunctionsを再デプロイする。

## 動作確認

テストカード `4242 4242 4242 4242` を使い、次を確認する。

1. 未購入ユーザーの設定に「航海証」「月額 ¥490」が表示される。
2. Checkout完了後、自動で設定が開き、Webhook到着後に「有効」へ変わる。
3. 同じユーザーが再度購入操作をしてもCustomer Portalへ移動し、二重契約にならない。
4. 期間末解約後も期限までは有効で、期限後は無料状態へ戻る。
5. Webhookを重複送信しても `stripeEvents/{eventId}` により二重処理されない。
6. アカウント削除時に残存サブスクリプションが解約される。

## 本番前

- テスト用と本番用でAPI Key、Webhook secret、Price IDを完全に分ける。
- Stripe Dashboardの強い2要素認証とAPI Keyのアクセス制限を有効にする。
- 特定商取引法に基づく表示、利用規約、プライバシーポリシー、解約条件を公開する。
- 税登録を確認するまで `automatic_tax` は有効化しない。
