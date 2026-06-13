# Manual Check

## Health

```bash
curl -i http://localhost:3000/api/v1/health
```

## CSRF

```
rm -f tmp/cookies.txt

curl -i \
  -c tmp/cookies.txt \
  -b tmp/cookies.txt \
  http://localhost:3000/api/v1/auth/csrf
```

## Login

```
CSRF_TOKEN=$(awk '$6 == "km_auth_starter_csrf" { print $7 }' tmp/cookies.txt)

curl -i \
  -c tmp/cookies.txt \
  -b tmp/cookies.txt \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -X POST http://localhost:3000/api/v1/auth/login \
  -d '{
    "email": "your@example.com",
    "password": "password123456"
  }'
```

## Me

```
curl -i \
  -b tmp/cookies.txt \
  http://localhost:3000/api/v1/auth/me
```

## Billing Products

```
curl -i \
  -b tmp/cookies.txt \
  "http://localhost:3000/api/v1/billing/credit_products?app_key=sample_app"
```

## Billing Balance

```
curl -i \
  -b tmp/cookies.txt \
  "http://localhost:3000/api/v1/billing/balance?app_key=sample_app"
```

## Stripe Webhook Route

`curl -i -X POST http://localhost:3000/webhooks/stripe -d '{}'`

Expected:

`400 invalid_signature`

404なら route 設定が間違っている。

---

## 最後に実行する確認

Rails側：

```bash
bin/rails zeitwerk:check
bin/rails routes -g billing
bin/rails routes -g webhooks
bin/rails db:seed
```

Vue側：

`npm run build`

Stripe確認：

`stripe listen --forward-to localhost:3000/webhooks/stripe`
