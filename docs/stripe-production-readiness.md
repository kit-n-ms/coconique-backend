# Coconique Stripe Production Readiness Checklist

更新日: 2026-06-15

## 決定事項

- 初期βの決済ProviderはStripeで進める
- fincode byGMOは将来候補として保留し、初期リリースのブロッカーにしない
- Stripe Taxは初期βではOFF
- 430円はCoconique上の表示総額として扱う
- 非課税事業者として開始する前提。ただし消費税・インボイス対応は税理士確認対象

## Live mode設定

| 項目 | 状態 |
|---|---|
| Stripe本番アカウント本人確認 |  |
| 銀行口座登録 |  |
| 明細表記設定 |  |
| 顧客向けメール設定 |  |
| Product: Founder Plan |  |
| Price: 430 JPY monthly |  |
| Coupon: 330 JPY off once |  |
| Product: Host Ticket |  |
| Price: 1000 JPY one-time |  |
| Webhook endpoint |  |
| Webhook events選択 |  |
| Live secret key設定 |  |
| Live publishable key設定 |  |
| Live webhook secret設定 |  |

## Webhook events

最低限、以下を有効化する。

- `checkout.session.completed`
- `invoice.paid`
- `invoice.payment_failed`
- `invoice.payment_action_required`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `charge.refunded`
- `refund.updated`

## Render / hosting env

```bash
CURRENT_APP_KEY=coconique
COCONIQUE_BILLING_PROVIDER=stripe
STRIPE_TAX_ENABLED=false

STRIPE_SECRET_KEY=sk_live_xxx
STRIPE_PUBLISHABLE_KEY=pk_live_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
STRIPE_PRICE_FOUNDER_MONTHLY=price_live_xxx
STRIPE_COUPON_FIRST_MONTH_100=coupon_live_xxx
STRIPE_PRICE_HOST_TICKET=price_live_xxx

STRIPE_SUCCESS_URL=https://<frontend-domain>/billing/success?session_id={CHECKOUT_SESSION_ID}
STRIPE_CANCEL_URL=https://<frontend-domain>/billing/cancel
```

## リリース前に必ず確認すること

- [ ] Test keyとLive keyが混ざっていない
- [ ] Test Price IDとLive Price IDが混ざっていない
- [ ] Test Coupon IDとLive Coupon IDが混ざっていない
- [ ] Webhook secretが環境ごとに正しい
- [ ] Checkout成功URLに `{CHECKOUT_SESSION_ID}` が含まれている
- [ ] Stripe TaxがOFF
- [ ] 初回請求が100円
- [ ] 2ヶ月目以降が430円
- [ ] `invoice.paid` 後に月額チケット5枚付与
- [ ] 支払い失敗で参加申請/募集公開が止まる
- [ ] 解約済みユーザーが参加申請/募集公開できない
- [ ] 退会時にStripe subscriptionが停止する、または運営タスクとして検知できる
- [ ] BAN時にStripe subscriptionが停止する、または運営タスクとして検知できる
- [ ] 返金時のチケット扱い・管理メモ方針が決まっている

## 初期βの運用メモ

- 支払い失敗ユーザーはログイン可、参加申請/募集公開不可にする
- カード変更はStripe Billing Portal導線を優先する
- 問い合わせ対応用にStripe Customer ID / Subscription ID / Invoice IDで検索できるようにする
- Live初回は自分のカードで100円決済し、DBとStripe Dashboardの整合性を確認してからβユーザーに案内する


## 9. Price/Coupon IDの実在確認

Live移行前に、Render等の本番環境と同じ環境変数で以下を実行する。

```bash
bin/rails coconique:stripe:doctor
bin/rails coconique:stripe:verify_remote
```

`No such price` が出る場合は、ほぼ必ず `STRIPE_SECRET_KEY` と `STRIPE_PRICE_FOUNDER_MONTHLY` のモード/アカウント不一致。

- `sk_test_...` にはTest modeの `price_...`
- `sk_live_...` にはLive modeの `price_...`
- `prod_...` ではなく `price_...` を入れる
- CouponもTest/Liveで別IDになる

Coconiqueでは、Checkout作成失敗時に500ではなく422で `STRIPE_CHECKOUT_SESSION_CREATE_FAILED` を返す。
