# Handoff Guide

このドキュメントは、KM Auth Starterを別チャット・別プロダクトへ引き渡すための手順をまとめたもの。

## API handoff zip作成

Rails APIプロジェクト直下で実行する。

```bash
zip -r coconique_api_handoff.zip \
  app/controllers \
  app/models \
  app/mailers \
  app/views \
  app/lib \
  config/application.rb \
  config/routes.rb \
  config/initializers \
  config/environments \
  config/queue.yml \
  bin/jobs \
  db/migrate \
  db/queue_schema.rb \
  db/seeds.rb \
  lib/tasks \
  test \
  docs \
  Gemfile \
  Gemfile.lock \
  .env.example \
  README.md \
  -x "*.DS_Store" \
  -x "log/*" \
  -x "tmp/*" \
  -x "storage/*" \
  -x ".env" \
  -x ".env.local" \
  -x "config/master.key" \
  -x "config/credentials/*.key" \
  -x "config/database.yml"
```

`config/database.yml` は実値を含む可能性があるため、handoffには原則含めない。必要なら `config/database.yml.example` を別途作る。

## Frontend handoff zip作成

Frontendプロジェクト直下で実行する。

```bash
zip -r km_auth_starter_web_handoff.zip \
  src \
  public \
  index.html \
  package.json \
  package-lock.json \
  vite.config.ts \
  vitest.config.ts \
  tsconfig.json \
  tsconfig.app.json \
  tsconfig.node.json \
  .env.example \
  docs \
  -x "*.DS_Store" \
  -x "node_modules/*" \
  -x "dist/*" \
  -x "coverage/*" \
  -x ".env" \
  -x ".env.local"
```

## Handoff時に必ず伝えること

- 現在の目的
- ここまで実装済みの機能
- 未実装の機能
- 直近の成功確認
- 直近の未解決課題
- 使用中のENV一覧
- 秘密情報は含めていないこと

## Handoff前チェック

```bash
bin/rails test
bin/rails km:doctor
curl -i http://localhost:3000/up
curl -i http://localhost:3000/healthz
curl -i http://localhost:3000/readiness
npm run test
npm run build
```

## 含めてはいけないもの

- `.env`
- `.env.local`
- `config/master.key`
- `config/credentials/*.key`
- API keys
- webhook secrets
- Stripe secret keys
- Resend API keys
- 実ユーザーデータ
- log / tmp / storage
- node_modules
- dist
- coverage

## Handoff後の初回確認

受け取り側では、以下を確認する。

```bash
bundle install
bin/rails db:prepare
bin/rails test
bin/rails km:doctor
```

Frontend:

```bash
npm i
npm run test
npm run build
```
