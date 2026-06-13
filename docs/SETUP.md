# KM Auth Starter API Setup

## 目的

このリポジトリは、Hodokoo / Coconique などへ複製して使うための Rails API 認証・決済スターターです。

共通化するのはコード・設計・テンプレートまでです。  
本番サービスでは DB / Cookie / Secret / Stripe / Mail / Storage / Admin を必ず分離します。

## Backend

```bash
bundle install
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

## 環境変数
cp .env.example .env

または、開発中はターミナルで直接 export します。

export STRIPE_SECRET_KEY="sk_test_xxx"
export STRIPE_WEBHOOK_SECRET="whsec_xxx"
export STRIPE_SUCCESS_URL="http://localhost:5173/billing/success?session_id={CHECKOUT_SESSION_ID}"
export STRIPE_CANCEL_URL="http://localhost:5173/billing/cancel"
export CURRENT_APP_KEY="sample_app"

## Rails起動

bin/rails s

## Stripe CLI

stripe listen --forward-to localhost:3000/webhooks/stripe

表示された whsec_... を STRIPE_WEBHOOK_SECRET として Rails server に渡してください。

## Frontend

```bash
npm install
npm run dev
```

## Test Card

Stripeテスト決済では以下を使用します。

```
カード番号: 4242 4242 4242 4242
有効期限: 12/34 など将来日付
CVC: 123
```

## Main Flow

/signup
→ email verification
→ /onboarding/profile
→ /onboarding/confirm
→ /signup/complete
→ /app/dashboard
→ /app/deposit
→ Stripe Checkout
→ /billing/success
→ webhook
→ credit balance update


---

# 5. `docs/fork-checklist.md`

```md
# Fork Checklist

Hodokoo / Coconique へ派生する時に必ず確認・変更する項目です。

## 必ず分離するもの

- DB
- 認証DB
- session cookie名
- CSRF cookie名
- secret_key_base
- Rails credentials
- JWT署名鍵を使う場合はJWT署名鍵
- ActiveStorage bucket
- 暗号化キー
- Stripe account
- Stripe API key
- Stripe webhook secret
- Stripe customer
- Mail送信ドメイン
- 管理画面
- 管理者アカウント
- ログ保存先

## Rails側で変更する値

- `CURRENT_APP_KEY`
- `CURRENT_TERMS_VERSION`
- `CURRENT_PRIVACY_VERSION`
- `AUTH_COOKIE_NAME`
- `CSRF_COOKIE_NAME`
- `FRONTEND_ORIGIN`
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_SUCCESS_URL`
- `STRIPE_CANCEL_URL`
- `MAIL_FROM`

## Frontend側で変更する値

- `VITE_API_BASE_URL`
- `VITE_APP_KEY`
- `VITE_CSRF_COOKIE_NAME`
- `VITE_IDLE_LOGOUT_MINUTES`
- brand theme
- 利用規約文面
- プライバシーポリシー文面

## Hodokooで追加するもの

- 契約書アップロード履歴
- 営業トーク音声/文字起こし履歴
- AIチェック履歴
- redaction settings
- provider usage logs
- 非弁法配慮の文言
- 利用範囲・免責表示

## Coconiqueで追加するもの

- 本人確認
- 緊急連絡先
- 参加予定
- 集合場所
- 通報履歴
- ブロック機能
- 評価/レビュー
- 安全対策ログ

## 注意

Coconique固有の本人確認・緊急連絡先・集合場所・通報履歴は、共通スターターには入れないこと。  
Hodokoo固有の契約書・営業トーク・AIチェック履歴も、共通スターターには入れないこと。




