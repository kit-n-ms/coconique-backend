require "net/http"
require "json"
require "openssl"

module Coconique
  module IdentityVerifications
    class DiditProvider
      class ConfigurationError < StandardError; end
      class ApiError < StandardError; end

      PROVIDER_KEY = "didit".freeze
      STANDARD_WORKFLOW_TYPE = "standard_document".freeze
      MY_NUMBER_WORKFLOW_TYPE = "my_number_front_only".freeze

      def self.configured?
        ENV["DIDIT_API_KEY"].present? && ENV["DIDIT_WORKFLOW_ID_STANDARD"].present?
      end

      def self.my_number_enabled?
        ActiveModel::Type::Boolean.new.cast(ENV.fetch("DIDIT_MY_NUMBER_CARD_ENABLED", "false")) && ENV["DIDIT_WORKFLOW_ID_MY_NUMBER"].present?
      end

      def create_session(user:, return_url:, workflow_type: STANDARD_WORKFLOW_TYPE)
        raise ConfigurationError, "Didit is not configured" unless self.class.configured?
        workflow_type = normalize_workflow_type(workflow_type)
        workflow_id = workflow_id_for(workflow_type)
        vendor_data = vendor_data_for(user)

        payload = {
          workflow_id: workflow_id,
          vendor_data: vendor_data,
          callback: return_url,
          callback_method: "both",
          language: "ja",
          contact_details: {
            email: user.email,
            send_notification_emails: false,
            email_lang: "ja"
          },
          metadata: {
            app_key: "coconique",
            user_id: user.id.to_s,
            workflow_type: workflow_type
          }
        }

        response = request_json(:post, "/v3/session/", payload)
        provider_session_id = session_id_from(response)
        verification_url = verification_url_from(response)

        raise ApiError, "Didit API response did not include a session id" if provider_session_id.blank?
        raise ApiError, "Didit API response did not include a verification URL" if verification_url.blank?

        user.update!(
          identity_verification_status: :processing,
          identity_provider: PROVIDER_KEY,
          identity_workflow_type: workflow_type
        )

        user.coconique_identity_verification_sessions.create!(
          provider: PROVIDER_KEY,
          provider_session_id: provider_session_id,
          status: status_for(provider_status_from(response)),
          url: verification_url,
          return_url: return_url,
          expires_at: parse_time(response["expires_at"] || response["expiresAt"] || response["expiration_date"]),
          workflow_type: workflow_type,
          document_type: nil,
          provider_status: provider_status_from(response),
          metadata: safe_session_metadata(response, workflow_type: workflow_type)
        )
      end

      def retrieve_decision(provider_session_id)
        request_json(:get, "/v3/session/#{provider_session_id}/decision/")
      end

      def delete_session(provider_session_id)
        request(:delete, "/v3/session/#{provider_session_id}/delete/")
        true
      rescue ApiError => e
        Rails.logger.warn("[Didit] delete_session failed: #{e.message}")
        false
      end

      def apply_decision_to_session!(local_session, decision, webhook_metadata: {})
        workflow_type = local_session.workflow_type.presence || decision.dig("metadata", "workflow_type") || STANDARD_WORKFLOW_TYPE
        provider_status = provider_status_from(decision)
        document_type = document_type_for(decision: decision, workflow_type: workflow_type)
        safe_metadata = safe_decision_metadata(decision, workflow_type: workflow_type).merge(webhook_metadata.stringify_keys)

        case status_for(provider_status)
        when :verified
          local_session.mark_verified!(
            provider_session_id: local_session.provider_session_id,
            age_over_18: true,
            document_type: document_type,
            provider_status: provider_status,
            metadata: safe_metadata
          )
          delete_session(local_session.provider_session_id) unless local_session.deleted_at.present?
        when :rejected
          local_session.mark_rejected!(
            reason: "didit_declined",
            provider_status: provider_status,
            document_type: document_type,
            metadata: safe_metadata
          )
          delete_session(local_session.provider_session_id) unless local_session.deleted_at.present?
        when :expired
          local_session.mark_expired!(
            provider_status: provider_status,
            metadata: safe_metadata
          )
          delete_session(local_session.provider_session_id) unless local_session.deleted_at.present?
        when :requires_input
          local_session.mark_requires_input!(
            provider_status: provider_status,
            metadata: safe_metadata
          )
        when :canceled
          local_session.mark_canceled!(
            provider_status: provider_status,
            metadata: safe_metadata
          )
        else
          local_session.mark_processing!(
            provider_status: provider_status,
            metadata: safe_metadata
          )
        end

        local_session.reload
      end

      def workflow_id_for(workflow_type)
        case normalize_workflow_type(workflow_type)
        when STANDARD_WORKFLOW_TYPE
          ENV.fetch("DIDIT_WORKFLOW_ID_STANDARD")
        when MY_NUMBER_WORKFLOW_TYPE
          unless self.class.my_number_enabled?
            raise ConfigurationError, "マイナンバーカード本人確認はFeature Flagで無効です。"
          end

          ENV.fetch("DIDIT_WORKFLOW_ID_MY_NUMBER")
        else
          raise ArgumentError, "unsupported Didit workflow type: #{workflow_type}"
        end
      end

      def normalize_workflow_type(workflow_type)
        value = workflow_type.to_s.presence || STANDARD_WORKFLOW_TYPE
        return MY_NUMBER_WORKFLOW_TYPE if value == MY_NUMBER_WORKFLOW_TYPE

        STANDARD_WORKFLOW_TYPE
      end

      def status_for(provider_status)
        case provider_status.to_s.downcase.tr("_", " ").strip
        when "approved", "verified", "success", "passed", "completed", "complete"
          :verified
        when "declined", "rejected", "failed", "failure", "denied"
          :rejected
        when "expired", "kyc expired", "abandoned", "timeout", "timed out"
          :expired
        when "requires input", "requires input from user", "resubmission required", "retry required"
          :requires_input
        when "canceled", "cancelled"
          :canceled
        when "not started", "created", "initialized"
          :created
        else
          :processing
        end
      end

      def document_type_for(decision:, workflow_type:)
        return "my_number_card" if workflow_type.to_s == MY_NUMBER_WORKFLOW_TYPE

        idv = Array(decision["id_verifications"]).first || Array(decision.dig("decision", "id_verifications")).first || Array(decision.dig("data", "id_verifications")).first || {}
        raw = [
          idv["document_type"],
          idv["documentType"],
          decision["document_type"],
          decision["documentType"],
          decision.dig("document", "type"),
          decision.dig("data", "document_type"),
          decision.dig("data", "documentType")
        ].compact.first.to_s.downcase

        case raw
        when /passport/
          "passport"
        when /driver|driving|licen[cs]e/
          "driving_license"
        when /residence|resident|zairyu/
          "residence_card"
        else
          raw.present? ? "unknown" : nil
        end
      end

      def safe_decision_metadata(decision, workflow_type:)
        {
          "workflow_id" => decision["workflow_id"],
          "workflow_version" => decision["workflow_version"],
          "session_kind" => decision["session_kind"],
          "session_number" => decision["session_number"],
          "provider_status" => provider_status_from(decision),
          "workflow_type" => workflow_type,
          "features" => decision["features"],
          "session_id" => session_id_from(decision),
          "vendor_data" => decision["vendor_data"] || decision["vendorData"]
        }.merge(safe_reentry_reference_metadata(decision)).compact
      end

      def safe_reentry_reference_metadata(payload)
        {
          "didit_vendor_user_id" => first_deep_value(payload, "vendor_user_id", "vendorUserId"),
          "didit_user_id" => first_deep_value(payload, "didit_user_id", "diditUserId", "provider_user_id", "providerUserId"),
          "didit_entity_id" => first_deep_value(payload, "entity_id", "entityId"),
          "didit_person_id" => first_deep_value(payload, "person_id", "personId"),
          "didit_biometric_id" => first_deep_value(payload, "biometric_id", "biometricId"),
          "didit_face_reference_id" => first_deep_value(payload, "face_reference_id", "faceReferenceId", "face_id", "faceId"),
          "didit_document_reference_id" => first_deep_value(payload, "document_reference_id", "documentReferenceId", "document_id", "documentId"),
          "didit_duplicate_check_status" => first_deep_value(payload, "duplicate_check_status", "duplicateCheckStatus"),
          "didit_blocklist_status" => first_deep_value(payload, "blocklist_status", "blocklistStatus")
        }.compact
      end

      def first_deep_value(payload, *keys)
        keys.each do |key|
          found = deep_find_value(payload, key)
          return found if found.to_s.strip.present?
        end
        nil
      end

      def deep_find_value(object, key)
        case object
        when Hash
          return object[key] if object.key?(key)
          object.each_value do |value|
            found = deep_find_value(value, key)
            return found if found.to_s.strip.present?
          end
        when Array
          object.each do |value|
            found = deep_find_value(value, key)
            return found if found.to_s.strip.present?
          end
        end
        nil
      end

      def provider_status_from(payload)
        payload["status"] ||
          payload["verification_status"] ||
          payload["verificationStatus"] ||
          payload.dig("data", "status") ||
          payload.dig("data", "verification_status") ||
          payload.dig("data", "verificationStatus") ||
          payload.dig("decision", "status")
      end

      def session_id_from(payload)
        payload["session_id"] ||
          payload["sessionId"] ||
          payload["verification_session_id"] ||
          payload["verificationSessionId"] ||
          payload["id"] ||
          payload.dig("data", "session_id") ||
          payload.dig("data", "sessionId") ||
          payload.dig("decision", "session_id") ||
          payload.dig("decision", "sessionId")
      end

      def verification_url_from(payload)
        payload["verification_url"] ||
          payload["verificationUrl"] ||
          payload["url"] ||
          payload["session_url"] ||
          payload["sessionUrl"] ||
          payload.dig("data", "verification_url") ||
          payload.dig("data", "verificationUrl") ||
          payload.dig("data", "url")
      end

      private

      def vendor_data_for(user)
        "coconique-user-#{user.id}"
      end

      def safe_session_metadata(response, workflow_type:)
        {
          "workflow_id" => response["workflow_id"],
          "workflow_version" => response["workflow_version"],
          "session_kind" => response["session_kind"],
          "session_number" => response["session_number"],
          "vendor_data" => response["vendor_data"] || response["vendorData"],
          "workflow_type" => workflow_type,
          "session_id" => session_id_from(response),
          "verification_url_present" => verification_url_from(response).present?
        }.compact
      end

      def request_json(method, path, payload = nil)
        response = request(method, path, payload)
        body = response.body.to_s
        body.present? ? JSON.parse(body) : {}
      rescue JSON::ParserError => e
        raise ApiError, "Didit API returned invalid JSON: #{e.message}"
      end

      def request(method, path, payload = nil)
        uri = URI.join(api_base_url, path)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        configure_ssl!(http) if http.use_ssl?
        http.open_timeout = 5
        http.read_timeout = 20

        request = case method
        when :post
          Net::HTTP::Post.new(uri)
        when :get
          Net::HTTP::Get.new(uri)
        when :delete
          Net::HTTP::Delete.new(uri)
        else
          raise ArgumentError, "unsupported http method: #{method}"
        end

        request["x-api-key"] = api_key
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload) if payload.present?

        response = http.request(request)
        return response if response.is_a?(Net::HTTPSuccess)

        raise ApiError, "Didit API #{method.upcase} #{path} failed with #{response.code}: #{response.body.to_s[0, 500]}"
      rescue OpenSSL::SSL::SSLError => e
        raise ApiError, ssl_error_message(e)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise ApiError, "Didit API request timed out: #{e.message}"
      rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
        raise ApiError, "Didit API connection failed: #{e.message}"
      end

      def configure_ssl!(http)
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.cert_store = didit_cert_store
        http.verify_callback = ssl_verify_callback if allow_crl_failure?
      end

      def didit_cert_store
        store = OpenSSL::X509::Store.new
        store.set_default_paths

        ssl_cert_file = ENV["SSL_CERT_FILE"].to_s.strip
        store.add_file(ssl_cert_file) if ssl_cert_file.present? && File.file?(ssl_cert_file)

        ssl_cert_dir = ENV["SSL_CERT_DIR"].to_s.strip
        store.add_path(ssl_cert_dir) if ssl_cert_dir.present? && Dir.exist?(ssl_cert_dir)

        # Some local OpenSSL/Homebrew/macOS combinations enable CRL checks through
        # global configuration. Didit TLS verification should validate the chain and
        # hostname, but must not require the developer machine to have every issuer
        # CRL preloaded. Keep CRL verification flags off unless the host explicitly
        # opts into them.
        store.flags = ssl_verify_flags if store.respond_to?(:flags=)
        store
      end

      def ssl_verify_flags
        flags = 0
        flags |= OpenSSL::X509::V_FLAG_TRUSTED_FIRST if defined?(OpenSSL::X509::V_FLAG_TRUSTED_FIRST)
        flags
      end

      def ssl_verify_callback
        lambda do |preverify_ok, store_context|
          next true if preverify_ok

          error = store_context.error
          if error == OpenSSL::X509::V_ERR_UNABLE_TO_GET_CRL
            Rails.logger.warn("[Didit] allowing local TLS CRL verification failure. Do not enable DIDIT_SSL_ALLOW_CRL_FAILURE in production.")
            true
          else
            false
          end
        end
      end

      def allow_crl_failure?
        return false if Rails.env.production?

        ActiveModel::Type::Boolean.new.cast(ENV.fetch("DIDIT_SSL_ALLOW_CRL_FAILURE", "false"))
      end

      def ssl_error_message(error)
        message = "Didit API TLS verification failed: #{error.message}"
        if error.message.include?("unable to get certificate CRL")
          message += ". Local OpenSSL is requiring a certificate revocation list. Try rerunning with the updated custom cert store; in development only, you may set DIDIT_SSL_ALLOW_CRL_FAILURE=true to allow this specific CRL-check failure while keeping normal certificate verification enabled."
        end
        message
      end

      def api_base_url
        ENV.fetch("DIDIT_API_BASE_URL", "https://verification.didit.me")
      end

      def api_key
        ENV.fetch("DIDIT_API_KEY")
      end

      def parse_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
