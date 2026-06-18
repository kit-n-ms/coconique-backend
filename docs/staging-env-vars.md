# Coconique Step 7-6 ステージング環境変数表

更新日: 2026-06-18

この表は **Step 7-6 安定ベース**で staging を立てるためのものです。Step 7-7 の `km-auth-starter` 系名称変更はまだ採用しません。

重要:

- staging でも `RAILS_ENV=production` を使う
- staging 判定は `APP_ENV=staging` で行う
- DB / Stripe / Didit / Resend / R2 / secret は production と完全分離する
- `app.stg.coconique.jp` と `api.stg.coconique.jp` は別サブドメインなので、CSRF cookie をWeb側が読めるよう `AUTH_COOKIE_DOMAIN=.stg.coconique.jp` を設定する

---

## Web / Vite

Cloudflare Pages の staging branch 用。

```env
VITE_API_BASE_URL=https://api.stg.coconique.jp
VITE_APP_KEY=coconique
VITE_CSRF_COOKIE_NAME=coconique_csrf
VITE_COCONIQUE_PUBLIC_APP_ORIGIN=https://app.stg.coconique.jp
```

Cloudflare Pages Preview Deployment URLも、可能ならCloudflare Accessで保護する。難しい場合は検証URLを `app.stg.coconique.jp` に集約する。

---

## Rails 基本

Render staging Web Service / Worker 共通。

```env
RAILS_ENV=production
APP_ENV=staging
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true
CURRENT_APP_KEY=coconique
SECRET_KEY_BASE=...
DATABASE_URL=postgres://...

FRONTEND_ORIGIN=https://app.stg.coconique.jp
CORS_ALLOWED_ORIGINS=https://app.stg.coconique.jp
CHECKOUT_ALLOWED_HOSTS=app.stg.coconique.jp
AUTH_COOKIE_NAME=coconique_session
CSRF_COOKIE_NAME=coconique_csrf
AUTH_COOKIE_DOMAIN=.stg.coconique.jp
AUTH_COOKIE_SECURE=true
AUTH_COOKIE_SAME_SITE=lax
REQUIRE_ORIGIN_FOR_UNSAFE_REQUESTS=true
```

### Cookie domainについて

フロントは `app.stg.coconique.jp`、APIは `api.stg.coconique.jp` に分かれる。現在のフロントは `document.cookie` からCSRF cookieを読み、`X-CSRF-Token` に載せる。

そのため、APIが発行する `coconique_csrf` cookie は `app.stg.coconique.jp` から読める必要がある。stagingでは必ず以下を設定する。

```env
AUTH_COOKIE_DOMAIN=.stg.coconique.jp
```

productionでは以下にする。

```env
AUTH_COOKIE_DOMAIN=.coconique.jp
```

---

## メール

```env
MAIL_PROVIDER=resend
RESEND_API_KEY=re_...
RESEND_WEBHOOK_SECRET=...
MAIL_FROM=no-reply@stg.coconique.jp
SUPPORT_EMAIL=support@coconique.jp
FRONTEND_EMAIL_VERIFICATION_URL=https://app.stg.coconique.jp/verify-email
FRONTEND_PASSWORD_RESET_URL=https://app.stg.coconique.jp/reset-password
```

stagingの送信先制限を行う場合は、Resend側の設定またはアプリ側の将来フラグで制御する。

---

## Stripe / Test mode

```env
COCONIQUE_BILLING_PROVIDER=stripe
COCONIQUE_USE_FAKE_STRIPE_CHECKOUT=false

STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_FOUNDER_MONTHLY=price_...
STRIPE_COUPON_FIRST_MONTH_100=...
STRIPE_PRICE_HOST_TICKET=price_...
STRIPE_TAX_ENABLED=false
STRIPE_BILLING_PORTAL_RETURN_URL=https://app.stg.coconique.jp/app/settings

COCONIQUE_FIRST_MONTH_AMOUNT_JPY=100
COCONIQUE_MONTHLY_AMOUNT_JPY=430
COCONIQUE_MONTHLY_HOST_TICKETS=5
COCONIQUE_ADDITIONAL_HOST_TICKET_AMOUNT_JPY=1000
COCONIQUE_ADDITIONAL_HOST_TICKET_MONTHLY_LIMIT=5
COCONIQUE_CAPTURE_STRIPE_CARD_FINGERPRINT=true
```

stagingでは必ず `sk_test_` / `pk_test_` を使う。live keyは入れない。

Webhook endpoint:

```txt
https://api.stg.coconique.jp/webhooks/stripe
```

Cloudflare Accessで `*.stg.coconique.jp` を保護する場合も、このpathはbypassする。保護はStripe署名検証で行う。

---

## Didit

```env
COCONIQUE_IDENTITY_PROVIDER_PRIMARY=didit
COCONIQUE_IDENTITY_PROVIDER_FALLBACK=fake_identity
COCONIQUE_USE_FAKE_IDENTITY=false
COCONIQUE_ALLOW_FAKE_IDENTITY=false

DIDIT_API_BASE_URL=https://verification.didit.me
DIDIT_API_KEY=...
DIDIT_WORKFLOW_ID_STANDARD=...
DIDIT_WEBHOOK_SECRET=...
DIDIT_MY_NUMBER_CARD_ENABLED=false
DIDIT_SSL_ALLOW_CRL_FAILURE=false
COCONIQUE_IDENTITY_PUBLIC_RETURN_URL=https://app.stg.coconique.jp/identity/return
```

Webhook endpoint:

```txt
https://api.stg.coconique.jp/webhooks/didit
```

Cloudflare Accessで `*.stg.coconique.jp` を保護する場合も、このpathはbypassする。保護はDidit署名検証で行う。

---

## SMS

SMSは初期必須から撤去済み。Twilio Verifyは将来用にコードだけ残す。

```env
COCONIQUE_SMS_PROVIDER=fake
```

---

## 再登録防止シグナル

```env
COCONIQUE_REENTRY_SIGNAL_SECRET=<32文字以上の固定ランダム文字列>
COCONIQUE_CAPTURE_STRIPE_CARD_FINGERPRINT=true
```

注意: `COCONIQUE_REENTRY_SIGNAL_SECRET` は運用開始後に変えると過去digestと照合できなくなるため、staging/prodで別々に固定する。

---

## リクエスト時の同期間引き

```env
COCONIQUE_REQUEST_SYNC_INTERVAL_SECONDS=60
```

---

## Cloudflare Access

対象:

```txt
*.stg.coconique.jp
```

保護対象:

```txt
app.stg.coconique.jp
api.stg.coconique.jp
admin.stg.coconique.jp
```

Bypass対象:

```txt
api.stg.coconique.jp/webhooks/stripe
api.stg.coconique.jp/webhooks/didit
api.stg.coconique.jp/webhooks/resend
api.stg.coconique.jp/webhooks/quick_trust
```

WebhookはAccessではなくProvider署名検証で守る。

---

## 実行確認

```bash
bin/rails db:migrate
bin/rails coconique:doctor
bin/rails coconique:staging:doctor
bin/rails coconique:stripe:doctor
bin/rails coconique:stripe:verify_remote
bin/rails coconique:identity:doctor
```

`coconique:staging:doctor` で `cookie domain` がNGになる場合、`AUTH_COOKIE_DOMAIN=.stg.coconique.jp` を確認する。
