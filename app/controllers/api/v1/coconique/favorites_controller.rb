module Api
  module V1
    module Coconique
      class FavoritesController < BaseController
        def index
          events = favorite_events_for_current_user

          render_success(
            {
              events: events.map { |event| serialize_event_card(event) }
            }
          )
        end
      end
    end
  end
end
