require "net/http"
require "json"

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

        user.update!(
          identity_verification_status: :processing,
          identity_provider: PROVIDER_KEY,
          identity_workflow_type: workflow_type
        )

        user.coconique_identity_verification_sessions.create!(
          provider: PROVIDER_KEY,
          provider_session_id: response.fetch("session_id"),
          status: status_for(response["status"]),
          url: response["url"],
          return_url: return_url,
          expires_at: parse_time(response["expires_at"]),
          workflow_type: workflow_type,
          document_type: nil,
          provider_status: response["status"],
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
        case provider_status.to_s.downcase.tr("_", " ")
        when "approved"
          :verified
        when "declined"
          :rejected
        when "expired", "kyc expired", "abandoned"
          :expired
        when "not started"
          :created
        else
          :processing
        end
      end

      def document_type_for(decision:, workflow_type:)
        return "my_number_card" if workflow_type.to_s == MY_NUMBER_WORKFLOW_TYPE

        idv = Array(decision["id_verifications"]).first || Array(decision.dig("decision", "id_verifications")).first || {}
        raw = idv["document_type"].to_s.downcase

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
          "provider_status" => decision["status"],
          "workflow_type" => workflow_type,
          "features" => decision["features"]
        }.compact
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
          "vendor_data" => response["vendor_data"],
          "workflow_type" => workflow_type
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
