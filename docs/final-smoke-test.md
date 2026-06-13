# Final Smoke Test

共通基盤完了前、またはHodokoo / Coconiqueへ派生する前に実行する最終確認。

## API basic

```bash
bin/rails test
bin/rails km:doctor
curl -i http://localhost:3000/up
curl -i http://localhost:3000/healthz
curl -i http://localhost:3000/readiness
```

期待:

- `/up`: 200
- `/healthz`: 200
- `/readiness`: 200
- `km:doctor`: all green

## Mail runtime

```bash
bin/rails runner 'puts "MAIL_PROVIDER=#{ENV["MAIL_PROVIDER"]}"; puts "delivery_method=#{ActionMailer::Base.delivery_method}"'
```

期待:

```txt
MAIL_PROVIDER=resend
delivery_method=resend_custom
```

## Resend direct send

```bash
bin/rails runner 'user = User.find_by!(email: "YOUR_TEST_EMAIL"); AuthMailer.email_verification(user, "smoke-direct").deliver_now; puts "sent now"'
```

期待:

- `sent now`
- Resend Logs 200
- 実メール到達

## Resend deliver_later + Solid Queue

別ターミナルでworkerを起動:

```bash
bin/jobs start
```

送信:

```bash
bin/rails runner 'user = User.find_by!(email: "YOUR_TEST_EMAIL"); AuthMailer.email_verification(user, "smoke-later").deliver_later; puts "enqueued"'
```

期待:

- `enqueued`
- Resend Logs 200
- 実メール到達
- `SolidQueue::FailedExecution.count == 0`

## Resend Webhook

```bash
bin/rails runner 'p EmailWebhookEvent.recent.limit(10).pluck(:event_id, :event_type, :email, :message_id, :processed_at, :processing_error)'
```

期待:

- `email.sent`
- `email.delivered`
- `processing_error == nil`

## Stripe

Stripe CLI:

```bash
stripe listen --forward-to localhost:3000/webhooks/stripe
```

Checkout Session作成後、テストカードで決済。

期待:

- Stripe CLI returns 200
- `checkout.session.completed` processed
- CreditBalance increases
- CreditTransaction created

## Admin API

adminユーザーでログイン済みcookieを使って確認。

```bash
curl -i -b tmp/cookies.txt http://localhost:3000/api/v1/admin/users
curl -i -b tmp/cookies.txt http://localhost:3000/api/v1/admin/email_webhook_events
curl -i -b tmp/cookies.txt http://localhost:3000/api/v1/admin/billing/credit_transactions
```

期待:

- admin: 200
- general: 403
- guest: 401

## Frontend

```bash
npm run test
npm run build
```

期待:

- tests pass
- production build succeeds

## Cleanup after smoke test

開発環境のみ。

```bash
bin/rails dev:clear_solid_queue_failures
bin/rails dev:clear_email_webhook_events
bin/rails dev:clear_tmp_mails
```
