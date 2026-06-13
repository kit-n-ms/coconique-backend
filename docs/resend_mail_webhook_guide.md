# Resend メール送信・Webhook 導入メモ

## 目的

このドキュメントは、共通認証基盤に Resend を導入し、以下を実現するための手順と仕様をまとめたものです。

- 開発環境では `MAIL_PROVIDER=file` で `tmp/mails` に保存する
- ステージング/本番相当では `MAIL_PROVIDER=resend` で実メール送信する
- `deliver_later` を Solid Queue 経由で処理する
- Resend Webhook を受け取り、送信・配信・遅延・バウンス・苦情・失敗・抑止イベントをDBに保存する
- バウンス/苦情/失敗/抑止されたメールアドレスを `email_suppressions` に保存し、以後の送信抑止に利用する

---

## 全体構成

```txt
Frontend
  ↓
Rails API
  ↓
AuthMailer
  ↓
ActionMailer
  ↓
ResendDeliveryMethod
  ↓
Resend API
  ↓
メール送信

Resend Webhook
  ↓
ngrok or production HTTPS endpoint
  ↓
Rails /webhooks/resend
  ↓
EmailWebhookEvent
  ↓
EmailSuppression
```

---

## Resend 側で行ったこと

### 1. ドメイン追加

Resend Dashboard で送信に使うドメインを追加します。

今回の例:

```txt
coconique.com
```

注意:

```txt
coconique.com と coconique.info.com は別ドメイン。
coconique.com を所有している場合、Resendに追加するのは coconique.com。
```

### 2. DNSレコード追加

Resendが表示するDNSレコードを、ドメイン管理画面に追加します。

Squarespaceで管理している場合、対象ドメインのDNS設定に以下のように追加します。

```txt
DKIM TXT:
Name: resend._domainkey
Value: p=MIGfMA... などResend指定値

SPF MX:
Name: send
Priority: 10
Mail Server: feedback-smtp...amazonses.com

SPF TXT:
Name: send
Value: v=spf1 include:amazonses.com ~all

DMARC TXT:
Name: _dmarc
Value: v=DMARC1; p=none;
```

### 3. Verify

Resend側でDNS確認を実行し、以下の状態になればOKです。

```txt
STATUS: Verified
Domain verified: Your domain is ready to send emails.
```

---

## 環境変数

Rails API / Solid Queue worker の両方で同じ環境変数を設定します。

```bash
export MAIL_PROVIDER=resend
export RESEND_API_KEY="re_xxxxxxxxxxxxxxxxx"
export MAIL_FROM="Coconique <no-reply@coconique.com>"
export FRONTEND_EMAIL_VERIFICATION_URL="http://localhost:5173/auth/email-verifications/confirm"
export FRONTEND_PASSWORD_RESET_URL="http://localhost:5173/auth/password-resets/confirm"
export RESEND_WEBHOOK_SECRET="whsec_xxxxxxxxxxxxxxxxx"
```

開発で `file` 保存にしたい場合:

```bash
export MAIL_PROVIDER=file
```

---

## mail_provider initializer

`config/initializers/mail_provider.rb`

