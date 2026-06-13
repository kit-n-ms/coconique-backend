module Api
  module V1
    module Admin
      class AuditLogsController < BaseController
        def index
          scope = AuditLog.order(created_at: :desc)

          if params[:user_id].present?
            scope = scope.where(user_id: params[:user_id])
          end

          if params[:action].present?
            scope = scope.where(action: params[:action])
          end

          if params[:target_type].present?
            scope = scope.where(target_type: params[:target_type])
          end

          logs, pagination = paginated(scope)

          render_success(
            {
              audit_logs: logs.map { |log| audit_log_json(log) },
              pagination: pagination
            }
          )
        end

        private

        def audit_log_json(log)
          {
            id: log.id,
            user_id: log.user_id,
            action: log.action,
            target_type: log.target_type,
            target_id: log.target_id,
            metadata: log.metadata,
            ip_address: log.ip_address,
            user_agent: log.user_agent,
            created_at: log.created_at
          }
        end
      end
    end
  end
end
