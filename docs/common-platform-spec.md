# KM Auth Starter 共通基盤仕様書

## 概要

KM Auth Starter は、Hodokoo / Coconique など複数プロダクトへ派生させるための共通認証・課金・メール基盤である。

目的は、各プロダクトごとに毎回ゼロから作り直しになりやすい以下の機能を、共通化して安全に複製できる状態にすること。

- ユーザー登録
- メールアドレス確認
- ログイン / ログアウト
- パスワード再設定
- プロフィール登録
- 利用規約 / プライバシーポリシー同意
- オンボーディング
- Stripe Checkout
- クレジット残高 / 履歴
- Stripe Webhook
- Resend実メール送信
- Resend Webhook
- メール抑止管理
- Solid Queue
- Health / Readiness
- 管理者向け最小API
- テスト自動化

## 技術構成

### Backend

- Ruby on Rails API
- PostgreSQL
- Cookie session
- CSRF protection
- Solid Queue
- Stripe
- Resend
- Svix webhook signature verification

### Frontend

- Vite
- Vue 3
- `<script setup lang="ts">`
- TypeScript
- Tailwind CSS
- Pinia
- Vue Router
- Vitest

## 主要フロー

### 新規登録

1. ユーザーがメールアドレス・パスワードを入力
2. Rails APIでユーザー作成
3. EmailVerification作成
4. `AuthMailer.email_verification(...).deliver_later`
5. Solid Queueがメール送信ジョブを処理
6. Resend経由で確認メール送信
7. ユーザーが確認URLを開く
8. メール認証完了
9. プロフィール入力
10. 入力内容確認
11. 利用規約 / プライバシーポリシー同意
12. 利用開始

### Stripe決済

1. ユーザーがデポジット商品を選択
2. Rails APIがCheckout Session作成
3. ユーザーがStripe Checkoutで決済
4. Stripe WebhookをRailsが受信
5. Checkout Session完了を冪等処理
6. CreditBalance / CreditTransaction更新

### メールWebhook

1. Resendが `email.sent` / `email.delivered` などを送信
2. Rails `/webhooks/resend` が受信
3. Svix署名検証
4. EmailWebhookEventに保存
5. bounced / complained / failed / suppressed は EmailSuppression へ反映

## 管理API

管理APIは通常ユーザー画面とは分離する前提の、最小運用APIである。

- ユーザー一覧 / 詳細
- AuditLog確認
- Billing履歴確認
- Stripe Webhook履歴確認
- Resend Webhook履歴確認
- EmailSuppression確認 / 解除

管理画面UIは共通基盤には含めない。Hodokoo / Coconique 側で別フロントとして作成する。

## 共通基盤に含めないもの

以下は派生先で実装する。

### Hodokoo側

- 契約書アップロード
- OCR / PDF / 音声文字起こし
- AI契約チェック
- 非弁法配慮UI
- クレジット消費ルールの本実装
- 契約書チェック履歴

### Coconique側

- イベント同行者募集
- 募集作成 / 応募 / マッチング
- 本人確認
- 通報 / ブロック / モデレーション
- 安全対策
- 年齢確認や利用条件

## 本番運用で必須の確認

- `/up` が200
- `/healthz` が200
- `/readiness` が200
- `bin/rails km:doctor` が成功
- `bin/rails test` が成功
- `npm run test` が成功
- `npm run build` が成功
- Stripe Webhookが200
- Resend Webhookが200
- `MAIL_PROVIDER=resend` かつ `delivery_method=resend_custom`

## 重要な注意

API handoff zipには必ず以下を含める。

- `app/lib`
- `config/application.rb`
- `config/environments`
- `config/queue.yml`
- `bin/jobs`
- `db/queue_schema.rb`

特に `app/lib/resend_delivery_method.rb` がないとResend送信が再現できない。
