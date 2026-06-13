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