# Coconique ステージング環境変数表

更新日: 2026-06-17

## Web / Vite

```env
VITE_API_BASE_URL=https://coconique-api-staging.example.com
VITE_APP_KEY=coconique
VITE_CSRF_COOKIE_NAME=coconique_csrf
VITE_COCONIQUE_PUBLIC_APP_ORIGIN=https://coconique-staging.example.com
```

## Rails 基本

```env
RAILS_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true
CURRENT_APP_KEY=coconique
FRONTEND_ORIGIN=https://coconique-staging.example.com
CHECKOUT_ALLOWED_HOSTS=coconique-staging.example.com,localhost,127.0.0.1
SESSION_COOKIE_NAME=coconique_session
CSRF_COOKIE_NAME=coconique_csrf
SECRET_KEY_BASE=...
DATABASE_URL=postgres://...
```

## Stripe / Staging は Test mode

```env
COCONIQUE_BILLING_PROVIDER=stripe
COCONIQUE_USE_FAKE_STRIPE_CHECKOUT=false
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_FOUNDER_MONTHLY=price_test_monthly_430
STRIPE_COUPON_FIRST_MONTH_100=coupon_test_330_off_once
STRIPE_PRICE_HOST_TICKET=price_test_host_ticket_1000
STRIPE_TAX_ENABLED=false
STRIPE_BILLING_PORTAL_RETURN_URL=https://coconique-staging.example.com/app/settings
COCONIQUE_FIRST_MONTH_AMOUNT_JPY=100
COCONIQUE_MONTHLY_AMOUNT_JPY=430
COCONIQUE_MONTHLY_HOST_TICKETS=5
COCONIQUE_ADDITIONAL_HOST_TICKET_AMOUNT_JPY=1000
COCONIQUE_ADDITIONAL_HOST_TICKET_MONTHLY_LIMIT=5
```

## Didit / Staging

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
COCONIQUE_IDENTITY_PUBLIC_RETURN_URL=https://coconique-staging.example.com/identity/return
DIDIT_SSL_ALLOW_CRL_FAILURE=false
```

## 再登録防止シグナル

```env
COCONIQUE_REENTRY_SIGNAL_SECRET=long-random-secret-fixed-after-launch
COCONIQUE_CAPTURE_STRIPE_CARD_FINGERPRINT=true
```

## SMS

SMSは初期必須から撤去済み。Twilio関連は将来用に残すが、ステージング初期では使わない。

```env
COCONIQUE_SMS_PROVIDER=fake
```

## メール

```env
RESEND_API_KEY=...
MAIL_FROM=no-reply@coconique.example.com
SUPPORT_EMAIL=support@coconique.example.com
```

## リクエスト時の自動同期間引き

```env
COCONIQUE_REQUEST_SYNC_INTERVAL_SECONDS=60
```
