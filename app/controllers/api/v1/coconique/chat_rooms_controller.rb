module Api
  module V1
    module Coconique
      class ChatRoomsController < BaseController
        POSTABLE_DAYS_AFTER_EVENT_END = 30.days

        before_action :set_event, only: [:show]
        before_action :require_event_chat_member!, only: [:show]

        def index
          event_ids = chat_accessible_event_ids_for_current_user
          events = CoconiqueEvent
            .where(id: event_ids)
            .includes(:host)
            .order(starts_at: :desc, id: :desc)

          render_success(
            {
              chat_rooms: events.map { |event| serialize_chat_room_summary(event) }
            }
          )
        end

        def show
          render_success(
            {
              chat_room: serialize_chat_room_summary(@event)
            }
          )
        end

        private

        def set_event
          @event = find_event!
        end

        def chat_accessible_event_ids_for_current_user
          hosted_event_ids = current_user.hosted_coconique_events.pluck(:id)
          approved_event_ids = current_user.coconique_participation_requests.approved.pluck(:coconique_event_id)

          (hosted_event_ids + approved_event_ids).uniq
        end

        def require_event_chat_member!
          return true if event_chat_member?(@event)

          render_error(
            code: "EVENT_CHAT_FORBIDDEN",
            message: "このチャットは、主催者または参加承認済みメンバーだけが利用できます。",
            status: :forbidden
          )

          false
        end

        def event_chat_member?(event)
          return false if current_user.blank?
          return true if current_user.admin? || event.hosted_by?(current_user)

          event.coconique_participation_requests.approved.exists?(user_id: current_user.id)
        end

        def event_chat_viewer_role(event)
          return "admin" if current_user&.admin?
          return "host" if event.hosted_by?(current_user)
          return "participant" if event.coconique_participation_requests.approved.exists?(user_id: current_user.id)

          "unknown"
        end

        def can_post_event_chat?(event)
          return false unless event_chat_member?(event)
          return false if event.canceled?
          return true unless event.finished?

          chat_postable_until(event).present? && Time.current <= chat_postable_until(event)
        end

        def chat_postable_until(event)
          base_time = event.ends_at || event.finished_at
          return nil if base_time.blank?

          base_time + POSTABLE_DAYS_AFTER_EVENT_END
        end

        def chat_read_only_reason(event)
          return nil if can_post_event_chat?(event)
          return "この募集はキャンセルされているため、チャットは閲覧のみです。" if event.canceled?
          return "終了後30日を過ぎたため、このチャットは閲覧のみです。" if event.finished? && chat_postable_until(event).present? && Time.current > chat_postable_until(event)

          nil
        end

        def serialize_chat_room_summary(event)
          latest_message = event.coconique_event_messages.visible.includes(user: :user_profile).order(created_at: :desc, id: :desc).first
          {
            "id" => event.public_id,
            "eventId" => event.public_id,
            "event" => serialize_event_card(event),
            "viewerRole" => event_chat_viewer_role(event),
            "canPost" => can_post_event_chat?(event),
            "postableUntil" => chat_postable_until(event)&.iso8601,
            "readOnlyReason" => chat_read_only_reason(event),
            "unreadCount" => unread_chat_count(event),
            "lastMessage" => latest_message ? serialize_chat_message_preview(latest_message) : nil,
            "messagesPath" => "/api/v1/coconique/chat_rooms/#{event.public_id}/messages",
            "appPath" => "/app/rooms/#{event.public_id}"
          }
        end

        def unread_chat_count(event)
          last_read_at = CoconiqueEventChatRead.find_by(user: current_user, coconique_event: event)&.last_read_at
          scope = event.coconique_event_messages.visible.where.not(user_id: current_user.id)
          scope = scope.where("created_at > ?", last_read_at) if last_read_at.present?
          scope.count
        end

        def serialize_chat_message_preview(message)
          {
            "id" => message.public_id,
            "eventId" => message.coconique_event.public_id,
            "body" => message.body.to_s.truncate(80),
            "kind" => message.kind,
            "imageUrls" => (message.image_urls || []).first(1),
            "createdAt" => message.created_at&.iso8601,
            "isMine" => message.user_id == current_user.id,
            "user" => serialize_chat_user(message.user)
          }
        end

        def serialize_chat_user(user)
          profile = user.user_profile

          {
            "id" => user.id.to_s,
            "displayName" => profile&.display_name.presence || user.email.to_s.split("@").first,
            "profilePath" => "/app/members/#{user.id}",
            "avatarUrl" => profile&.avatar_url
          }
        end
      end
    end
  end
end
