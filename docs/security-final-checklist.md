# Security Final Checklist

Hodokoo / Coconique へ派生する前、本番化する前に確認するセキュリティ項目。

## Secrets

- `.env` をzipに含めない
- `.env.local` をzipに含めない
- `config/master.key` を含めない
- `config/credentials/*.key` を含めない
- Stripe secret key を共有しない
- Resend API key を共有しない
- Webhook secret を共有しない
- API key をスクショに出さない

## Cookie / CSRF

- `AUTH_COOKIE_NAME` はプロダクトごとに分ける
- `CSRF_COOKIE_NAME` はフロントとAPIで一致させる
- 本番では `COOKIE_SECURE=true`
- `COOKIE_SAME_SITE` を用途に合わせて確認する
- CSRF token必須のwrite APIを確認する

## CORS / Host Authorization

- `FRONTEND_ORIGIN` を本番URLにする
- `CORS_ALLOWED_ORIGINS` を必要最小限にする
- ngrok host許可はdevelopment限定にする
- wildcard許可を本番に入れない

## Admin API

- adminのみ200
- generalは403
- guestは401
- 管理APIに過剰な個人情報を返していないか確認
- DELETE / PATCH 系はAuditLogを残す

## Stripe

- Webhook署名検証あり
- `checkout.session.completed` は冪等処理
- 付与creditsをclientから信頼しない
- product/amount/creditsはDB側で確認する
- test key / live key を混同しない

## Resend

- Resend Webhook署名検証あり
- raw bodyで検証している
- `svix-id` を冪等キーとして扱う
- bounced / complained / failed / suppressed をEmailSuppressionに保存する
- suppression解除はadmin限定

## Mail

- `MAIL_PROVIDER=resend`
- `ActionMailer::Base.delivery_method == :resend_custom`
- `app/lib/resend_delivery_method.rb` をhandoff zipに含める
- FromドメインがResendでverified
- 本番メール本文にlocalhost URLを含めない

## Logs / Data

- logをzipに含めない
- tmpをzipに含めない
- storageをzipに含めない
- テストユーザーを本番seedに入れない
- 実メールアドレスをdocsに残さない

## Legal / Compliance

- 利用規約バージョンをENVで管理
- プライバシーポリシーバージョンをENVで管理
- Hodokooでは非弁法配慮文言を必ず追加
- Coconiqueでは本人確認・通報・ブロック・モデレーション方針を別途設計
