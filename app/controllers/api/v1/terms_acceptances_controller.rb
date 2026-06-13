module Api
  module V1
    class TermsAcceptancesController < ApplicationController
      before_action :require_login!

      def create
        acceptance = current_user.terms_acceptances.create!(
          app_key: params.require(:app_key),
          terms_version: params.require(:terms_version),
          privacy_version: params.require(:privacy_version),
          ip_address: request.remote_ip,
          user_agent: request.user_agent.to_s.truncate(1000)
        )

        AuditLog.record!(
          user: current_user,
          action: "terms_acceptance.created",
          request: request,
          target: acceptance,
          metadata: {
            app_key: acceptance.app_key,
            terms_version: acceptance.terms_version,
            privacy_version: acceptance.privacy_version
          }
        )

        render_success(
          {
            terms_acceptance: terms_acceptance_json(acceptance)
          },
          status: :created
        )
      end

      private

      def terms_acceptance_json(acceptance)
        {
          id: acceptance.id,
          app_key: acceptance.app_key,
          terms_version: acceptance.terms_version,
          privacy_version: acceptance.privacy_version,
          accepted_at: acceptance.accepted_at
        }
      end
    end
  end
end
