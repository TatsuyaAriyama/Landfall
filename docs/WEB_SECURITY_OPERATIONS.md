# Aftide Web セキュリティ運用

## 実装済みの防御

- Firebase Authentication（Google / Apple）を認証境界とし、未認証アクセスを
  Firestore Rulesで拒否する。
- Firestore Rulesで所有者、共有港の所属、入力フィールド、型、文字数・件数を検証する。
- Firebase App Check（reCAPTCHA Enterprise）のトークンを本番Webクライアントで利用する。
- Stripeの秘密情報はGoogle Secret Managerだけに保存し、クライアントへ渡さない。
- Stripe Webhookは署名を検証し、イベントIDで重複処理を防止する。
- HTTPセキュリティヘッダーで、外部スクリプト・フレーム・接続先、埋め込み、
  MIME誤認、不要な端末権限、参照元情報を制限する。
- DOMへHTML文字列を代入せず、テキストとイベントをDOM APIで構築する。
- 任意ファイルのアップロード機能を提供しない。

## 定期診断

GitHub Actionsの `Security checks` を毎週月曜日に実行する。

1. コミット済みファイルの秘密情報パターン検査
2. 本番依存パッケージの既知脆弱性監査（high以上で失敗）
3. lintと本番ビルド
4. OWASP ZAPによる `https://aftide.app` のベースライン診断

ZAPで問題が検出された場合はGitHub Issueを作成し、修正完了まで追跡する。
依存関係監査またはビルドが失敗した場合、修正前に本番へ反映しない。

## リリース前

```sh
npm --prefix web ci
npm --prefix web run security:check
```

ローカルでは `.githooks/pre-commit` がStripe本番キー、Webhook署名シークレット、
Googleサービスアカウント秘密鍵の誤コミットを防止する。初回だけ次を実行する。

```sh
git config core.hooksPath .githooks
```

## アカウント運用

- StripeとGoogleの管理者アカウントではパスキーまたは認証アプリによる二要素認証を使う。
- 管理者を追加する場合は共有IDを作らず、個別アカウントを発行する。
- 不要になった管理者権限は即日削除する。
- APIキーは環境ごと・用途ごとに分離し、最小権限のRestricted Keyを使う。
- 不審な操作を確認した場合はキーを直ちにローテーションし、Stripe Workbenchと
  Google Cloud Loggingの操作履歴を確認する。
