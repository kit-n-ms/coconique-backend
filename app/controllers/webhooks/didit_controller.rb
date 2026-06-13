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
      return unless payload["webhook_type"].to_s == "status.updated"

      provider_session_id = payload["session_id"].to_s
      local_session = CoconiqueIdentityVerificationSession.find_by(provider: "didit", provider_session_id: provider_session_id)

      if local_session.blank?
        Rails.logger.warn("[DiditWebhook] local session not found for #{provider_session_id}")
        return
      end

      provider = ::Coconique::IdentityVerifications::DiditProvider.new
      decision = payload["decision"].is_a?(Hash) ? payload["decision"] : payload
      provider_status = payload["status"].presence || decision["status"]
      workflow_type = local_session.workflow_type.presence || decision.dig("metadata", "workflow_type") || "standard_document"
      document_type = provider.document_type_for(decision: decision, workflow_type: workflow_type)
      safe_metadata = provider.safe_decision_metadata(decision, workflow_type: workflow_type)

      case provider.status_for(provider_status)
      when :verified
        local_session.mark_verified!(
          provider_session_id: provider_session_id,
          age_over_18: true,
          document_type: document_type,
          provider_status: provider_status,
          metadata: safe_metadata.merge("didit_webhook_type" => payload["webhook_type"], "didit_event_id" => payload["event_id"])
        )
        delete_provider_session!(provider, local_session)
      when :rejected
        local_session.mark_rejected!(
          reason: "didit_declined",
          provider_status: provider_status,
          document_type: document_type,
          metadata: safe_metadata.merge("didit_webhook_type" => payload["webhook_type"], "didit_event_id" => payload["event_id"])
        )
        delete_provider_session!(provider, local_session)
      when :expired
        local_session.mark_expired!(
          provider_status: provider_status,
          metadata: safe_metadata.merge("didit_webhook_type" => payload["webhook_type"], "didit_event_id" => payload["event_id"])
        )
        delete_provider_session!(provider, local_session)
      else
        local_session.mark_processing!(
          provider_status: provider_status,
          metadata: safe_metadata.merge("didit_webhook_type" => payload["webhook_type"], "didit_event_id" => payload["event_id"])
        )
      end
    end

    def delete_provider_session!(provider, local_session)
      return if local_session.provider_session_id.blank?
      return if local_session.deleted_at.present?

      local_session.mark_provider_session_deleted! if provider.delete_session(local_session.provider_session_id)
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
