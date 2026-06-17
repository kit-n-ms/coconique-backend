# Coconique Step 7-2 Stripe Subscription 実装メモ

## 方針

- Founder βプランは Stripe Checkout `mode=subscription`。
- 月額Priceは 430円/月。
- 初月100円は 330円OFF / duration once のCouponで実現。
- Stripe Taxは初期βではOFF。Checkout Session作成時も `automatic_tax: { enabled: false }` を明示。
- 追加主催チケットは従来どおり `mode=payment` の都度決済。
- 月額チケット5枚の付与は `invoice.paid` webhookを正とする。
- `checkout.session.completed` ではSubscription ID等を保存するが、チケット付与はしない。

## Stripe Dashboardで必要なもの

1. Product: `Coconique Founder Plan`
   - Recurring Price: 430 JPY / month
   - env: `STRIPE_PRICE_FOUNDER_MONTHLY=price_xxx`
2. Coupon: 初回のみ330円OFF
   - Amount off: 330 JPY
   - Duration: once
   - env: `STRIPE_COUPON_FIRST_MONTH_100=coupon_xxx`
3. Product: `Coconique Host Ticket`
   - One-time Price: 1000 JPY
   - env: `STRIPE_PRICE_HOST_TICKET=price_xxx`

## Stripe webhookで有効化するイベント

- `checkout.session.completed`
- `checkout.session.expired`
- `invoice.paid`
- `invoice.payment_failed`
- `invoice.payment_action_required`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `identity.verification_session.verified`
- `identity.verification_session.requires_input`
- `identity.verification_session.canceled`

## 重要な動作

### 初回Checkout完了

`checkout.session.completed`:

- `payment_checkout_sessions` を completed にする。
- `users.coconique_stripe_subscription_id` を保存。
- `card_registered_at` を保存。
- `coconique_subscription_status` は一旦 `incomplete`。
- チケット付与はまだ行わない。

### 初回/毎月の請求成功

`invoice.paid`:

- ユーザーを `active` にする。
- `current_period_started_at` / `current_period_ends_at` をStripe invoiceのperiodに合わせる。
- 前期間の未使用月額チケットを失効。
- 新期間の月額主催チケット5枚を付与。
- `stripe_invoice_id` をlot/transaction metadataに保存し、同一invoiceの二重処理を防ぐ。

### 支払い失敗

`invoice.payment_failed` / `invoice.payment_action_required`:

- `coconique_subscription_status` を `past_due` にする。
- `safety_registered_at` を外す。
- ログインは維持し、参加申請/募集公開側の安全登録条件で止める。

### サブスク終了

`customer.subscription.deleted`:

- `coconique_subscription_status` を `canceled` にする。
- `safety_registered_at` を外す。
- 内部のSubscription停止履歴を残す。

## ローカル確認

```bash
bin/rails db:migrate
bin/rails test test/integration/stripe_webhook_test.rb
```

Stripe CLIを使う場合:

```bash
stripe listen --forward-to localhost:3000/webhooks/stripe
```

Checkoutはフロント既存の `billingStore.startCheckout('founder_beta_monthly')` をそのまま使う。API側で `mode=subscription` に切り替えるため、フロント変更は不要。
