# Coconique Step 7-6 ステージング環境変数表

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
SECRET_KEY_BASE=...
DATABASE_URL=postgres://...

FRONTEND_ORIGIN=https://coconique-staging.example.com
CORS_ALLOWED_ORIGINS=https://coconique-staging.example.com
CHECKOUT_ALLOWED_HOSTS=coconique-staging.example.com
SESSION_COOKIE_NAME=coconique_session
CSRF_COOKIE_NAME=coconique_csrf
AUTH_COOKIE_SECURE=true
```

## メール

```env
MAIL_PROVIDER=resend
RESEND_API_KEY=re_...
RESEND_WEBHOOK_SECRET=...
MAIL_FROM=no-reply@staging-coconique.example.com
SUPPORT_EMAIL=support@coconique.example.com
FRONTEND_EMAIL_VERIFICATION_URL=https://coconique-staging.example.com/verify-email
FRONTEND_PASSWORD_RESET_URL=https://coconique-staging.example.com/reset-password
```

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
STRIPE_BILLING_PORTAL_RETURN_URL=https://coconique-staging.example.com/app/settings

COCONIQUE_FIRST_MONTH_AMOUNT_JPY=100
COCONIQUE_MONTHLY_AMOUNT_JPY=430
COCONIQUE_MONTHLY_HOST_TICKETS=5
COCONIQUE_ADDITIONAL_HOST_TICKET_AMOUNT_JPY=1000
COCONIQUE_ADDITIONAL_HOST_TICKET_MONTHLY_LIMIT=5
COCONIQUE_CAPTURE_STRIPE_CARD_FINGERPRINT=true
```

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
COCONIQUE_IDENTITY_PUBLIC_RETURN_URL=https://coconique-staging.example.com/identity/return
```

## SMS

SMSは初期必須から撤去済み。Twilio Verifyは将来用にコードだけ残す。

```env
COCONIQUE_SMS_PROVIDER=fake
```

## 再登録防止シグナル

```env
COCONIQUE_REENTRY_SIGNAL_SECRET=<32文字以上の固定ランダム文字列>
COCONIQUE_CAPTURE_STRIPE_CARD_FINGERPRINT=true
```

注意: `COCONIQUE_REENTRY_SIGNAL_SECRET` は運用開始後に変えると過去digestと照合できなくなるため、staging/prodで別々に固定する。

## リクエスト時の同期間引き

```env
COCONIQUE_REQUEST_SYNC_INTERVAL_SECONDS=60
```

## 実行確認

```bash
bin/rails coconique:staging:doctor
bin/rails coconique:stripe:verify_remote
bin/rails coconique:identity:doctor
```
