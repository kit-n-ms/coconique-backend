## Resend custom delivery method

resend gem の標準ActionMailer adapterでは、環境によって `to` / `from` が配列として渡り、Resend APIで422になることがある。

そのため本基盤では `app/lib/resend_delivery_method.rb` を使い、`from` / `to` をResend API向けに明示的に文字列化する。

期待される確認値:

```bash
bin/rails runner 'puts "MAIL_PROVIDER=#{ENV["MAIL_PROVIDER"]}"; puts "delivery_method=#{ActionMailer::Base.delivery_method}"'
