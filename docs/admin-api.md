# Admin API

## 方針

この共通基盤では、Hodokoo / Coconique の通常ユーザー画面と管理画面を分離しやすくするため、まずは管理画面UIではなく **管理者・運用者向けの最小API** だけを提供する。

管理APIは `/api/v1/admin` 配下に置く。

## 権限

- 未ログイン: `401 UNAUTHORIZED`
- ログイン済み一般ユーザー: `403 FORBIDDEN`
- `role=admin` のユーザー: アクセス可

既存の `Api::V1::Admin::BaseController` で `require_login!` と `require_admin!` を実行する。

## ユーザー管理

```txt
GET /api/v1/admin/users
GET /api/v1/admin/users/:id
PATCH /api/v1/admin/users/:id/status
GET /api/v1/admin/users/:user_id/auth_sessions
DELETE /api/v1/admin/auth_sessions/:id
```

### ユーザー一覧 query

```txt
q          メールアドレス部分一致
role       general / admin
status     active / suspended / deleted
page       1始まり
per_page   最大100
```

## AuditLog

```txt
GET /api/v1/admin/audit_logs
```

### query

```txt
user_id
action
target_type
page
per_page
```

## Billing確認

```txt
GET /api/v1/admin/billing/credit_transactions
GET /api/v1/admin/billing/checkout_sessions
GET /api/v1/admin/billing/checkout_sessions/:id
GET /api/v1/admin/billing/credit_balances
```

### credit_transactions query

```txt
user_id
app_key
transaction_type
source_type
page
per_page
```

### checkout_sessions query

```txt
user_id
app_key
status
stripe_checkout_session_id
page
per_page
```

### credit_balances query

```txt
user_id
app_key
page
per_page
```

## Stripe Webhook確認

```txt
GET /api/v1/admin/stripe_webhook_events
GET /api/v1/admin/stripe_webhook_events/:id
```

### query

```txt
event_type
livemode=true/false
processed=true/false
page
per_page
```

`show` ではpayloadも返すため、管理画面に出す場合は表示権限・マスキングを検討する。

## Resend Webhook確認

```txt
GET /api/v1/admin/email_webhook_events
GET /api/v1/admin/email_webhook_events/:id
```

### query

```txt
provider
 event_type
email
message_id
processed=true/false
page
per_page
```

`show` ではpayloadも返すため、管理画面に出す場合は表示権限・マスキングを検討する。

## Email Suppression確認・解除

```txt
GET /api/v1/admin/email_suppressions
DELETE /api/v1/admin/email_suppressions/:id
```

### query

```txt
email
reason
source
page
per_page
```

`DELETE` は抑止解除であり、送信再開を意味する。実行時にはAuditLogへ `admin.email_suppression_deleted` を記録する。

## 第16段階でまだ入れないもの

- 管理画面UI
- ユーザーのメールアドレス変更
- 決済履歴・クレジット履歴の手動改ざん
- 本人確認管理
- Hodokoo / Coconique 固有データ管理

これらは派生先で別途設計する。
