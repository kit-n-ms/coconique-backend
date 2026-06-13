module Api
  module V1
    module Admin
      class StripeWebhookEventsController < BaseController
        def index
          scope = StripeWebhookEvent.order(created_at: :desc)

          scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
          scope = scope.where(livemode: boolean_param(params[:livemode])) if params[:livemode].present?
          scope = processed_filter(scope)

          events, pagination = paginated(scope)

          render_success(
            {
              stripe_webhook_events: events.map { |event| stripe_webhook_event_json(event) },
              pagination: pagination
            }
          )
        end

        def show
          event = StripeWebhookEvent.find(params[:id])

          render_success(
            {
              stripe_webhook_event: stripe_webhook_event_json(event, include_payload: true)
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

        def boolean_param(value)
          value.to_s == "true" || value.to_s == "1"
        end

        def stripe_webhook_event_json(event, include_payload: false)
          data = {
            id: event.id,
            stripe_event_id: event.stripe_event_id,
            event_type: event.event_type,
            api_version: event.api_version,
            livemode: event.livemode,
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