```ruby
mail_provider = ENV.fetch(
  "MAIL_PROVIDER",
  Rails.env.production? ? "resend" : "file"
)

Rails.application.config.action_mailer.perform_deliveries = true
Rails.application.config.action_mailer.raise_delivery_errors = true
ActionMailer::Base.perform_deliveries = true
ActionMailer::Base.raise_delivery_errors = true

case mail_provider
when "resend"
  require Rails.root.join("app/lib/resend_delivery_method").to_s

  ActionMailer::Base.add_delivery_method(
    :resend_custom,
    ResendDeliveryMethod,
    api_key: ENV.fetch("RESEND_API_KEY")
  )

  Rails.application.config.action_mailer.delivery_method = :resend_custom
  ActionMailer::Base.delivery_method = :resend_custom

when "postmark"
  Rails.application.config.action_mailer.delivery_method = :postmark
  Rails.application.config.action_mailer.postmark_settings = {
    api_token: ENV.fetch("POSTMARK_API_TOKEN")
  }

  ActionMailer::Base.delivery_method = :postmark
  ActionMailer::Base.postmark_settings = {
    api_token: ENV.fetch("POSTMARK_API_TOKEN")
  }

when "file"
  Rails.application.config.action_mailer.delivery_method = :file
  Rails.application.config.action_mailer.file_settings = {
    location: Rails.root.join("tmp/mails")
  }

  ActionMailer::Base.delivery_method = :file
  ActionMailer::Base.file_settings = {
    location: Rails.root.join("tmp/mails")
  }

when "test"
  Rails.application.config.action_mailer.delivery_method = :test
  ActionMailer::Base.delivery_method = :test

else
  raise "Unknown MAIL_PROVIDER: #{mail_provider}"
end
```

確認コマンド:

```bash
bin/rails runner 'puts "MAIL_PROVIDER=#{ENV["MAIL_PROVIDER"]}"; puts "delivery_method=#{ActionMailer::Base.delivery_method}"'
```

期待値:

```txt
MAIL_PROVIDER=resend
delivery_method=resend_custom
```

---

## ResendDeliveryMethod

Resend gem の標準 ActionMailer adapter では、環境によって `to` / `from` が配列として渡り、Resend APIで422になることがあります。

そのため、本基盤ではカスタムdelivery methodを用意し、`from` / `to` をResend API向けに明示的に文字列化します。

`app/lib/resend_delivery_method.rb`

```ruby
require "resend"

class ResendDeliveryMethod
  def initialize(settings = {})
    @api_key = settings.fetch(:api_key)
  end

  def deliver!(mail)
    Resend.api_key = @api_key

    from = stringify_first(mail[:from]&.formatted) ||
      stringify_first(mail.from) ||
      ENV.fetch("MAIL_FROM")

    to = stringify_list(mail[:to]&.formatted) ||
      stringify_list(mail.to)

    raise ArgumentError, "email from is blank" if from.blank?
    raise ArgumentError, "email recipients are blank" if to.blank?

    params = {
      from: from,
      to: to,
      subject: mail.subject.to_s,
      html: html_body(mail),
      text: text_body(mail)
    }.compact

    Resend::Emails.send(params)
  end

  private

  def stringify_first(value)
    Array(value)
      .flatten
      .compact
      .map(&:to_s)
      .map(&:strip)
      .reject(&:blank?)
      .first
  end

  def stringify_list(value)
    values = Array(value)
      .flatten
      .compact
      .map(&:to_s)
      .map(&:strip)
      .reject(&:blank?)

    return nil if values.blank?

    values.join(",")
  end

  def html_body(mail)
    if mail.html_part
      mail.html_part.body.decoded
    elsif mail.mime_type == "text/html"
      mail.body.decoded
    end
  end

  def text_body(mail)
    if mail.text_part
      mail.text_part.body.decoded
    elsif mail.mime_type == "text/plain"
      mail.body.decoded
    end
  end
end
```

---

## development.rb の注意

`config/environments/development.rb` では、`delivery_method = :file` を固定しないようにします。

```ruby
config.action_mailer.perform_deliveries = true
config.action_mailer.raise_delivery_errors = true
# config.action_mailer.delivery_method = :file
config.action_mailer.file_settings = {
  location: Rails.root.join("tmp/mails")
}

config.action_mailer.perform_caching = false
config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
```

`delivery_method` は `config/initializers/mail_provider.rb` に集約します。

---

## ApplicationMailer の送信抑止チェック

`before_action` ではなく、`after_action` で抑止チェックします。

理由:

```txt
before_action は mail(to: ...) が設定される前に走る可能性がある。
そのため message.to が nil になり得る。
after_action なら宛先設定後にチェックできる。
```

`app/mailers/application_mailer.rb`

