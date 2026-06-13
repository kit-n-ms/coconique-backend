module Api
  module V1
    module Admin
      class EmailSuppressionsController < BaseController
        def index
          scope = EmailSuppression.order(created_at: :desc)

          scope = scope.where(email: normalized_email_param) if params[:email].present?
          scope = scope.where(reason: params[:reason]) if params[:reason].present?
          scope = scope.where(source: params[:source]) if params[:source].present?

          suppressions, pagination = paginated(scope)

          render_success(
            {
              email_suppressions: suppressions.map { |suppression| email_suppression_json(suppression) },
              pagination: pagination
            }
          )
        end

        def destroy
          suppression = EmailSuppression.find(params[:id])
          email = suppression.email
          reason = suppression.reason

          suppression.destroy!

          AuditLog.record!(
            user: current_user,
            action: "admin.email_suppression_deleted",
            request: request,
            metadata: {
              email: email,
              reason: reason
            }
          )

          render_success(
            {
              deleted: true,
              email: email
            }
          )
        end

        private

        def normalized_email_param
          params[:email].to_s.strip.downcase
        end

        def email_suppression_json(suppression)
          {
            id: suppression.id,
            email: suppression.email,
            reason: suppression.reason,
            source: suppression.source,
            source_event_id: suppression.source_event_id,
            suppressed_at: suppression.suppressed_at,
            metadata: suppression.metadata,
            created_at: suppression.created_at,
            updated_at: suppression.updated_at
          }
        end
      end
    end
  end
end
