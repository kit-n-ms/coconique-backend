module Api
  module V1
    module Admin
      class BaseController < ApplicationController
        before_action :require_login!
        before_action :require_admin!

        private

        def require_admin!
          return true if current_user&.admin?

          AuditLog.record!(
            user: current_user,
            action: "admin.access_denied",
            request: request,
            metadata: {
              path: request.path,
              method: request.method
            }
          )

          render_error(
            code: "FORBIDDEN",
            message: "この操作を行う権限がありません。",
            status: :forbidden
          )

          false
        end

        def admin_user_json(user)
          {
            id: user.id,
            email: user.email,
            email_verified: user.email_verified_at.present?,
            status: user.status,
            role: user.role,
            last_login_at: user.last_login_at,
            created_at: user.created_at,
            updated_at: user.updated_at,
            active_coconique_restriction: active_coconique_restriction_json(user)
          }
        end


        def active_coconique_restriction_json(user)
          restriction = user.coconique_user_restrictions.active.order(created_at: :desc).first
          return nil if restriction.blank?

          {
            id: restriction.public_id,
            status: restriction.status,
            reason: restriction.reason,
            starts_at: restriction.starts_at,
            ends_at: restriction.ends_at
          }
        rescue ActiveRecord::StatementInvalid, NameError
          nil
        end

        def pagination_params
          page = params.fetch(:page, 1).to_i
          per_page = params.fetch(:per_page, 20).to_i

          {
            page: [page, 1].max,
            per_page: [[per_page, 1].max, 100].min
          }
        end

        def paginated(scope)
          pagination = pagination_params
          total_count = scope.count

          records = scope
            .offset((pagination[:page] - 1) * pagination[:per_page])
            .limit(pagination[:per_page])

          [
            records,
            {
              page: pagination[:page],
              per_page: pagination[:per_page],
              total_count: total_count
            }
          ]
        end
      end
    end
  end
end