```ruby
class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "KM Auth Starter <no-reply@example.com>")
  layout "mailer"

  after_action :prevent_suppressed_recipient!

  private

  def prevent_suppressed_recipient!
    recipients = Array(message.to)
      .compact
      .map { |email| email.to_s.strip.downcase }
      .reject(&:blank?)

    return if recipients.blank?

    suppressed = recipients.find { |email| EmailSuppression.suppressed?(email) }

    return if suppressed.blank?

    Rails.logger.warn("[Mailer] suppressed recipient blocked: #{suppressed}")

    message.perform_deliveries = false
  end
end
```

---

## AuthMailer の確認

`app/mailers/auth_mailer.rb`

```ruby
class AuthMailer < ApplicationMailer
  def email_verification(user, token)
    @user = user
    @token = token
    @url = build_url(
      ENV.fetch(
        "FRONTEND_EMAIL_VERIFICATION_URL",
        "http://localhost:5173/auth/email-verifications/confirm"
      ),
      token
    )

    mail(
      to: @user.email,
      subject: "メールアドレス確認のお願い"
    )
  end

  def password_reset(user, token)
    @user = user
    @token = token
    @url = build_url(
      ENV.fetch(
        "FRONTEND_PASSWORD_RESET_URL",
        "http://localhost:5173/auth/password-resets/confirm"
      ),
      token
    )

    mail(
      to: @user.email,
      subject: "パスワード再設定のご案内"
    )
  end

  private

  def build_url(base_url, token)
    separator = base_url.include?("?") ? "&" : "?"
    "#{base_url}#{separator}token=#{CGI.escape(token)}"
  end
end
```

宛先確認:

```bash
bin/rails runner 'user = User.find_by!(email: "kit.and.ms+200@gmail.com"); delivery = AuthMailer.email_verification(user, "debug-token"); message = delivery.message; p message.to; p message.to.class; p message[:to]&.value; p message.subject'
```

期待値:

```txt
["kit.and.ms+200@gmail.com"]
Mail::AddressContainer
"kit.and.ms+200@gmail.com"
"メールアドレス確認のお願い"
```

---

## Solid Queue worker

`deliver_later` を使う場合、Rails serverとは別にworkerを起動します。

```bash
bin/jobs start
```

worker側にも、Rails server側と同じENVが必要です。

```bash
export MAIL_PROVIDER=resend
export RESEND_API_KEY="re_xxxxxxxxxxxxxxxxx"
export MAIL_FROM="Coconique <no-reply@coconique.com>"
export FRONTEND_EMAIL_VERIFICATION_URL="http://localhost:5173/auth/email-verifications/confirm"
export FRONTEND_PASSWORD_RESET_URL="http://localhost:5173/auth/password-resets/confirm"
export RESEND_WEBHOOK_SECRET="whsec_xxxxxxxxxxxxxxxxx"

bin/jobs start
```

確認:

```bash
bin/rails runner '
puts "ReadyExecution: #{SolidQueue::ReadyExecution.count}"
puts "ClaimedExecution: #{SolidQueue::ClaimedExecution.count}"
puts "FailedExecution: #{SolidQueue::FailedExecution.count}"
puts "Jobs: #{SolidQueue::Job.count}"

puts "\nRecent jobs:"
SolidQueue::Job.order(created_at: :desc).limit(10).each do |j|
  p j.attributes.slice("id", "queue_name", "class_name", "active_job_id", "finished_at", "created_at", "updated_at")
end
'
```

---

## Resend 実送信確認

### deliver_now

```bash
bin/rails runner 'user = User.find_by!(email: "kit.and.ms+200@gmail.com"); AuthMailer.email_verification(user, "resend-direct-final").deliver_now; puts "sent now"'
```

期待:

```txt
sent now
```

Resend Logs で `/emails` が `200` になり、実メールが届けばOK。

### deliver_later

```bash
bin/rails runner 'user = User.find_by!(email: "kit.and.ms+200@gmail.com"); AuthMailer.email_verification(user, "resend-later-final").deliver_later; puts "enqueued"'
```

