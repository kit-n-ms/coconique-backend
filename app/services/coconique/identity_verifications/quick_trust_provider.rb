require "net/http"
require "json"

module Coconique
  module IdentityVerifications
    class QuickTrustProvider
      class ConfigurationError < StandardError; end
      class ApiError < StandardError; end
      class LiveApiNotImplementedError < StandardError; end

      PROVIDER_KEY = "quick_trust".freeze
      STANDARD_WORKFLOW_TYPE = "standard_document".freeze
      MY_NUMBER_WORKFLOW_TYPE = "my_number_front_only".freeze

      # Quick Trustの正式API仕様が確定するまでは、開発/検証用stubとして安全に待機する。
      # 本接続時は create_live_session! / delete_live_session! / verify webhook signature 部分だけ差し替える想定。
      def self.configured?
        stub_mode? || (live_enabled? && live_configured?)
      end

      def self.live_enabled?
        ActiveModel::Type::Boolean.new.cast(ENV.fetch("QUICK_TRUST_LIVE_ENABLED", "false"))
      end

      def self.live_configured?
        ENV["QUICK_TRUST_API_KEY"].present? && ENV["QUICK_TRUST_API_BASE_URL"].present?
      end

      def self.stub_mode?
        return true if Rails.env.development? || Rails.env.test?

        ActiveModel::Type::Boolean.new.cast(ENV.fetch("QUICK_TRUST_STUB_MODE", "false"))
      end

      def self.my_number_enabled?
        ActiveModel::Type::Boolean.new.cast(ENV.fetch("QUICK_TRUST_MY_NUMBER_CARD_ENABLED", "false"))
      end

      def create_session(user:, return_url:, workflow_type: STANDARD_WORKFLOW_TYPE)
        workflow_type = normalize_workflow_type(workflow_type)

        if self.class.stub_mode?
          return create_stub_session!(user: user, return_url: return_url, workflow_type: workflow_type)
        end

        unless self.class.live_enabled? && self.class.live_configured?
          raise ConfigurationError, "Quick Trust live APIはまだ有効化されていません。正式API仕様確定後に QUICK_TRUST_LIVE_ENABLED=true と接続情報を設定してください。"
        end

        create_live_session!(user: user, return_url: return_url, workflow_type: workflow_type)
      end

      def delete_session(provider_session_id)
        return false if provider_session_id.blank?
        return true if self.class.stub_mode? || provider_session_id.to_s.start_with?("qt_stub_")

        delete_live_session!(provider_session_id)
      rescue ApiError, LiveApiNotImplementedError => e
        Rails.logger.warn("[QuickTrust] delete_session failed: #{e.message}")
        false
      end

      def status_for(provider_status)
        normalized = provider_status.to_s.downcase.tr("_", " ").strip

        case normalized
        when "approved", "verified", "complete", "completed", "passed", "pass", "ok", "success"
          :verified
        when "declined", "rejected", "failed", "fail", "ng", "denied"
          :rejected
        when "expired", "timeout", "timed out"
          :expired
        when "canceled", "cancelled", "abandoned"
          :canceled
        when "requires input", "requires input from user", "resubmission required", "retry required"
          :requires_input
        when "created", "not started", "initialized"
          :created
        else
          :processing
        end
      end

      def document_type_for(payload:, workflow_type:)
        return "my_number_card" if workflow_type.to_s == MY_NUMBER_WORKFLOW_TYPE

        raw = [
          payload["document_type"],
          payload["documentType"],
          payload.dig("document", "type"),
          payload.dig("data", "document_type"),
          payload.dig("data", "documentType"),
          payload.dig("result", "document_type"),
          payload.dig("result", "documentType")
        ].compact.first.to_s.downcase

        case raw
        when /passport|旅券/
          "passport"
        when /driver|driving|licen[cs]e|免許/
          "driving_license"
        when /residence|resident|zairyu|在留/
          "residence_card"
        when /my.?number|個人番号|マイナ/
          "my_number_card"
        else
          raw.present? ? "unknown" : nil
        end
      end

      def safe_webhook_metadata(payload, workflow_type:)
        {
          "provider" => PROVIDER_KEY,
          "workflow_type" => workflow_type,
          "event_id" => payload["event_id"] || payload["eventId"] || payload["id"],
          "event_type" => payload["event_type"] || payload["eventType"] || payload["type"],
          "provider_status" => provider_status_from(payload),
          "sandbox" => payload["sandbox"],
          "test" => payload["test"],
          "stub" => payload["stub"]
        }.compact
      end

      def provider_status_from(payload)
        payload["status"] ||
          payload["verification_status"] ||
          payload["verificationStatus"] ||
          payload.dig("data", "status") ||
          payload.dig("data", "verification_status") ||
          payload.dig("data", "verificationStatus") ||
          payload.dig("result", "status")
      end

      def provider_session_id_from(payload)
        payload["session_id"] ||
          payload["sessionId"] ||
          payload["verification_id"] ||
          payload["verificationId"] ||
          payload.dig("data", "session_id") ||
          payload.dig("data", "sessionId") ||
          payload.dig("data", "verification_id") ||
          payload.dig("data", "verificationId") ||
          payload.dig("result", "session_id") ||
          payload.dig("result", "sessionId")
      end

      private

      def normalize_workflow_type(workflow_type)
        value = workflow_type.to_s.presence || STANDARD_WORKFLOW_TYPE
        if value == MY_NUMBER_WORKFLOW_TYPE
          raise ConfigurationError, "マイナンバーカード本人確認はFeature Flagで無効です。" unless self.class.my_number_enabled?

          return MY_NUMBER_WORKFLOW_TYPE
        end

        STANDARD_WORKFLOW_TYPE
      end

      def create_stub_session!(user:, return_url:, workflow_type:)
        provider_session_id = "qt_stub_#{SecureRandom.hex(10)}"
        session = user.coconique_identity_verification_sessions.create!(
          provider: PROVIDER_KEY,
          provider_session_id: provider_session_id,
          status: :processing,
          url: nil,
          return_url: return_url,
          expires_at: 30.minutes.from_now,
          workflow_type: workflow_type,
          document_type: nil,
          provider_status: "quick_trust_stub_processing",
          metadata: {
            "provider" => PROVIDER_KEY,
            "stub_provider" => true,
            "workflow_type" => workflow_type,
            "vendor_user_id" => user.id.to_s
          }
        )

        session.update!(url: quick_trust_stub_return_url(return_url, session.public_id))
        user.update!(
          identity_verification_status: :processing,
          identity_provider: PROVIDER_KEY,
          identity_workflow_type: workflow_type
        )
        session
      end

      def quick_trust_stub_return_url(return_url, session_public_id)
        uri = URI.parse(return_url.to_s)
        query = Rack::Utils.parse_nested_query(uri.query)
        query["identity_session_id"] = session_public_id
        query["quick_trust_stub"] = "1"
        uri.query = query.to_query
        uri.to_s
      rescue URI::InvalidURIError
        "/app/safety/registration?identity_session_id=#{session_public_id}&quick_trust_stub=1"
      end

      def create_live_session!(user:, return_url:, workflow_type:)
        # Quick Trustの正式API仕様・sandbox仕様・署名仕様が届いたら、ここだけ差し替える。
        # 想定としては、vendor/user id、workflow、return_url をサーバー側から渡して
        # verification_url/session_id を受け取り、下のようにlocal sessionへ保存する。
        raise LiveApiNotImplementedError, "Quick Trust live API adapter is waiting for official API specification. Enable QUICK_TRUST_STUB_MODE for sandbox-like local verification."
      end

      def delete_live_session!(_provider_session_id)
        # Quick Trust側にsession削除APIがある場合、正式仕様に合わせてここへ実装する。
        false
      end
    end
  end
end
