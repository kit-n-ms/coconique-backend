# Coconique インフラ構成 / staging・production 方針

更新日: 2026-06-18  
対象: Step 7-6 安定ベース / staging検証 / 本番リリース準備

---

## 1. 基本構成

```txt
LP / 説明ページ: Cloudflare Pages
本体フロント: Cloudflare Pages
Rails API / worker: Render
DB: Render Postgres
画像ストレージ: Cloudflare R2（将来の本格画像保存時）
DNS / WAF / staging保護: Cloudflare
障害案内ページ: Netlify非常口
```

LPや説明ページは本体アプリから分離する。本体APIやDBに障害が出ても、説明・問い合わせ・障害案内を出せる状態にする。

---

## 2. リポジトリ

```txt
coconique-lp
  → Cloudflare Pages
  → coconique.jp / www.coconique.jp

coconique-web
  → Cloudflare Pages
  → app.coconique.jp / app.stg.coconique.jp

coconique-api
  → Render
  → api.coconique.jp / api.stg.coconique.jp
```

---

## 3. ブランチ運用

```txt
main
  → production

staging
  → staging

feature/*
  → 作業ブランチ
```

基本フロー:

```txt
feature/*
  ↓ PR
staging
  ↓ staging環境へ自動デプロイ
  ↓ 動作確認
main
  ↓ production環境へ自動デプロイ
```

ブランチだけでなく、DB・ストレージ・外部APIキーも完全に分離する。

---

## 4. URL

production:

```txt
coconique.jp
www.coconique.jp
app.coconique.jp
api.coconique.jp
admin.coconique.jp
status.coconique.jp
```

staging:

```txt
app.stg.coconique.jp
api.stg.coconique.jp
admin.stg.coconique.jp
```

---

## 5. Render

現時点では `config/environments/staging.rb` を作らない。

stagingでもRails実行環境は `RAILS_ENV=production` とし、運用上のstaging判定は `APP_ENV=staging` で行う。

```txt
coconique-api-prod
  branch: main
  domain: api.coconique.jp
  DB: coconique-db-prod
  RAILS_ENV=production
  APP_ENV=production

coconique-worker-prod
  branch: main
  DB: coconique-db-prod
  RAILS_ENV=production
  APP_ENV=production

coconique-api-stg
  branch: staging
  domain: api.stg.coconique.jp
  DB: coconique-db-stg
  RAILS_ENV=production
  APP_ENV=staging

coconique-worker-stg
  branch: staging
  DB: coconique-db-stg
  RAILS_ENV=production
  APP_ENV=staging
```

staging APIは本番DBを絶対に参照しない。stagingからproduction用のStripe/本人確認/Resend/R2キーを使わない。

---

## 6. Cookie / CSRF

本番・stagingとも、WebとAPIは別サブドメインになる。

```txt
production: app.coconique.jp → api.coconique.jp
staging:    app.stg.coconique.jp → api.stg.coconique.jp
```

現在のフロントはCSRF cookieを `document.cookie` で読み、`X-CSRF-Token` に載せる。APIが発行するCSRF cookieをWeb側が読めるように、cookie domainは親ドメインへ広げる。

staging:

```env
AUTH_COOKIE_DOMAIN=.stg.coconique.jp
AUTH_COOKIE_NAME=coconique_session
CSRF_COOKIE_NAME=coconique_csrf
AUTH_COOKIE_SECURE=true
AUTH_COOKIE_SAME_SITE=lax
```

production:

```env
AUTH_COOKIE_DOMAIN=.coconique.jp
AUTH_COOKIE_NAME=coconique_session
CSRF_COOKIE_NAME=coconique_csrf
AUTH_COOKIE_SECURE=true
AUTH_COOKIE_SAME_SITE=lax
```

`coconique_session` はHttpOnly、`coconique_csrf` はフロントから読めるcookieとして扱う。

---

## 7. Cloudflare Access

staging URLはURLを知っているだけの第三者に見られないようにする。

対象:

```txt
*.stg.coconique.jp
```

保護対象:

```txt
app.stg.coconique.jp
api.stg.coconique.jp
admin.stg.coconique.jp
```

設定イメージ:

```txt
Application: Coconique Staging
Public hostname: *.stg.coconique.jp
Policy: Allow only approved emails
Login method: One-time PIN
Allowed emails: kit.and.ms@gmail.com
```

WebhookはAccessを通れないため、必ずbypassする。

```txt
api.stg.coconique.jp/webhooks/stripe
api.stg.coconique.jp/webhooks/didit
api.stg.coconique.jp/webhooks/resend
api.stg.coconique.jp/webhooks/quick_trust
```

WebhookはAccessではなく、Provider署名検証で守る。

---

## 8. DB / Storage / 外部サービス分離

production / stagingで必ず分けるもの:

```txt
DATABASE_URL
SECRET_KEY_BASE
RAILS_MASTER_KEY / credentials
AUTH_COOKIE_DOMAIN / cookie設定
FRONTEND_ORIGIN
CORS_ALLOWED_ORIGINS
R2_ACCESS_KEY_ID
R2_SECRET_ACCESS_KEY
R2_BUCKET
STRIPE_SECRET_KEY
STRIPE_WEBHOOK_SECRET
STRIPE_PRICE_ID
RESEND_API_KEY
DIDIT / QUICKTRUST / STRIPE IDENTITY keys
```

Stripe:

```txt
staging → test mode
production → live mode
```

本人確認:

```txt
staging → staging用workflow / 検証用workflow / mock
production → production provider
```

Resend:

```txt
staging → 送信先制限またはstaging用ドメイン
production → production
```

---

## 9. 障害案内

Cloudflare障害時にも案内できるよう、Netlifyにも非常用ステータスページを置く。

```txt
status.coconique.jp
  → 通常のステータスページ

coconique-status.netlify.app
  → Cloudflare外の非常口
```

障害ページに載せる内容:

- 現在アクセスしづらい可能性があること
- 障害によって参加予定・チケット・申請内容が自動的に不利に扱われることはないこと
- 帰宅確認や安全相談の代替連絡先
- 復旧状況

将来的に検討する猶予フラグ:

```txt
incident_mode
home_check_grace_enabled
ticket_finalize_grace_enabled
cancellation_deadline_grace_enabled
outbound_mail_paused
```

特に帰宅確認は、インフラ障害で未回答扱いになり緊急連絡が誤爆しないよう、障害時猶予の仕組みを優先的に検討する。
