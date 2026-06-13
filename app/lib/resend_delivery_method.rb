# app/lib/resend_delivery_method.rb

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
