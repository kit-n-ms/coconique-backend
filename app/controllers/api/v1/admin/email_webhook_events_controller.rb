module Api
  module V1
    module Admin
      class EmailWebhookEventsController < BaseController
        def index
          scope = EmailWebhookEvent.recent

          scope = scope.where(provider: params[:provider]) if params[:provider].present?
          scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
          scope = scope.where(email: normalized_email_param) if params[:email].present?
          scope = scope.where(message_id: params[:message_id]) if params[:message_id].present?
          scope = processed_filter(scope)

          events, pagination = paginated(scope)

          render_success(
            {
              email_webhook_events: events.map { |event| email_webhook_event_json(event) },
              pagination: pagination
            }
          )
        end

        def show
          event = EmailWebhookEvent.find(params[:id])

          render_success(
            {
              email_webhook_event: email_webhook_event_json(event, include_payload: true)
            }
          )
        end

        private

        def processed_filter(scope)
          return scope if params[:processed].blank?

          case params[:processed].to_s
          when "true", "1"
            scope.where.not(processed_at: nil)
          when "false", "0"
            scope.where(processed_at: nil)
          else
            scope
          end
        end

        def normalized_email_param
          params[:email].to_s.strip.downcase
        end

        def email_webhook_event_json(event, include_payload: false)
          data = {
            id: event.id,
            provider: event.provider,
            event_id: event.event_id,
            event_type: event.event_type,
            email: event.email,
            message_id: event.message_id,
            status: event.status,
            reason: event.reason,
            metadata: event.metadata,
            processed_at: event.processed_at,
            processing_error: event.processing_error,
            created_at: event.created_at,
            updated_at: event.updated_at
          }

          data[:payload] = event.payload if include_payload
          data
        end
      end
    end
  end
end
