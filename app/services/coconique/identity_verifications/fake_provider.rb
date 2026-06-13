module Coconique
  module IdentityVerifications
    class FakeProvider
      PROVIDER_KEY = "fake_identity".freeze

      def self.configured?
        true
      end

      def create_session(user:, return_url:, workflow_type: "standard_document")
        provider_session_id = "fake_#{SecureRandom.hex(10)}"
        public_id = nil

        result = ProviderResult.new(
          provider: PROVIDER_KEY,
          provider_session_id: provider_session_id,
          status: :processing,
          url: nil,
          return_url: return_url,
          expires_at: 30.minutes.from_now,
          workflow_type: workflow_type,
          document_type: nil,
          provider_status: "fake_processing",
          metadata: { "fake_provider" => true }
        )

        session = user.coconique_identity_verification_sessions.create!(
          provider: result.provider,
          provider_session_id: result.provider_session_id,
          status: result.status,
          url: result.url,
          return_url: result.return_url,
          expires_at: result.expires_at,
          workflow_type: result.workflow_type,
          document_type: result.document_type,
          provider_status: result.provider_status,
          metadata: result.metadata
        )
        public_id = session.public_id
        session.update!(url: fake_identity_return_url(return_url, public_id))
        user.update!(
          identity_verification_status: :processing,
          identity_provider: PROVIDER_KEY,
          identity_workflow_type: workflow_type
        )
        session
      end

      private

      def fake_identity_return_url(return_url, session_public_id)
        uri = URI.parse(return_url.to_s)
        query = Rack::Utils.parse_nested_query(uri.query)
        query["identity_session_id"] = session_public_id
        query["fake_identity"] = "1"
        uri.query = query.to_query
        uri.to_s
      rescue URI::InvalidURIError
        "/app/safety/registration?identity_session_id=#{session_public_id}&fake_identity=1"
      end
    end
  end
end
