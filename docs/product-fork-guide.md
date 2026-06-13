# Product Fork Guide

このスターターは、コード・設計・テンプレートを複製して使うための共通基盤である。
Hodokoo / Coconique では、本番環境・DB・認証情報を共有しない。

## 派生時に必ず変更するもの

- DB名 / DATABASE_URL
- queue DB / QUEUE_DATABASE_URL
- `secret_key_base`
- Rails credentials / master key
- `AUTH_COOKIE_NAME`
- `CSRF_COOKIE_NAME`
- `AUTH_COOKIE_DOMAIN`
- `CURRENT_APP_KEY`
- `CURRENT_TERMS_VERSION`
- `CURRENT_PRIVACY_VERSION`
- `CORS_ALLOWED_ORIGINS`
- `FRONTEND_ORIGIN`
- `FRONTEND_EMAIL_VERIFICATION_URL`
- `FRONTEND_PASSWORD_RESET_URL`
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- Stripe products / prices / customer運用
- `RESEND_API_KEY`
- `RESEND_WEBHOOK_SECRET`
- `MAIL_FROM`
- 送信ドメイン
- ActiveStorage bucket
- 管理者アカウント
- ログ保存先
- 監視/通知先

## Hodokoo向け注意

Hodokooは契約書・営業トーク・AIチェック履歴など、非常にセンシティブな情報を扱う。

- 契約書/音声/AI結果の保存ポリシーを別途設計する
- 送信データの最小化を徹底する
- 非弁行為に見えない文言・UIを維持する
- Stripe / Resend / Storage をCoconiqueと共有しない

## Coconique向け注意

Coconiqueは本人確認・緊急連絡先・参加予定・集合場所・評価・通報履歴など、リアル被害につながる個人情報を扱う。

- 本人確認情報は共通スターターに入れない
- 緊急連絡先・通報・評価はCoconique側で慎重に追加する
- 管理画面・管理者権限はHodokooと共有しない
- 位置情報・集合場所のログ保持期間を明確にする

## Handoff zip作成時に含めるべきもの

API側は、現在のzipコマンドに加えて以下も含める。

```bash
app/lib \
app/services \
config/application.rb \
config/environments \
config/database.yml.example \
config/queue.yml \
bin/jobs \
db/queue_schema.rb
```

特に `app/lib/resend_delivery_method.rb` を含め忘れると、Resend送信が壊れる。

## Handoff zipに含めないもの

- `.env`
- `.env.local`
- `config/master.key`
- `config/credentials/*.key`
- `tmp/*`
- `log/*`
- `storage/*`
- 本番DB dump
- API key / webhook secret / secret_key_base
