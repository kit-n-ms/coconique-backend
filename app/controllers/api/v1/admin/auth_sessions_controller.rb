module Api
  module V1
    module Admin
      class AuthSessionsController < BaseController
        def index
          user = User.find(params[:user_id])

          sessions = user.auth_sessions.order(created_at: :desc)

          render_success(
            {
              user: admin_user_json(user),
              auth_sessions: sessions.map { |session| auth_session_json(session) }
            }
          )
        end

        def destroy
          session = AuthSession.find(params[:id])
          session.revoke!

          AuditLog.record!(
            user: current_user,
            action: "admin.auth_session_revoked",
            request: request,
            target: session,
            metadata: {
              target_user_id: session.user_id
            }
          )

          render_success(
            {
              message: "セッションを失効しました。",
              auth_session: auth_session_json(session)
            }
          )
        end

        private

        def auth_session_json(session)
          {
            id: session.id,
            user_id: session.user_id,
            expires_at: session.expires_at,
            revoked_at: session.revoked_at,
            ip_address: session.ip_address,
            user_agent: session.user_agent,
            created_at: session.created_at,
            active: session.revoked_at.nil? && session.expires_at.future?
          }
        end
      end
    end
  end
end