期待:

```txt
enqueued
```

`deliver_later` はキューに積むだけなので、ターミナル表示は `enqueued` で正常です。実送信は `bin/jobs start` が処理します。

---

## Webhook 用モデル

### email_webhook_events

Resendから受け取ったイベントを保存します。

主なカラム:

```txt
provider
event_id
event_type
email
message_id
status
reason
payload
metadata
processed_at
processing_error
```

### email_suppressions

バウンス、苦情、失敗、抑止されたメールアドレスを保存します。

主なカラム:

```txt
email
reason
source
source_event_id
suppressed_at
metadata
```

---

## Webhook route

`config/routes.rb`

```ruby
Rails.application.routes.draw do
  post "webhooks/stripe", to: "webhooks/stripe#create"
  post "webhooks/resend", to: "webhooks/resend#create"

  namespace :api do
    namespace :v1 do
      # ...
    end
  end
end
```

Webhookは外部サービスから叩かれるため、`/api/v1` の外側に置きます。

---

## Resend Webhook Controller

`app/controllers/webhooks/resend_controller.rb`

概要:

```txt
- request.raw_post を使う
- svix-id / svix-timestamp / svix-signature で署名検証する
- payload を deep_stringify_keys する
- svix-id をevent_idとして優先利用する
- EmailWebhookEvent に保存する
- bounced / complained / failed / suppressed は EmailSuppression に保存する
- 同じsvix-idが来た場合は冪等にスキップする
```

---

## ngrok でローカルWebhook確認

Resendから localhost は直接叩けないため、ngrok等で外部URLを作ります。

```bash
ngrok http 3000
```

例:

```txt
https://motor-rambling-cobweb.ngrok-free.dev
```

Resend Webhook Endpoint URL:

```txt
https://motor-rambling-cobweb.ngrok-free.dev/webhooks/resend
```

### Rails Host Authorization 対応

`config/environments/development.rb`

```ruby
if ENV["NGROK_HOST"].present?
  config.hosts << ENV["NGROK_HOST"]
end
```

起動時:

```bash
export NGROK_HOST="motor-rambling-cobweb.ngrok-free.dev"
bin/rails s
```

署名なしcurl確認:

```bash
curl -i \
  -X POST http://localhost:3000/webhooks/resend \
  -H "Content-Type: application/json" \
  -d '{"type":"email.bounced"}'
```

期待値:

```txt
HTTP/1.1 400 Bad Request
{"ok":false,"error":"invalid_webhook"}
```

署名なしWebhookが400になるのは正常です。

---

## Webhook受信確認

Webhookイベント履歴:

```bash
bin/rails runner 'p EmailWebhookEvent.recent.limit(20).pluck(:event_id, :event_type, :email, :message_id, :processed_at, :processing_error)'
```

成功例:

```txt
[
  ["msg_...", "email.delivered", "kit.and.ms+200@gmail.com", "66143bf3-047b-4743-9f4b-15c1409e46d3", ..., nil],
  ["msg_...", "email.sent", "kit.and.ms+200@gmail.com", "66143bf3-047b-4743-9f4b-15c1409e46d3", ..., nil]
]
```

古いWebhookイベントを開発中に消す場合:

```bash
bin/rails runner 'EmailWebhookEvent.delete_all; puts "email webhook events cleared"'
```

mari@example.com だけ消す場合:

```bash
bin/rails runner 'EmailWebhookEvent.where(email: "mari@example.com").delete_all; puts "mari@example.com webhook events cleared"'
```

---

## Resend Webhook イベントの意味

ResendのWebhookはHTTPSでJSON payloadを送るリアルタイム通知です。アプリケーション側では、イベントをDBに保存し、重複や順序の前後に備えて処理します。

### email.sent

Resend APIへの送信リクエストが成功し、Resendが受信者メールサーバーへの配送を試みる状態。

意味:

