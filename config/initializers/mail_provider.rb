# config/initializers/mail_provider.rb

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