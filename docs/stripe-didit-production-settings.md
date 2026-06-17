# Stripe / Didit 本番設定表

更新日: 2026-06-17

## Stripe 本番設定

### Product / Price

| 用途 | Stripe設定 | 値 |
|---|---|---|
| Founder β月額 | recurring Price | 430 JPY / month |
| 初月割引 | Coupon | 330 JPY off / duration once |
| 初回請求 | 430円 - 330円 | 100 JPY |
| 追加主催チケット | one-time Price | 1000 JPY |

### Checkout

- Founder β: `mode=subscription`
- 追加チケット: `mode=payment`
- Stripe Tax: OFF
- 表示価格はCoconique上の総額として扱う

### Webhook endpoint

```text
https://api.coconique.example.com/webhooks/stripe
```

購読イベント:

```text
checkout.session.completed
checkout.session.expired
invoice.paid
invoice.payment_failed
invoice.payment_action_required
customer.subscription.updated
customer.subscription.deleted
charge.refunded
refund.updated
```

### Billing Portal

Stripe DashboardでBilling Portalを有効化し、カード更新・請求履歴確認を許可する。

Return URL:

```text
https://coconique.example.com/app/settings
```

## Didit 本番設定

### Workflow

初期ON:

- 運転免許証
- パスポート
- 在留カード
- 顔照合 + ライブ判定
- 18歳以上確認
- 日本国内利用想定

初期OFF:

- マイナンバーカード
- 日本国外の一般ID文書
- 書類裏面を必須にする設定

### Return URL

```text
https://coconique.example.com/identity/return
```

スマホQRで本人確認した場合は、この公開完了ページに戻す。PC側はwebhookまたはsyncで安全登録状態を更新する。

### Webhook endpoint

```text
https://api.coconique.example.com/webhooks/didit
```

### Coconique側に保存しないもの

- 本人確認書類画像
- 顔写真
- 免許証番号
- OCR全文
- 住所全文
- 書類裏面データ
- Didit詳細レポート全文

### Coconique側に保存するもの

- provider
- session_id
- status
- workflow_type
- document_type
- verified_at
- age_over_18
- Didit由来一意識別子がある場合のHMAC digest
- Stripe card fingerprintがある場合のHMAC digest

## 本番切り替え時の確認順

1. StagingでStripe Test modeの決済・webhook・Portalを確認
2. StagingでDidit Workflow / webhook / return URLを確認
3. Live modeのStripe Product / Price / Couponを作成
4. Live webhook secretを本番環境変数に設定
5. Didit本番Workflow ID/API key/webhook secretを設定
6. 本番で管理者アカウントだけを使い、初回100円決済を1回テスト
7. 本番で本人確認を1回テスト
8. 通報/退会/BAN/再登録防止シグナルを管理画面で確認
9. βユーザー招待開始