```txt
Rails → Resend API への送信依頼は成功した。
ただし、受信者のメールボックスに届いたことまでは保証しない。
```

保存用途:

```txt
送信要求がResendに受理された履歴
```

---

### email.delivered

Resendが受信者側のメールサーバーにメールを正常に渡した状態。

意味:

```txt
受信者のメールサーバーまでは届いた。
ただし、受信箱に表示されたか、迷惑メールに入ったかまでは別問題。
```

保存用途:

```txt
配信成功履歴
```

---

### email.delivery_delayed

一時的な理由で受信者側メールサーバーに配信できなかった状態。

例:

```txt
受信者側メールサーバーの一時障害
受信箱容量などの一時的問題
一時的なレート制限
```

意味:

```txt
まだ最終失敗ではない。
後でdelivered/bounced/failedに変わる可能性がある。
```

保存用途:

```txt
配送遅延の監視
```

注意:

```txt
email.delivery_delayed は即suppression対象にしない。
```

---

### email.bounced

受信者側メールサーバーがメールを恒久的に拒否した状態。

例:

```txt
存在しないメールアドレス
受信者ドメインが受信拒否
ハードバウンス
```

意味:

```txt
この宛先へ今後送っても届かない可能性が高い。
```

保存用途:

```txt
EmailSuppression に reason=bounced で保存。
以後の送信抑止に利用。
```

---

### email.complained

メールは配信されたが、受信者が迷惑メールとして報告した状態。

意味:

```txt
受信者がスパム報告した。
送信ドメイン評価に悪影響がある。
```

保存用途:

```txt
EmailSuppression に reason=complained で保存。
以後の送信抑止に利用。
```

重要度:

```txt
かなり高い。
complained は基本的に即送信停止対象。
```

---

### email.failed

Resendがメール送信に失敗した状態。

例:

```txt
無効な受信者
API key の問題
ドメイン検証の問題
送信クォータ制限
その他Resend側/設定側の送信失敗
```

意味:

```txt
送信処理自体が失敗した。
原因は宛先だけとは限らない。
```

保存用途:

```txt
EmailWebhookEvent に保存。
必要に応じて EmailSuppression に reason=failed で保存。
```

注意:

```txt
email.failed は設定ミスやクォータでも起きるため、
本番運用では即suppressionにするかは慎重に判断する。
共通基盤では安全側でsuppression対象にしつつ、管理画面から解除できる設計が望ましい。
```

---

### email.suppressed

Resend側でメール送信が抑止された状態。

例:

```txt
Resend側のsuppression listに入っている
過去のバウンス/苦情により送信抑止されている
```

意味:

```txt
Resendが送信すべきでない宛先として扱っている。
```

保存用途:

```txt
EmailSuppression に reason=suppressed で保存。
以後の送信抑止に利用。
```

---

## Suppression方針

抑止対象:

```txt
email.bounced
email.complained
email.failed
email.suppressed
```

即抑止しない:

```txt
email.sent
email.delivered
email.delivery_delayed
```

理由:

```txt
sent/delivered は正常系。
delivery_delayed は一時的な遅延であり、最終失敗ではない。
```

---

## トラブルシューティング

### 1. Resend Logsに出ない

確認:

```bash
bin/rails runner 'puts "MAIL_PROVIDER=#{ENV["MAIL_PROVIDER"]}"; puts "delivery_method=#{ActionMailer::Base.delivery_method}"'
```

期待:

```txt
MAIL_PROVIDER=resend
delivery_method=resend_custom
```

`delivery_method=file` の場合、Resendには送られず `tmp/mails` に保存されます。

確認:

```bash
ls -lt tmp/mails | head
```

---

### 2. `The to field must be a string`

原因:

```txt
Resend APIに to が配列で渡っている。
```

対応:

```txt
ResendDeliveryMethodで to を文字列化する。
```

---

### 3. `The from field must be a string`

原因:

```txt
Resend APIに from が配列で渡っている。
```

