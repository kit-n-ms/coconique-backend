require "json"
require "openssl"

module Webhooks
  class QuickTrustController < ActionController::API
    MAX_TIMESTAMP_SKEW_SECONDS = 5.minutes.to_i

    def create
      raw_body = request.raw_post
      payload = JSON.parse(raw_body)

      verify_signature!(raw_body)
      process_payload!(payload)

      render json: { ok: true }
    rescue JSON::ParserError
      render json: { ok: false, error: "invalid_payload" }, status: :bad_request
    rescue SignatureError => e
      Rails.logger.warn("[QuickTrustWebhook] signature failed: #{e.message}")
      render json: { ok: false, error: "invalid_signature" }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("[QuickTrustWebhook] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { ok: false, error: "webhook_processing_failed" }, status: :internal_server_error
    end

    private

    class SignatureError < StandardError; end

    def process_payload!(payload)
      provider = ::Coconique::IdentityVerifications::QuickTrustProvider.new
      provider_session_id = provider.provider_session_id_from(payload).to_s
      if provider_session_id.blank?
        Rails.logger.warn("[QuickTrustWebhook] provider session id missing")
        return
      end

      local_session = CoconiqueIdentityVerificationSession.find_by(provider: "quick_trust", provider_session_id: provider_session_id)
      if local_session.blank?
        Rails.logger.warn("[QuickTrustWebhook] local session not found for #{provider_session_id}")
        return
      end

      provider_status = provider.provider_status_from(payload)
      workflow_type = local_session.workflow_type.presence || payload.dig("metadata", "workflow_type") || payload.dig("data", "workflow_type") || "standard_document"
      document_type = provider.document_type_for(payload: payload, workflow_type: workflow_type)
      safe_metadata = provider.safe_webhook_metadata(payload, workflow_type: workflow_type)

      case provider.status_for(provider_status)
      when :verified
        local_session.mark_verified!(
          provider_session_id: provider_session_id,
          age_over_18: age_over_18_from(payload),
          document_type: document_type,
          provider_status: provider_status,
          metadata: safe_metadata
        )
        delete_provider_session!(provider, local_session)
      when :rejected
        local_session.mark_rejected!(
          reason: "quick_trust_rejected",
          provider_status: provider_status,
          document_type: document_type,
          metadata: safe_metadata
        )
        delete_provider_session!(provider, local_session)
      when :expired
        local_session.mark_expired!(provider_status: provider_status, metadata: safe_metadata)
        delete_provider_session!(provider, local_session)
      when :canceled
        local_session.mark_canceled!(provider_status: provider_status, metadata: safe_metadata)
        delete_provider_session!(provider, local_session)
      when :requires_input
        local_session.mark_requires_input!(provider_status: provider_status, metadata: safe_metadata)
      else
        local_session.mark_processing!(provider_status: provider_status, metadata: safe_metadata)
      end
    end

    def age_over_18_from(payload)
      value = payload["age_over_18"] ||
        payload["ageOver18"] ||
        payload.dig("data", "age_over_18") ||
        payload.dig("data", "ageOver18") ||
        payload.dig("result", "age_over_18") ||
        payload.dig("result", "ageOver18")

      return true if value.nil?

      ActiveModel::Type::Boolean.new.cast(value)
    end

    def delete_provider_session!(provider, local_session)
      return if local_session.provider_session_id.blank?
      return if local_session.deleted_at.present?

      local_session.mark_provider_session_deleted! if provider.delete_session(local_session.provider_session_id)
    end

    def verify_signature!(raw_body)
      return if signature_optional_for_environment?

      secret = ENV["QUICK_TRUST_WEBHOOK_SECRET"].to_s
      raise SignatureError, "QUICK_TRUST_WEBHOOK_SECRET is blank" if secret.blank?

      timestamp = request.headers["X-QuickTrust-Timestamp"].presence || request.headers["X-Timestamp"].to_s
      if timestamp.present? && (Time.current.to_i - timestamp.to_i).abs > MAX_TIMESTAMP_SKEW_SECONDS
        raise SignatureError, "timestamp is too old"
      end

      expected = hmac(secret, raw_body)
      signatures = [
        request.headers["X-QuickTrust-Signature"],
        request.headers["X-Quicktrust-Signature"],
        request.headers["X-Signature"],
        request.headers["X-Signature-V2"]
      ].compact.map(&:to_s).reject(&:blank?)

      return if signatures.any? { |signature| secure_compare_signature(signature, expected) }

      raise SignatureError, "no signature matched"
    end

    def signature_optional_for_environment?
      (Rails.env.development? || Rails.env.test?) && ENV["QUICK_TRUST_WEBHOOK_SECRET"].blank?
    end

    def hmac(secret, message)
      OpenSSL::HMAC.hexdigest("SHA256", secret, message.to_s)
    end

    def secure_compare_signature(signature, expected_hex)
      normalized = signature.to_s.sub(/\Asha256=/i, "")
      return false if normalized.blank?

      ActiveSupport::SecurityUtils.secure_compare(normalized, expected_hex)
    rescue ArgumentError
      false
    end
  end
end
