module Api
  module V1
    module Coconique
      class EventFavoritesController < BaseController
        def create
          event = find_event!
          return unless require_publicly_available_event!(event)
          return unless require_not_enryo_event!(event)
          return unless require_favorable_event!(event)

          favorite = current_user.coconique_event_favorites.find_or_initialize_by(coconique_event: event)
          status = favorite.new_record? ? :created : :ok
          favorite.save! if favorite.new_record?

          render_success(
            {
              event: serialize_event_card(event.reload)
            },
            status: status
          )
        end

        def destroy
          event = find_event!

          current_user.coconique_event_favorites.find_by(coconique_event: event)&.destroy!

          render_success(
            {
              event: serialize_event_card(event.reload)
            }
          )
        end

        private

        def require_favorable_event!(event)
          if event.hosted_by?(current_user)
            render_error(
              code: "OWN_EVENT_NOT_FAVORABLE",
              message: "自分が主催する募集は気になるに追加できません。",
              status: :unprocessable_entity
            )

            return false
          end

          true
        end
      end
    end
  end
end
