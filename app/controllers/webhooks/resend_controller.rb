require "svix"

module Webhooks
  class ResendController < ActionController::API
    PROVIDER = "resend"

    SUPPRESSION_EVENT_TYPES = {
      "email.bounced" => EmailSuppression::REASON_BOUNCED,
      "email.complained" => EmailSuppression::REASON_COMPLAINED,
      "email.failed" => EmailSuppression::REASON_FAILED,
      "email.suppressed" => EmailSuppression::REASON_SUPPRESSED
    }.freeze

    def create
      payload = verified_payload!

      webhook_event = find_or_initialize_event!(payload)

      if webhook_event.persisted? && webhook_event.processed?
        return render json: { ok: true, skipped: true }
      end

      webhook_event.save!

      process_event!(webhook_event)

      webhook_event.update!(
        processed_at: Time.current,
        processing_error: nil
      )

      render json: { ok: true }
    rescue Svix::WebhookVerificationError, JSON::ParserError => e
      Rails.logger.warn("[ResendWebhook] invalid webhook: #{e.class}: #{e.message}")
      render json: { ok: false, error: "invalid_webhook" }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("[ResendWebhook] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      if defined?(webhook_event) && webhook_event.present?
        webhook_event.update!(
          processing_error: "#{e.class}: #{e.message}"
        )
      end

      render json: { ok: false, error: "webhook_processing_failed" }, status: :internal_server_error
    end

    private

    def verified_payload!
      raw_payload = request.raw_post
      secret = ENV.fetch("RESEND_WEBHOOK_SECRET")

      headers = {
        "svix-id" => request.headers["svix-id"],
        "svix-timestamp" => request.headers["svix-timestamp"],
        "svix-signature" => request.headers["svix-signature"]
      }.compact

      verified = Svix::Webhook.new(secret).verify(raw_payload, headers)

      payload =
        case verified
        when String
          JSON.parse(verified)
        when Hash
          JSON.parse(verified.to_json)
        else
          JSON.parse(verified.to_json)
        end

      payload.deep_stringify_keys
    end

    def find_or_initialize_event!(payload)
      payload = payload.deep_stringify_keys

      event_type = payload["type"].to_s
      data = (payload["data"] || {}).deep_stringify_keys

      svix_id = request.headers["svix-id"].presence

      message_id =
        data["email_id"].presence ||
        data["id"].presence ||
        data["message_id"].presence ||
        payload["id"].presence

      event_id =
        svix_id ||
        payload["event_id"].presence ||
        "#{event_type}:#{message_id}:#{payload["created_at"]}"

      event = EmailWebhookEvent.find_or_initialize_by(
        provider: PROVIDER,
        event_id: event_id
      )

      event.assign_attributes(
        event_type: event_type,
        email: extract_email(data),
        message_id: message_id,
        status: data["status"],
        reason: extract_reason(data),
        payload: payload,
        metadata: {
          svix_id: svix_id,
          svix_timestamp: request.headers["svix-timestamp"],
          payload_id: payload["id"]
        }
      )

      event
    end

    def process_event!(webhook_event)
      reason = SUPPRESSION_EVENT_TYPES[webhook_event.event_type]

      return if reason.blank?

      EmailSuppression.suppress!(
        email: webhook_event.email,
        reason: reason,
        source: PROVIDER,
        source_event_id: webhook_event.event_id,
        metadata: {
          event_type: webhook_event.event_type,
          message_id: webhook_event.message_id,
          reason: webhook_event.reason
        }
      )
    end

    def extract_email(data)
      to = data["to"] || data["email"]

      case to
      when Array
        to.first.to_s.strip.downcase
      else
        to.to_s.strip.downcase
      end
    end

    def extract_message_id(data)
      data["email_id"].presence ||
        data["id"].presence ||
        data["message_id"].presence
    end

    def extract_reason(data)
      data["reason"].presence ||
        data["error"].presence ||
        data.dig("bounce", "message").presence ||
        data.dig("complaint", "message").presence
    end
  end
end
