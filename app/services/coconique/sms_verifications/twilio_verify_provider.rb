require "net/http"
require "json"
require "uri"

module Coconique
  module SmsVerifications
    class TwilioVerifyProvider
      class ConfigurationError < StandardError; end
      class ApiError < StandardError; end

      PROVIDER_KEY = "twilio_verify".freeze
      DEFAULT_API_BASE_URL = "https://verify.twilio.com".freeze

      def self.configured?
        ENV["TWILIO_ACCOUNT_SID"].present? &&
          ENV["TWILIO_AUTH_TOKEN"].present? &&
          ENV["TWILIO_VERIFY_SERVICE_SID"].present?
      end

      def self.enabled?
        CoconiquePhoneVerificationAttempt.default_provider == PROVIDER_KEY
      end

      def start_verification(phone_number:)
        raise ConfigurationError, "Twilio Verify is not configured" unless self.class.configured?

        payload = {
          "To" => phone_number,
          "Channel" => ENV.fetch("TWILIO_VERIFY_CHANNEL", "sms"),
          "Locale" => ENV.fetch("TWILIO_VERIFY_LOCALE", "ja")
        }

        custom_friendly_name = ENV["TWILIO_VERIFY_CUSTOM_FRIENDLY_NAME"].to_s.strip
        payload["CustomFriendlyName"] = custom_friendly_name if custom_friendly_name.present?

        request_form(:post, "/v2/Services/#{service_sid}/Verifications", payload)
      end

      def check_verification(attempt:, code:)
        raise ConfigurationError, "Twilio Verify is not configured" unless self.class.configured?

        verification_sid = attempt.metadata["twilio_verification_sid"].to_s.presence
        raise ApiError, "Twilio verification SID is missing" if verification_sid.blank?

        payload = {
          "VerificationSid" => verification_sid,
          "Code" => code.to_s.strip
        }

        response = request_form(:post, "/v2/Services/#{service_sid}/VerificationCheck", payload)
        approved = response["status"].to_s == "approved" || response["valid"] == true

        [approved, response]
      end

      private

      def request_form(method, path, payload)
        uri = URI.join(api_base_url, path)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 20

        request = case method
        when :post
          Net::HTTP::Post.new(uri)
        else
          raise ArgumentError, "unsupported http method: #{method}"
        end

        request.basic_auth(account_sid, auth_token)
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.set_form_data(payload)

        response = http.request(request)
        body = response.body.to_s
        parsed = body.present? ? JSON.parse(body) : {}

        return parsed if response.is_a?(Net::HTTPSuccess)

        raise ApiError, "Twilio Verify API #{method.upcase} #{path} failed with #{response.code}: #{safe_twilio_error(parsed, body)}"
      rescue JSON::ParserError => e
        raise ApiError, "Twilio Verify API returned invalid JSON: #{e.message}"
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise ApiError, "Twilio Verify API request timed out: #{e.message}"
      rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
        raise ApiError, "Twilio Verify API connection failed: #{e.message}"
      end

      def safe_twilio_error(parsed, body)
        message = parsed["message"].presence || body.to_s[0, 500]
        code = parsed["code"].presence
        [code && "code=#{code}", message].compact.join(" ")
      end

      def api_base_url
        ENV.fetch("TWILIO_VERIFY_API_BASE_URL", DEFAULT_API_BASE_URL)
      end

      def account_sid
        ENV.fetch("TWILIO_ACCOUNT_SID")
      end

      def auth_token
        ENV.fetch("TWILIO_AUTH_TOKEN")
      end

      def service_sid
        ENV.fetch("TWILIO_VERIFY_SERVICE_SID")
      end
    end
  end
end
