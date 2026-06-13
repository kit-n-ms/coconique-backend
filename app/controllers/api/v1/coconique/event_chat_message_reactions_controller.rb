module Api
  module V1
    module Coconique
      class EventChatMessageReactionsController < BaseController
        before_action :set_event
        before_action :set_message
        before_action :require_event_chat_member!

        def create
          reaction = @message.coconique_event_message_reactions.find_or_create_by!(
            user: current_user,
            emoji_key: normalized_emoji_key
          )

          AuditLog.record!(
            user: current_user,
            action: "coconique.event_chat_message_reaction.created",
            request: request,
            target: reaction,
            metadata: { event_public_id: @event.public_id, message_public_id: @message.public_id, emoji_key: reaction.emoji_key }
          )

          render_success({ chat_message: serialize_chat_message(@message.reload) })
        end

        def destroy
          reaction = @message.coconique_event_message_reactions.find_by(
            user: current_user,
            emoji_key: normalized_emoji_key
          )
          reaction&.destroy!

          AuditLog.record!(
            user: current_user,
            action: "coconique.event_chat_message_reaction.deleted",
            request: request,
            target: @message,
            metadata: { event_public_id: @event.public_id, message_public_id: @message.public_id, emoji_key: normalized_emoji_key }
          )

          render_success({ chat_message: serialize_chat_message(@message.reload) })
        end

        private

        def set_event
          @event = find_event!
        end

        def set_message
          @message = @event.coconique_event_messages.visible.find_by!(public_id: params[:message_id])
        rescue ActiveRecord::RecordNotFound
          render_error(
            code: "CHAT_MESSAGE_NOT_FOUND",
            message: "対象のメッセージが見つかりません。",
            status: :not_found
          )
        end

        def normalized_emoji_key
          key = params[:emoji_key].to_s.strip
          return key if CoconiqueEventMessageReaction::EMOJI_KEYS.include?(key)

          raise ActionController::ParameterMissing, :emoji_key
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

        def serialize_chat_user(user)
          profile = user.user_profile

          {
            "id" => user.id.to_s,
            "displayName" => profile&.display_name.presence || user.email.to_s.split("@").first,
            "profilePath" => "/app/members/#{user.id}",
            "avatarUrl" => profile&.avatar_url
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
      end
    end
  end
end
