module Api
  module V1
    module Coconique
      class HostedEventsController < BaseController
        def index
          events = current_user.hosted_coconique_events

          if params[:status].present? && CoconiqueEvent.statuses.key?(params[:status])
            events = events.where(status: params[:status])
          end

          if params[:q].present?
            query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s)}%"
            events = events.where(
              "title ILIKE :query OR area ILIKE :query OR summary ILIKE :query",
              query: query
            )
          end

          events = apply_sort(events)

          render_success(
            {
              events: events.map { |event| serialize_host_event(event) }
            }
          )
        end

        private

        def apply_sort(events)
          case params[:sort].to_s
          when "created_asc"
            events.order(created_at: :asc, id: :asc)
          when "starts_desc"
            events.order(starts_at: :desc, id: :desc)
          when "starts_asc"
            events.order(starts_at: :asc, id: :asc)
          else
            events.order(created_at: :desc, id: :desc)
          end
        end
      end
    end
  end
end
