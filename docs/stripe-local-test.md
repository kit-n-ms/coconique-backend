# Coconique Stripe Subscription Local / Test Mode Verification

更新日: 2026-06-15  
対象: Step 7-2 実装後の Stripe Checkout Subscription / webhook / 主催チケット付与検証

## 0. 方針

Coconique の初期βは Stripe を第一候補として進める。

- 月額: Stripe Checkout `mode=subscription`
- 価格: 430円/月
- 初月: 330円OFF coupon を1回だけ適用し、初回請求を100円にする
- Stripe Tax: 初期βではOFF
- 主催チケット: `invoice.paid` を正として毎月5枚付与
- 追加主催チケット: Stripe Checkout `mode=payment` で1枚1,000円
- fincode byGMO は将来候補として保留。初期リリースでは実装対象外

## 1. Stripe Dashboardで作成するもの

Test modeで先に作成し、検証後にLive modeで同じ構成を作る。

| 種別 | 内容 | 環境変数 |
|---|---|---|
| Product | Coconique Founder Plan | - |
| Recurring Price | 430 JPY / month | `STRIPE_PRICE_FOUNDER_MONTHLY` |
| Coupon | 330 JPY off / duration once | `STRIPE_COUPON_FIRST_MONTH_100` |
| Product | Coconique Host Ticket | - |
| One-time Price | 1000 JPY | `STRIPE_PRICE_HOST_TICKET` |

## 2. Rails env

`.env` または Render 等の環境変数に設定する。

```bash
CURRENT_APP_KEY=coconique
COCONIQUE_BILLING_PROVIDER=stripe

STRIPE_SECRET_KEY=sk_test_xxx
STRIPE_PUBLISHABLE_KEY=pk_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx

STRIPE_PRICE_FOUNDER_MONTHLY=price_xxx
STRIPE_COUPON_FIRST_MONTH_100=coupon_xxx
STRIPE_PRICE_HOST_TICKET=price_xxx
STRIPE_TAX_ENABLED=false

STRIPE_SUCCESS_URL=http://localhost:5173/billing/success?session_id={CHECKOUT_SESSION_ID}
STRIPE_CANCEL_URL=http://localhost:5173/billing/cancel
```

## 3. Web env

```bash
VITE_API_BASE_URL=http://localhost:3000
VITE_APP_KEY=coconique
VITE_CSRF_COOKIE_NAME=coconique_csrf
```

## 4. Doctor

```bash
bin/rails coconique:stripe:doctor
```

期待値:

- 必須環境変数が `OK`
- `COCONIQUE_BILLING_PROVIDER=stripe`
- `STRIPE_TAX_ENABLED=false`
- Checkout成功/キャンセルURLがCoconiqueのフロントURLになっている

## 5. Stripe CLI Webhook転送

```bash
stripe login
stripe listen --forward-to localhost:3000/webhooks/stripe
```

表示された `whsec_...` を `STRIPE_WEBHOOK_SECRET` に設定して Rails を再起動する。

## 6. 起動

```bash
bin/rails db:migrate
bin/rails test test/integration/stripe_webhook_test.rb
bin/rails s
```

別ターミナルでWebを起動する。

```bash
npm run dev
```

## 7. 月額Subscription Checkout検証

1. Coconiqueに新規登録する
2. メール認証・プロフィール・部則同意まで進む
3. 支払い登録画面でFounder βプランを開始する
4. Stripe Checkoutへ遷移する
5. テストカードで支払う
6. `/billing/success` に戻る
7. Webhookログで `checkout.session.completed` と `invoice.paid` が200で処理されることを確認する

テストカード例:

```text
4242 4242 4242 4242
12/34
123
```

## 8. DB確認

```bash
bin/rails runner 'u = User.order(created_at: :desc).first; p({ email: u.email, billing: u.coconique_billing&.slice(:billing_provider, :subscription_status, :stripe_customer_id, :stripe_subscription_id, :card_registered_at) })'
```

```bash
bin/rails runner 'u = User.order(created_at: :desc).first; p u.coconique_host_ticket_lots.order(created_at: :desc).limit(5).pluck(:source_type, :status, :initial_count, :remaining_count, :expires_at, :stripe_invoice_id)'
```

期待値:

- `subscription_status` が `active`
- `card_registered_at` が入っている
- 月額主催チケット5枚のlotが付与されている
- `stripe_invoice_id` が入っている

## 9. 追加主催チケット検証

1. 月額チケットを使い切った状態、または購入ボタンのdisabled条件を一時的に満たした状態にする
2. 追加チケット購入画面から1,000円Checkoutへ進む
3. テストカードで支払う
4. Webhook処理後、追加チケット1枚が付与される

期待値:

- 追加チケットlotの `source_type` が購入系になる
- 有効期限が購入日から180日後になる
- 月内購入上限5枚を超えない

## 10. 支払い失敗検証

