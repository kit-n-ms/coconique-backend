# 第15段階：本番運用準備・複製前仕上げ

## 目的

この段階では、認証・メール・決済・Webhook・ジョブ基盤が揃った共通スターターを、Hodokoo / Coconique に安全に複製できる状態へ近づける。

新機能を大きく増やすのではなく、以下を整える。

- 生存監視・疎通確認
- 環境変数の確認
- Solid Queue worker の起動確認
- Stripe / Resend / Webhook の設定漏れ検出
- 開発用データ掃除タスク
- 派生時に必ず変更する項目の明文化

## 追加するエンドポイント

### `GET /up`

アプリケーションプロセスが起動しているかを確認する軽量エンドポイント。
DB接続確認はしない。

ロードバランサーやホスティングサービスの簡易ヘルスチェック向け。

### `GET /healthz`

以下を確認する。

- primary DB 接続
- Solid Queue DB 接続

### `GET /readiness`

以下を確認する。

- primary DB 接続
- Solid Queue DB 接続
- Solid Queue 必須テーブル
- Mail Provider 設定
- Frontend URL / CORS 系設定
- Cookie 名 / Cookie セキュリティ設定
- Stripe 設定
- Resend Webhook 設定

`/readiness` は運用者向け確認用。外部公開時は認証やIP制限を検討する。

## 追加するRakeタスク

### `bin/rails km:doctor`

現在の環境変数・DB・Queue・Mailer・Stripe・Resend設定を確認する。

```bash
bin/rails km:doctor
```

期待例:

```txt
✅ database: primary database is reachable
✅ queue_database: Solid Queue database is reachable
✅ solid_queue_tables: required tables exist
✅ mail_provider: resend / resend_custom
```

### 開発用掃除タスク

```bash
bin/rails dev:clear_solid_queue_failures
bin/rails dev:clear_email_webhook_events
bin/rails dev:clear_email_suppressions
bin/rails dev:clear_tmp_mails
bin/rails dev:clear_local_artifacts
```

すべて `development` 専用。

## stage15導入後の確認

```bash
bin/rails routes | grep -E "up|healthz|readiness"

curl -i http://localhost:3000/up
curl -i http://localhost:3000/healthz
curl -i http://localhost:3000/readiness

bin/rails km:doctor
```

## 注意

今回のResend送信には `app/lib/resend_delivery_method.rb` が必要。
Handoff zip作成時に `app/lib` を含め忘れると、`cannot load such file -- resend_delivery_method` になる。
