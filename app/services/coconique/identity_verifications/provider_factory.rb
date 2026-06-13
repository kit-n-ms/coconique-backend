module Coconique
  module IdentityVerifications
    class ProviderFactory
      SUPPORTED_PROVIDER_KEYS = %w[didit quick_trust stripe_identity fake_identity fake].freeze

      def self.current
        new.current
      end

      def self.primary_provider_key
        normalize_provider_key(ENV.fetch("COCONIQUE_IDENTITY_PROVIDER_PRIMARY", "didit"))
      end

      def self.fallback_provider_key
        normalize_provider_key(ENV.fetch("COCONIQUE_IDENTITY_PROVIDER_FALLBACK", "fake_identity"))
      end

      def self.normalize_provider_key(value)
        key = value.to_s.strip.downcase.tr("-", "_")
        return "quick_trust" if key.in?(%w[quicktrust quick_trust quick_trust_ekyc])
        return "stripe_identity" if key.in?(%w[stripe stripe_identity])
        return "fake_identity" if key.in?(%w[fake fake_identity])

        key
      end

      def self.provider_label(provider_key)
        case normalize_provider_key(provider_key)
        when "didit"
          "Didit"
        when "quick_trust"
          "Quick Trust"
        when "stripe_identity"
          "Stripe Identity"
        when "fake_identity"
          "開発用本人確認"
        else
          "本人確認サービス"
        end
      end

      def self.my_number_enabled_for_current_provider?
        case primary_provider_key
        when "didit"
          DiditProvider.my_number_enabled?
        when "quick_trust"
          QuickTrustProvider.my_number_enabled?
        else
          false
        end
      end

      def current
        provider_key = force_fake_provider? ? "fake_identity" : self.class.primary_provider_key
        build_provider(provider_key)
      rescue DiditProvider::ConfigurationError, StripeIdentityProvider::ConfigurationError, QuickTrustProvider::ConfigurationError, QuickTrustProvider::LiveApiNotImplementedError => e
        fallback_key = self.class.fallback_provider_key
        raise e if fallback_key.blank? || fallback_key == provider_key

        Rails.logger.warn("[IdentityProvider] #{provider_key} unavailable: #{e.message}. Falling back to #{fallback_key}.")
        build_provider(fallback_key)
      end

      private

      def build_provider(provider_key)
        case self.class.normalize_provider_key(provider_key)
        when "didit"
          return DiditProvider.new if DiditProvider.configured?
          return FakeProvider.new unless Rails.env.production?

          raise DiditProvider::ConfigurationError, "Didit本人確認が未設定です。DIDIT_API_KEY と DIDIT_WORKFLOW_ID_STANDARD を設定してください。"
        when "quick_trust"
          return QuickTrustProvider.new if QuickTrustProvider.configured?
          return FakeProvider.new unless Rails.env.production?

          raise QuickTrustProvider::ConfigurationError, "Quick Trust本人確認が未設定です。QUICK_TRUST_API_KEY と QUICK_TRUST_API_BASE_URL を設定してください。"
        when "stripe_identity", "stripe"
          return StripeIdentityProvider.new if StripeIdentityProvider.configured?
          return FakeProvider.new unless Rails.env.production?

          raise StripeIdentityProvider::ConfigurationError, "Stripe Identityが未設定です。STRIPE_SECRET_KEY を設定してください。"
        when "fake_identity", "fake"
          FakeProvider.new
        else
          raise ArgumentError, "unsupported identity provider: #{provider_key}"
        end
      end

      def force_fake_provider?
        Rails.env.development? && ActiveModel::Type::Boolean.new.cast(ENV.fetch("COCONIQUE_USE_FAKE_IDENTITY", "false"))
      end
    end
  end
end
