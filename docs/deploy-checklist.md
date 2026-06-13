# Deploy Checklist

## 1. Secrets / ENV

- [ ] `secret_key_base` が派生サービスごとに違う
- [ ] `AUTH_COOKIE_NAME` が派生サービスごとに違う
- [ ] `CSRF_COOKIE_NAME` が派生サービスごとに違う
- [ ] `AUTH_COOKIE_SECURE=true`
- [ ] `REQUIRE_ORIGIN_FOR_UNSAFE_REQUESTS=true`
- [ ] `CORS_ALLOWED_ORIGINS` が本番フロントURLのみ
- [ ] `FRONTEND_EMAIL_VERIFICATION_URL` が本番URL
- [ ] `FRONTEND_PASSWORD_RESET_URL` が本番URL

## 2. Database / Storage

- [ ] primary DB がサービスごとに分離されている
- [ ] queue DB がサービスごとに分離されている
- [ ] ActiveStorage bucket がサービスごとに分離されている
- [ ] logs / monitoring がサービスごとに分離されている

## 3. Mail

- [ ] `MAIL_PROVIDER=resend`
- [ ] `MAIL_FROM` がVerify済みドメイン
- [ ] `RESEND_API_KEY` がサービス専用
- [ ] `RESEND_WEBHOOK_SECRET` が設定済み
- [ ] Resend webhook endpoint が `/webhooks/resend`
- [ ] `email.sent` / `email.delivered` がDBに保存される

## 4. Stripe

- [ ] `STRIPE_SECRET_KEY` がサービス専用
- [ ] `STRIPE_WEBHOOK_SECRET` がサービス専用
- [ ] `STRIPE_SUCCESS_URL` が本番フロントURL
- [ ] `STRIPE_CANCEL_URL` が本番フロントURL
- [ ] Stripe webhook endpoint が `/webhooks/stripe`
- [ ] テスト決済でcredit balanceが増える

## 5. Solid Queue

- [ ] Web process と Worker process が分かれている
- [ ] Workerで `bin/jobs start` が起動している
- [ ] WorkerにもResend/Stripe等のENVが入っている
- [ ] `bin/rails km:doctor` が通る

## 6. Smoke test

```bash
curl -i https://api.example.com/up
curl -i https://api.example.com/healthz
curl -i https://api.example.com/readiness
```

- [ ] signup
- [ ] email verification
- [ ] login
- [ ] logout
- [ ] password reset
- [ ] Stripe checkout
- [ ] Stripe webhook
- [ ] Resend webhook
