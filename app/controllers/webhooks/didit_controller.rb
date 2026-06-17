require "json"
require "openssl"

module Webhooks
  class DiditController < ActionController::API
    MAX_TIMESTAMP_SKEW_SECONDS = 5.minutes.to_i

    def create
      raw_body = request.raw_post
      payload = JSON.parse(raw_body)

      verify_signature!(payload, raw_body)
      process_payload!(payload)

      render json: { ok: true }
    rescue JSON::ParserError
      render json: { ok: false, error: "invalid_payload" }, status: :bad_request
    rescue SignatureError => e
      Rails.logger.warn("[DiditWebhook] signature failed: #{e.message}")
      render json: { ok: false, error: "invalid_signature" }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("[DiditWebhook] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { ok: false, error: "webhook_processing_failed" }, status: :internal_server_error
    end

    private

    class SignatureError < StandardError; end

    def process_payload!(payload)
      webhook_type = payload["webhook_type"] || payload["webhookType"] || payload["type"] || payload["event_type"] || payload["eventType"]
      return if webhook_type.present? && !webhook_type.to_s.in?(%w[status.updated session.updated session.completed verification.completed])

      provider = ::Coconique::IdentityVerifications::DiditProvider.new
      decision = payload["decision"].is_a?(Hash) ? payload["decision"] : payload
      provider_session_id = provider.session_id_from(payload).to_s.presence || provider.session_id_from(decision).to_s
      local_session = CoconiqueIdentityVerificationSession.find_by(provider: "didit", provider_session_id: provider_session_id)

      if local_session.blank?
        Rails.logger.warn("[DiditWebhook] local session not found for #{provider_session_id}")
        return
      end

      provider.apply_decision_to_session!(
        local_session,
        decision,
        webhook_metadata: {
          "didit_webhook_type" => webhook_type,
          "didit_event_id" => payload["event_id"] || payload["eventId"] || payload["id"],
          "didit_webhook_received_at" => Time.current.iso8601
        }
      )
    end

    def verify_signature!(payload, raw_body)
      return if signature_optional_for_environment?

      secret = ENV["DIDIT_WEBHOOK_SECRET"].to_s
      raise SignatureError, "DIDIT_WEBHOOK_SECRET is blank" if secret.blank?

      timestamp = request.headers["X-Timestamp"].to_s
      raise SignatureError, "X-Timestamp is blank" if timestamp.blank?
      raise SignatureError, "timestamp is too old" if (Time.current.to_i - timestamp.to_i).abs > MAX_TIMESTAMP_SKEW_SECONDS

      signature_v2 = request.headers["X-Signature-V2"].to_s
      signature = request.headers["X-Signature"].to_s
      signature_simple = request.headers["X-Signature-Simple"].to_s

      return if signature_v2.present? && secure_compare_hex(signature_v2, hmac(secret, canonical_json(payload)))
      return if signature.present? && secure_compare_hex(signature, hmac(secret, raw_body))
      return if signature_simple.present? && secure_compare_hex(signature_simple, hmac(secret, simple_signature_payload(payload)))

      raise SignatureError, "no signature matched"
    end

    def signature_optional_for_environment?
      (Rails.env.development? || Rails.env.test?) && ENV["DIDIT_WEBHOOK_SECRET"].blank?
    end

    def canonical_json(value)
      JSON.generate(sort_json_value(value), space: nil, object_nl: nil, array_nl: nil)
    end

    def sort_json_value(value)
      case value
      when Array
        value.map { |item| sort_json_value(item) }
      when Hash
        value.keys.sort.each_with_object({}) { |key, obj| obj[key] = sort_json_value(value[key]) }
      else
        value
      end
    end

    def simple_signature_payload(payload)
      [payload["timestamp"], payload["session_id"], payload["status"], payload["webhook_type"]].join(":")
    end

    def hmac(secret, message)
      OpenSSL::HMAC.hexdigest("SHA256", secret, message.to_s)
    end

    def secure_compare_hex(a, b)
      return false if a.blank? || b.blank?

      ActiveSupport::SecurityUtils.secure_compare(a.to_s, b.to_s)
    rescue ArgumentError
      false
    end
  end
end