Stripe CLIまたはStripe Dashboardのテストイベントで、以下を確認する。

| event | 期待結果 |
|---|---|
| `invoice.payment_failed` | `subscription_status` が `past_due` になり、参加申請/募集公開が止まる |
| `invoice.payment_action_required` | 追加認証/カード確認が必要な状態として扱われる |
| `customer.subscription.updated` | Stripe側のstatusがCoconique側に反映される |
| `customer.subscription.deleted` | サブスク終了。参加申請/募集公開不可 |

## 11. 二重webhook検証

同じStripe eventが再送されても、主催チケットが二重付与されないことを確認する。

```bash
bin/rails runner 'p StripeWebhookEvent.order(created_at: :desc).limit(10).pluck(:stripe_event_id, :event_type, :processed_at, :processing_error)'
```

期待値:

- 同じ `stripe_event_id` が二重処理されない
- 同じ `stripe_invoice_id` で月額チケットが二重付与されない

## 12. Live mode移行前チェック

- [ ] Test modeで初月100円の請求になっている
- [ ] 2ヶ月目以降430円のSubscriptionになっている
- [ ] Stripe TaxがOFF
- [ ] `invoice.paid` で主催チケット5枚が付与される
- [ ] `checkout.session.completed` だけではチケット付与されない
- [ ] 追加チケット1,000円が都度決済で購入できる
- [ ] 支払い失敗時に参加申請/募集公開が止まる
- [ ] カード変更/解約導線はStripe Billing Portalまたは運営案内で確保する
- [ ] webhook secretがTest/Liveで混ざっていない
- [ ] Live keyをGit管理していない

## 13. 本番初回検証

本番では、最初に自分のアカウントで実カードを使って検証する。

1. Live key設定
2. Live webhook endpoint設定
3. 自分のユーザーで初月100円決済
4. Stripe DashboardでSubscription / Invoice / Customerを確認
5. Coconique DBで `active` / チケット5枚付与を確認
6. 必要なら即解約または返金テストを行う
7. 返金時のCoconique側表示・管理メモを確認


## 14. `No such price` でCheckout作成に失敗する場合

`/api/v1/billing/checkout_sessions` が以下のようなエラーになる場合:

```text
Stripe::InvalidRequestError (No such price: 'price_xxx')
```

原因はほぼ次のいずれか。

- `STRIPE_SECRET_KEY=sk_test_...` なのに、Live modeで作ったPrice IDを入れている
- `STRIPE_SECRET_KEY=sk_live_...` なのに、Test modeで作ったPrice IDを入れている
- 別のStripeアカウントで作ったPrice IDを入れている
- `prod_...` のProduct IDやlookup keyを入れており、`price_...` のPrice IDではない
- 環境変数に余計な空白や改行が入っている

まず環境変数の形式を確認する。

```bash
bin/rails coconique:stripe:doctor
```

次に、現在の `STRIPE_SECRET_KEY` で実際にStripe APIからPrice/Couponを取得できるか確認する。

```bash
bin/rails coconique:stripe:verify_remote
```

期待値:

- Founder monthly price: `amount=430 jpy recurring=month`
- Host ticket price: `amount=1000 jpy recurring=none`
- First month coupon: `amount_off=330 jpy duration=once`

`verify_remote` でNGになるIDは、現在のSecret Keyと同じTest/Liveモード・同じStripeアカウントからコピーし直す。

## Step 7-2e: ローカルWebhook転送と成功画面同期

Stripe CheckoutからCoconiqueへリダイレクトされても、Railsログに `/webhooks/stripe` が出ていない場合は、StripeからローカルAPIへWebhookが届いていません。ローカル検証では別ターミナルでStripe CLIを起動してください。

```bash
stripe login
stripe listen --forward-to http://localhost:3000/webhooks/stripe
```

`stripe listen` の起動直後に表示される `whsec_...` を、Railsの `STRIPE_WEBHOOK_SECRET` に設定してAPIを再起動します。

```env
STRIPE_WEBHOOK_SECRET=whsec_xxx
```

CoconiqueのStripeサブスク検証で最低限見るイベントは次の通りです。

- `checkout.session.completed`
- `checkout.session.expired`
- `invoice.paid`
- `invoice.payment_failed`
- `invoice.payment_action_required`
- `customer.subscription.updated`
- `customer.subscription.deleted`

成功画面 `/billing/success` では、`session_id=cs_...` を使って `POST /api/v1/billing/checkout_sessions/sync` を呼びます。この同期APIは、Webhookの反映待ち中でもStripe APIからCheckout SessionとInvoiceを再確認し、Invoiceが支払い済みなら月額プランの有効化と今期分の主催チケット5枚付与を補助します。

ただし、本番運用ではWebhookが正です。成功画面同期は、リダイレクト直後の表示遅延・ローカル検証・Webhook一時遅延に対する保険です。
