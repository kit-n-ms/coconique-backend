# Stripe Local Test

## 1. Stripe CLI Login


```bash
stripe login
```

## 2. Webhook転送

```bash
stripe listen --forward-to localhost:3000/webhooks/stripe
```

## 3. Rails 起動

```
export STRIPE_SECRET_KEY="sk_test_xxx"
export STRIPE_WEBHOOK_SECRET="whsec_xxx"
export STRIPE_SUCCESS_URL="http://localhost:5173/billing/success?session_id={CHECKOUT_SESSION_ID}"
export STRIPE_CANCEL_URL="http://localhost:5173/billing/cancel"
export CURRENT_APP_KEY="sample_app"

bin/rails s
```

## 4. Route確認

```
bin/rails routes -g webhooks

期待値:POST /webhooks/stripe webhooks/stripe#create
```

## 5. 署名なしcurl確認

```
curl -i -X POST http://localhost:3000/webhooks/stripe -d '{}'

期待値:

400 Bad Request
invalid_signature

404なら route が間違っている。
```

## 6. Checkout作成

```
curl -i \
  -c tmp/cookies.txt \
  -b tmp/cookies.txt \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: $CSRF_TOKEN" \
  -X POST http://localhost:3000/api/v1/billing/checkout_sessions \
  -d '{
    "app_key": "sample_app",
    "product_code": "deposit_1000"
  }'
```

## 7. Test Card

```
4242 4242 4242 4242
12/34
123
```

## 8. Stripe CLIで確認

```
成功時:

checkout.session.completed
<-- [200] POST http://localhost:3000/webhooks/stripe
```

## 9. DB確認

```bash
bin/rails runner 'p StripeWebhookEvent.order(created_at: :desc).limit(5).pluck(:stripe_event_id, :event_type, :processed_at, :processing_error)'
```

```bash
bin/rails runner 'p CreditTransaction.order(created_at: :desc).limit(5).pluck(:user_id, :app_key, :transaction_type, :amount, :balance_after, :description)'
```

## 10. 残高確認

```bash
curl -i \
  -b tmp/cookies.txt \
  "http://localhost:3000/api/v1/billing/balance?app_key=sample_app"

期待値:

{
  "ok": true,
  "data": {
    "credit_balance": {
      "app_key": "sample_app",
      "balance": 1000
    }
  }
}
```


---

# 8. `docs/error-codes.md`

```md
# Error Codes

## Auth

| Code | Meaning | User Message |
|---|---|---|
| AUTH_REQUIRED | ログインが必要 | ログインしてください。 |
| INVALID_CREDENTIALS | メールアドレスまたはパスワード不一致 | メールアドレスまたはパスワードを確認してください。 |
| INVALID_CSRF_TOKEN | CSRF検証失敗 | ページを再読み込みして再度お試しください。 |
| SESSION_EXPIRED | セッション期限切れ | 再度ログインしてください。 |

## Email Verification

| Code | Meaning | User Message |
|---|---|---|
| EMAIL_VERIFICATION_INVALID | token不正 | 確認リンクが無効です。 |
| EMAIL_VERIFICATION_EXPIRED | token期限切れ | 確認リンクの期限が切れています。 |
| EMAIL_ALREADY_VERIFIED | 既に認証済み | 既にメール認証は完了しています。 |

## Password Reset

| Code | Meaning | User Message |
|---|---|---|
| PASSWORD_RESET_INVALID | token不正 | パスワード再設定リンクが無効です。 |
| PASSWORD_RESET_EXPIRED | token期限切れ | パスワード再設定リンクの期限が切れています。 |

## Onboarding

| Code | Meaning | User Message |
|---|---|---|
| ONBOARDING_INCOMPLETE | 利用開始未完了 | 利用開始手続きを完了してください。 |
| TERMS_NOT_ACCEPTED | 規約未同意 | 利用規約とプライバシーポリシーに同意してください。 |

## Billing

| Code | Meaning | User Message |
|---|---|---|
| BILLING_PRODUCT_NOT_FOUND | 商品なし | 購入可能な商品が見つかりません。 |
| BILLING_CHECKOUT_FAILED | Checkout作成失敗 | 決済ページを開始できませんでした。 |
| BILLING_WEBHOOK_INVALID_SIGNATURE | Webhook署名不正 | Webhook署名検証に失敗しました。 |
| BILLING_WEBHOOK_PROCESSING_FAILED | Webhook処理失敗 | Webhook処理に失敗しました。 |