対応:

```txt
ResendDeliveryMethodで from を文字列化する。
```

---

### 4. `Domain not verified`

原因:

```txt
MAIL_FROM のドメインがResendでVerifiedになっていない。
```

例:

```txt
Verified: coconique.com
NG: no-reply@send.coconique.com
OK: no-reply@coconique.com
```

今回の方針:

```txt
MAIL_FROM="Coconique <no-reply@coconique.com>"
```

---

### 5. WebhookがBlocked hostsになる

原因:

```txt
Rails development の Host Authorization がngrok hostを拒否している。
```

対応:

```ruby
if ENV["NGROK_HOST"].present?
  config.hosts << ENV["NGROK_HOST"]
end
```

---

### 6. 署名なしcurlが400になる

これは正常です。

```txt
Webhook署名検証が効いている。
```

---

### 7. EmailWebhookEventが空

確認:

```txt
Resend Webhook Endpoint URLが正しいか
ngrok URLが最新か
RESEND_WEBHOOK_SECRETが正しいか
Rails serverにNGROK_HOSTを設定したか
署名検証で落ちていないか
```

---

## 開発中のクリアコマンド

Solid Queue失敗履歴:

```bash
bin/rails runner 'SolidQueue::FailedExecution.delete_all; puts "failed executions cleared"'
```

Webhook履歴:

```bash
bin/rails runner 'EmailWebhookEvent.delete_all; puts "email webhook events cleared"'
```

Suppression:

```bash
bin/rails runner 'EmailSuppression.delete_all; puts "email suppressions cleared"'
```

---

## 完了条件

```txt
- MAIL_PROVIDER=file で tmp/mails に保存できる
- MAIL_PROVIDER=resend で Resend実送信できる
- MAIL_FROM をENVで切り替えられる
- FRONTEND_EMAIL_VERIFICATION_URL をENVで切り替えられる
- FRONTEND_PASSWORD_RESET_URL をENVで切り替えられる
- deliver_now がResend Logs 200になる
- deliver_later がSolid Queue経由でResend Logs 200になる
- 実メールが届く
- /webhooks/resend が署名なしcurlを400で拒否する
- Resend署名付きWebhookが EmailWebhookEvent に保存される
- email.sent / email.delivered が保存される
- bounced/complained/failed/suppressed を EmailSuppression に保存できる
- AuthMailerTest が通る
- docs/mail-provider.md がある
```

---

## 派生時の注意

Hodokoo / Coconique に派生する時は、以下を分離します。

```txt
- 送信ドメイン
- MAIL_FROM
- RESEND_API_KEY
- RESEND_WEBHOOK_SECRET
- FRONTEND_EMAIL_VERIFICATION_URL
- FRONTEND_PASSWORD_RESET_URL
- Webhook Endpoint URL
- メールログ
- suppression / bounce / complaint 管理
```

Hodokoo例:

```env
MAIL_FROM="Hodokoo <no-reply@hodokoo.com>"
FRONTEND_EMAIL_VERIFICATION_URL=https://hodokoo.com/auth/email-verifications/confirm
FRONTEND_PASSWORD_RESET_URL=https://hodokoo.com/auth/password-resets/confirm
```

Coconique例:

```env
MAIL_FROM="Coconique <no-reply@coconique.com>"
FRONTEND_EMAIL_VERIFICATION_URL=https://coconique.com/auth/email-verifications/confirm
FRONTEND_PASSWORD_RESET_URL=https://coconique.com/auth/password-resets/confirm
```

---

## 本番化前にやること

```txt
- localhost URLを本番URLに変える
- Resend Webhook Endpointを本番API URLに変える
- ngrok設定はdevelopment限定にする
- MAIL_FROMを本番送信元にする
- Google Postmaster Tools等でドメイン評価を監視する
- DMARCは最初 p=none、安定後に quarantine/reject を検討する
- email.opened / email.clicked はプライバシーポリシー整備後に検討する
```
