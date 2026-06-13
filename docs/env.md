# Environment Variables

## App identity

| Key | Example | Notes |
|---|---|---|
| `APP_NAME` | `km_auth_starter_api` | `/up` 等に表示する内部名 |
| `CURRENT_APP_KEY` | `sample_app` | `hodokoo`, `coconique` などに派生時変更 |
| `CURRENT_TERMS_VERSION` | `2026-05-01` | 利用規約バージョン |
| `CURRENT_PRIVACY_VERSION` | `2026-05-01` | プライバシーポリシーバージョン |

## Frontend / CORS

| Key | Example | Notes |
|---|---|---|
| `FRONTEND_ORIGIN` | `http://localhost:5173` | フロントURL |
| `CORS_ALLOWED_ORIGINS` | `http://localhost:5173,http://127.0.0.1:5173` | 複数指定はカンマ区切り |
| `FRONTEND_EMAIL_VERIFICATION_URL` | `http://localhost:5173/auth/email-verifications/confirm` | メール認証URL |
| `FRONTEND_PASSWORD_RESET_URL` | `http://localhost:5173/auth/password-resets/confirm` | パスワード再設定URL |
| `REQUIRE_ORIGIN_FOR_UNSAFE_REQUESTS` | `true` | 本番では `true` 推奨 |
| `NGROK_HOST` | `xxxx.ngrok-free.dev` | ローカルWebhook確認用 |

## Cookie / Session

| Key | Example | Notes |
|---|---|---|
| `AUTH_COOKIE_NAME` | `km_auth_starter_session` | 派生時に必ず変更 |
| `CSRF_COOKIE_NAME` | `km_auth_starter_csrf` | 派生時に必ず変更 |
| `AUTH_COOKIE_SECURE` | `true` | 本番では `true` |
| `AUTH_COOKIE_SAME_SITE` | `lax` | クロスサイト構成なら要検討 |
| `AUTH_COOKIE_DOMAIN` | `.example.com` | 必要な場合のみ |

## Mail

| Key | Example | Notes |
|---|---|---|
| `MAIL_PROVIDER` | `file` / `resend` | ローカルは `file`, 本番は `resend` 推奨 |
| `MAIL_FROM` | `Coconique <no-reply@coconique.com>` | ResendでVerify済みドメインを使う |
| `RESEND_API_KEY` | `re_xxx` | 派生サービスごとに分離 |
| `RESEND_WEBHOOK_SECRET` | `whsec_xxx` | Resend webhook署名検証用 |
| `POSTMARK_API_TOKEN` | `xxx` | Postmark利用時のみ |

期待されるResend設定:

```bash
bin/rails runner 'puts "MAIL_PROVIDER=#{ENV["MAIL_PROVIDER"]}"; puts "delivery_method=#{ActionMailer::Base.delivery_method}"'
```

```txt
MAIL_PROVIDER=resend
delivery_method=resend_custom
```

## Stripe

| Key | Example | Notes |
|---|---|---|
| `STRIPE_SECRET_KEY` | `sk_test_xxx` | 派生サービスごとに分離 |
| `STRIPE_WEBHOOK_SECRET` | `whsec_xxx` | Stripe webhook署名検証用 |
| `STRIPE_SUCCESS_URL` | `http://localhost:5173/billing/success?session_id={CHECKOUT_SESSION_ID}` | `{CHECKOUT_SESSION_ID}` を残す |
| `STRIPE_CANCEL_URL` | `http://localhost:5173/billing/cancel` | キャンセル時URL |
| `REQUIRE_STRIPE_CONFIG` | `true` | stagingで厳密チェックしたい時 |

## Solid Queue

| Key | Example | Notes |
|---|---|---|
| `JOB_CONCURRENCY` | `1` | worker process数 |

開発時は別ターミナルで起動する。

```bash
bin/jobs start
```
