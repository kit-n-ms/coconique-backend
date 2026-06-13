module Coconique
  module IdentityVerifications
    class StripeIdentityProvider
      class ConfigurationError < StandardError; end

      PROVIDER_KEY = "stripe_identity".freeze

      def self.configured?
        defined?(Stripe::Identity::VerificationSession) && Stripe.api_key.present?
      end

      def create_session(user:, return_url:, workflow_type: "standard_document")
        raise ConfigurationError, "Stripe Identity is not configured" unless self.class.configured?

        provider_session = Stripe::Identity::VerificationSession.create(
          type: "document",
          metadata: {
            user_id: user.id,
            app_key: "coconique",
            workflow_type: workflow_type
          },
          return_url: return_url
        )

        user.update!(
          identity_verification_status: :processing,
          identity_provider: PROVIDER_KEY,
          identity_workflow_type: workflow_type
        )

        user.coconique_identity_verification_sessions.create!(
          provider: PROVIDER_KEY,
          provider_session_id: provider_session.id,
          status: :processing,
          url: provider_session.url,
          return_url: return_url,
          expires_at: provider_session.expires_at.present? ? Time.at(provider_session.expires_at) : nil,
          workflow_type: workflow_type,
          provider_status: provider_session.status,
          metadata: {
            "livemode" => provider_session.livemode,
            "workflow_type" => workflow_type
          }.compact
        )
      end
    end
  end
end
