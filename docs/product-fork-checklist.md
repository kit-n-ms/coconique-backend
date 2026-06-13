# Product Fork Checklist

KM Auth StarterをHodokoo / Coconique などへ派生させるときに、必ず変更・確認する項目。

## 必ず変更するENV

### Product identity

```env
APP_NAME=
APP_KEY=
PRODUCT_KEY=
CURRENT_TERMS_VERSION=
CURRENT_PRIVACY_VERSION=
```

### Frontend

```env
FRONTEND_ORIGIN=
FRONTEND_EMAIL_VERIFICATION_URL=
FRONTEND_PASSWORD_RESET_URL=
```

### Cookie

```env
AUTH_COOKIE_NAME=
CSRF_COOKIE_NAME=
COOKIE_SECURE=
COOKIE_SAME_SITE=
```

Cookie名はプロダクトごとに分ける。HodokooとCoconiqueを同じブラウザで使う場合、Cookie名が同じだと衝突する可能性がある。

### Mail / Resend

```env
MAIL_PROVIDER=resend
MAIL_FROM=
RESEND_API_KEY=
RESEND_WEBHOOK_SECRET=
```

Hodokoo / Coconique では送信ドメイン・API Key・Webhook Secretを分ける。

### Stripe

```env
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
STRIPE_SUCCESS_URL=
STRIPE_CANCEL_URL=
```

Stripe商品・価格・webhook endpointはプロダクトごとに分ける。

## 必ず変更するDB seed

- `app_key`
- `CreditProduct` の `code`
- 商品名
- 価格
- 付与credits
- 管理者初期ユーザー

## 必ず変更する表示名

- サービス名
- メールFrom表示名
- メール本文
- 利用規約
- プライバシーポリシー
- OGP / title / description
- ブランドカラー

## Hodokoo派生時

### 追加するもの

- 契約書チェック機能
- OCR / PDF / 音声文字起こし
- AI provider selection
- クレジット消費ルール
- 非弁法配慮文言
- 契約書・営業トーク確認履歴
- ユーザーがAI送信前に伏せ字化できるUI

### 注意点

- AI出力は法的判断ではなく確認観点の整理にする
- 弁護士相談導線は慎重に設計する
- 利用規約・免責・特商法・プライバシーポリシーの専門家確認を推奨

## Coconique派生時

### 追加するもの

- 募集作成
- イベント/同行者募集一覧
- 応募 / 承認 / マッチング
- メッセージ機能
- 通報 / ブロック
- 本人確認
- モデレーション
- 安全対策

### 注意点

- 本人確認は共通基盤には入れずCoconique側で慎重に追加する
- 個人間トラブル対応フローを設計する
- 迷惑行為・ドタキャン・ハラスメント対策を先に考える

## fork後に消してよいもの

- `sample_app` seed
- テスト用CreditProduct
- テスト用ユーザー
- 開発中の古いWebhookイベント
- 開発中のtmp/mails

## fork後に残すもの

- 認証基盤
- CSRF / Cookie設定
- Solid Queue
- Stripe webhook冪等処理
- Resend custom delivery method
- Resend webhook署名検証
- EmailSuppression
- Admin API
- Health / readiness
- km:doctor
