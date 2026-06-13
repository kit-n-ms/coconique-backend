module Api
  module V1
    module Coconique
      class DashboardController < BaseController
        def show
          upcoming_events = events_without_enryo_scope(CoconiqueEvent.ordered_for_dashboard).limit(12).to_a
          hosted_events = current_user.hosted_coconique_events
            .where(status: [:draft, :recruiting, :confirmed])
            .order(starts_at: :asc, id: :asc)
            .limit(5)
          participation_requests = current_user.coconique_participation_requests.includes(:coconique_event)
          favorite_events = favorite_events_for_current_user
          hosted_pending_requests = pending_requests_for_hosted_events
          chat_notices = unread_chat_notices_json
          today_range = Time.current.all_day

          render_success(
            {
              dashboard: {
                safety_notice: safety_notice_json,
                action_counts: {
                  today_participations: participation_requests
                    .joins(:coconique_event)
                    .where(status: [:pending, :approved])
                    .where(coconique_events: { starts_at: today_range })
                    .count,
                  pending_participations: participation_requests.pending.count,
                  approved_participations: participation_requests.approved.count,
                  host_pending_requests: hosted_pending_requests.count,
                  host_approved_participants: approved_participants_for_hosted_events.count,
                  unread_chat_messages: chat_notices.sum { |notice| notice[:count] },
                  favorites: favorite_events.count,
                  hosted_events: current_user.hosted_coconique_events.count,
                  profile_completion: profile_completion_percent
                },
                host_notices: host_notices_json(hosted_pending_requests),
                chat_notices: chat_notices,
                pickup_events: upcoming_events.map { |event| serialize_event_card(event) },
                recommended_events: upcoming_events.map { |event| serialize_event_card(event) },
                hosted_events: hosted_events.map { |event| serialize_host_event(event) },
                current_rule: current_rule_json(upcoming_events.first),
                safety_features: safety_features_json
              }
            }
          )
        end

        private


        def unread_chat_notices_json
          event_ids = chat_accessible_event_ids_for_current_user
          return [] if event_ids.blank?

          events_by_id = CoconiqueEvent.where(id: event_ids).index_by(&:id)
          read_states_by_event_id = CoconiqueEventChatRead
            .where(user: current_user, coconique_event_id: event_ids)
            .index_by(&:coconique_event_id)

          unread_messages = CoconiqueEventMessage
            .visible
            .where(coconique_event_id: event_ids)
            .where.not(user_id: current_user.id)
            .includes(:user, :coconique_event)
            .order(created_at: :desc, id: :desc)
            .select do |message|
              last_read_at = read_states_by_event_id[message.coconique_event_id]&.last_read_at
              last_read_at.blank? || message.created_at > last_read_at
            end

          unread_messages
            .group_by(&:coconique_event_id)
            .map do |event_id, messages|
              event = events_by_id[event_id]
              latest_message = messages.max_by(&:created_at)
              next if event.blank? || latest_message.blank?

              {
                id: "chat-unread-#{event.public_id}",
                event_id: event.public_id,
                title: event.title,
                count: messages.length,
                body: "『#{event.title.to_s.truncate(24)}』の参加者チャットに未確認メッセージが#{messages.length}件あります。",
                latest_message_body: latest_message.body.to_s.truncate(80),
                latest_message_user_display_name: latest_message.user.user_profile&.display_name || latest_message.user.email.to_s.split("@").first,
                latest_message_at: latest_message.created_at&.iso8601,
                link_path: "/app/rooms/#{event.public_id}"
              }
            end
            .compact
            .sort_by { |notice| notice[:latest_message_at].to_s }
            .reverse
            .first(5)
        end

        def chat_accessible_event_ids_for_current_user
          hosted_event_ids = current_user.hosted_coconique_events.pluck(:id)
          approved_event_ids = current_user.coconique_participation_requests.approved.pluck(:coconique_event_id)

          (hosted_event_ids + approved_event_ids).uniq
        end

        def pending_requests_for_hosted_events
          public_statuses = CoconiqueEvent.statuses.values_at("recruiting", "confirmed")

          CoconiqueParticipationRequest
            .pending
            .joins(:coconique_event)
            .where(coconique_events: { host_id: current_user.id, status: public_statuses })
            .includes(:coconique_event)
            .ordered_recently
        end

        def approved_participants_for_hosted_events
          CoconiqueParticipationRequest
            .approved
            .joins(:coconique_event)
            .where(coconique_events: { host_id: current_user.id })
        end

        def host_notices_json(pending_requests)
          pending_requests
            .group_by(&:coconique_event)
            .first(5)
            .map do |event, requests|
              {
                id: "host-pending-#{event.public_id}",
                event_id: event.public_id,
                title: event.title,
                count: requests.length,
                body: "募集中の『#{event.title.to_s.truncate(24)}』に参加申請がありました。参加承認チェックをしてください。",
                link_path: "/app/host/events/#{event.public_id}/requests"
              }
            end
        end

        def safety_notice_json
          pending_count = current_user.coconique_safety_check_sessions.needs_response.count

          if pending_count.positive?
            return {
              id: "safety-check-pending",
              title: "帰宅確認に回答してください",
              body: "終了後のおでかけ確認が#{pending_count}件あります。無事に終了したか、まだ続いているかを選択してください。",
              link_path: "/app/safety/check",
              visible: true
            }
          end

          {
            id: "safety-onboarding-2026-05",
            title: "安心・安全のためにご確認ください",
            body: "緊急連絡先と帰宅確認の設定をしておくと、予定終了後の確認がしやすくなります。",
            link_path: "/app/safety/check-settings",
            visible: true
          }
        rescue NameError, ActiveRecord::StatementInvalid
          {
            id: "safety-onboarding-2026-05",
            title: "安心・安全のためにご確認ください",
            body: "困ったときのサポートや安全機能、公共の場の使い方など、事前に確認をお願いします。",
            link_path: "/app/safety/help",
            visible: true
          }
        end

        def current_rule_json(event)
          return nil if event.blank?

          {
            event_id: event.public_id,
            category_key: event.category_key,
            title: event.title,
            meeting_time: event.starts_at&.iso8601,
            theme_score: 120
          }
        end

        def safety_features_json
          [
            {
              icon: "shield",
              title: "本人確認を推奨",
              body: "信頼できるつながりのために本人確認をすすめます。"
            },
            {
              icon: "rule",
              title: "ルール・マナーを明記",
              body: "安心して参加できるよう、予定ごとに行動基準を共有します。"
            },
            {
              icon: "block",
              title: "通報・ブロック機能",
              body: "不安を感じた相手とは距離を取れる設計です。"
            },
            {
              icon: "support",
              title: "24時間サポート体制",
              body: "困ったときにすぐ相談できる導線を用意します。"
            }
          ]
        end

        def profile_completion_percent
          profile = current_user.user_profile
          return 0 if profile.blank?

          fields = [
            profile.display_name,
            profile.legal_last_name,
            profile.legal_first_name,
            profile.legal_last_name_kana,
            profile.legal_first_name_kana,
            profile.locale,
            profile.timezone
          ]
          ((fields.count(&:present?).to_f / fields.length) * 100).round
        end
      end
    end
  end
end
