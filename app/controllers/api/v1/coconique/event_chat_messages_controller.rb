module Api
  module V1
    module Coconique
      class EventChatMessagesController < BaseController
        POSTABLE_DAYS_AFTER_EVENT_END = 30.days

        before_action :set_event
        before_action :require_event_chat_member!

        def index
          limit = params.fetch(:limit, 100).to_i.clamp(1, 200)
          messages = @event.coconique_event_messages
            .visible
            .includes(:coconique_event_message_reactions, user: :user_profile)
            .ordered_chronologically
            .last(limit)

          mark_chat_as_read!(messages.last)

          render_success(
            {
              event: serialize_event(@event, visibility: :auto),
              chat_messages: messages.map { |message| serialize_chat_message(message) },
              viewer_role: event_chat_viewer_role(@event),
              can_post: can_post_event_chat?(@event),
              postable_until: chat_postable_until(@event)&.iso8601,
              read_only_reason: chat_read_only_reason(@event)
            }
          )
        end

        def create
          kind = normalized_kind
          return unless require_event_chat_postable!(@event)

          if kind == :lost_item
            return unless require_lost_item_postable!(@event)
          end

          message = @event.coconique_event_messages.create!(
            user: current_user,
            body: normalized_body,
            kind: kind,
            image_urls: normalized_image_urls
          )

          AuditLog.record!(
            user: current_user,
            action: message.lost_item? ? "coconique.event_chat_message.lost_item.created" : "coconique.event_chat_message.created",
            request: request,
            target: message,
            metadata: { event_public_id: @event.public_id, image_count: message.image_count }
          )

          CoconiqueEventChatRead.mark_read!(event: @event, user: current_user, message: message)

          render_success(
            {
              chat_message: serialize_chat_message(message),
              event: serialize_event(@event, visibility: :auto),
              can_post: can_post_event_chat?(@event),
              postable_until: chat_postable_until(@event)&.iso8601,
              read_only_reason: chat_read_only_reason(@event)
            },
            status: :created
          )
        end

        private

        def set_event
          @event = find_event!
        end

        def normalized_body
          body = params[:body].to_s.strip
          return body if body.present?

          raise ActionController::ParameterMissing, :body
        end

        def normalized_kind
          params[:kind].to_s == "lost_item" ? :lost_item : :message
        end

        def normalized_image_urls
          Array(params[:image_urls] || params[:imageUrls]).map(&:to_s).map(&:strip).reject(&:blank?).first(3)
        end

        def mark_chat_as_read!(latest_visible_message)
          return if latest_visible_message.blank?

          CoconiqueEventChatRead.mark_read!(
            event: @event,
            user: current_user,
            message: latest_visible_message
          )
        rescue StandardError => e
          Rails.logger.warn("[CoconiqueEventChatRead] failed to mark read: #{e.class} #{e.message}")
          nil
        end

        def require_event_chat_member!
          return false unless require_coconique_safety_registration!(action_kind: "open_chat", event: @event)
          return true if event_chat_member?(@event)

          render_error(
            code: "EVENT_CHAT_FORBIDDEN",
            message: "このチャットは、主催者または参加承認済みメンバーだけが利用できます。",
            status: :forbidden
          )

          false
        end

        def require_event_chat_postable!(event)
          return true if can_post_event_chat?(event)

          render_error(
            code: "EVENT_CHAT_NOT_POSTABLE",
            message: chat_not_postable_message(event),
            status: :unprocessable_entity
          )

          false
        end

        def event_chat_member?(event)
          return false if current_user.blank?
          return true if current_user.admin? || event.hosted_by?(current_user)

          event.coconique_participation_requests.approved.exists?(user_id: current_user.id)
        end

        def can_post_event_chat?(event)
          return false unless event_chat_member?(event)
          return false if event.canceled?
          return true unless event.finished?

          chat_postable_until(event).present? && Time.current <= chat_postable_until(event)
        end

        def require_lost_item_postable!(event)
          return true if event_ended?(event)

          render_error(
            code: "LOST_ITEM_NOT_POSTABLE",
            message: "忘れ物問い合わせは、予定終了後に投稿できます。",
            status: :unprocessable_entity
          )

          false
        end

        def event_ended?(event)
          event.finished? || (event.ends_at.present? && event.ends_at <= Time.current)
        end

        def chat_postable_until(event)
          base_time = event.ends_at || event.finished_at
          return nil if base_time.blank?

          base_time + POSTABLE_DAYS_AFTER_EVENT_END
        end

        def chat_read_only_reason(event)
          return nil if can_post_event_chat?(event)
          return "この募集はキャンセルされているため、チャットは閲覧のみです。" if event.canceled?
          if event.finished?
            return "終了後30日を過ぎたため、このチャットは閲覧のみです。" if chat_postable_until(event).present? && Time.current > chat_postable_until(event)
            return nil
          end

          "このチャットには現在投稿できません。"
        end

        def chat_not_postable_message(event)
          chat_read_only_reason(event).presence || "このチャットへ投稿できません。"
        end

        def event_chat_viewer_role(event)
          return "admin" if current_user&.admin?
          return "host" if event.hosted_by?(current_user)
          return "participant" if event.coconique_participation_requests.approved.exists?(user_id: current_user.id)

          "unknown"
        end

        def serialize_chat_message(message)
          {
            "id" => message.public_id,
            "eventId" => message.coconique_event.public_id,
            "body" => message.body,
            "kind" => message.kind,
            "imageUrls" => message.image_urls || [],
            "createdAt" => message.created_at&.iso8601,
            "editedAt" => message.edited_at&.iso8601,
            "isMine" => message.user_id == current_user.id,
            "user" => serialize_chat_user(message.user),
            "reactions" => serialize_reactions(message)
          }
        end


        def serialize_reactions(message)
          grouped = message.coconique_event_message_reactions.group_by(&:emoji_key)

          CoconiqueEventMessageReaction::EMOJI_KEYS.filter_map do |emoji_key|
            reactions = grouped[emoji_key] || []
            next if reactions.empty?

            {
              "emojiKey" => emoji_key,
              "label" => reaction_label(emoji_key),
              "emoji" => reaction_emoji(emoji_key),
              "count" => reactions.size,
              "reactedByMe" => reactions.any? { |reaction| reaction.user_id == current_user.id }
            }
          end
        end

        def reaction_label(emoji_key)
          {
            "thanks" => "ありがとう",
            "like" => "いいね",
            "ok" => "OK",
            "smile" => "にこ",
            "laugh" => "うれしい",
            "shocked" => "びっくり",
            "clap" => "拍手",
            "hooray" => "やった",
            "check" => "確認しました",
            "heart" => "助かります",
            "exclamation" => "重要",
            "question" => "確認したい"
          }.fetch(emoji_key, emoji_key)
        end

        def reaction_emoji(emoji_key)
          {
            "thanks" => "🙏",
            "like" => "👍",
            "ok" => "👌",
            "smile" => "☺️",
            "laugh" => "😆",
            "shocked" => "🙀",
            "clap" => "👏",
            "hooray" => "🙌",
            "check" => "✅",
            "heart" => "💛",
            "exclamation" => "‼️",
            "question" => "⁉️"
          }.fetch(emoji_key, "✨")
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
