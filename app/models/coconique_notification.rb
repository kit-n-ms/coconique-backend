class CoconiqueNotification < ApplicationRecord
  KINDS = %w[safety_check host_pending chat_unread system].freeze

  belongs_to :user

  before_validation :ensure_public_id, on: :create
  before_validation :ensure_occurred_at

  validates :public_id, presence: true, uniqueness: true
  validates :notification_key, presence: true, uniqueness: { scope: :user_id }
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :title, :body, :link_path, presence: true

  scope :visible, -> { where(deleted_at: nil) }
  scope :unread, -> { visible.where(read_at: nil) }
  scope :recent, -> { order(occurred_at: :desc, created_at: :desc, id: :desc) }

  def self.sync_for_user!(user)
    return [] if user.blank?

    sync_safety_check_notifications_for!(user)
    sync_host_pending_notifications_for!(user)
    sync_chat_unread_notifications_for!(user)

    visible.where(user: user).recent.limit(80).to_a
  rescue NameError, ActiveRecord::StatementInvalid => e
    Rails.logger.warn("[CoconiqueNotification] sync skipped: #{e.class} #{e.message}")
    []
  end

  def self.unread_count_for(user)
    sync_for_user!(user)
    unread.where(user: user).count
  end

  def mark_read!
    update!(read_at: Time.current) if read_at.blank?
  end

  def mark_deleted!
    update!(deleted_at: Time.current)
  end

  def self.create_system_notification!(user:, notification_key:, title:, body:, link_path:, occurred_at: Time.current, metadata: {})
    return nil if user.blank?

    notification = find_or_initialize_by(user: user, notification_key: notification_key)
    notification.assign_attributes(
      kind: "system",
      title: title,
      body: body,
      link_path: link_path,
      metadata: metadata || {},
      occurred_at: occurred_at || Time.current,
      read_at: nil,
      deleted_at: nil
    )
    notification.save!
    notification
  end

  class << self
    private

    def upsert_dashboard_notification!(user:, notification_key:, kind:, title:, body:, link_path:, occurred_at:, metadata: {})
      notification = find_or_initialize_by(user: user, notification_key: notification_key)
      return notification if notification.persisted? && notification.deleted_at.present?

      if notification.new_record?
        notification.kind = kind
        notification.title = title
        notification.body = body
        notification.link_path = link_path
        notification.metadata = metadata || {}
        notification.occurred_at = occurred_at || Time.current
      else
        notification.assign_attributes(
          kind: kind,
          title: title,
          body: body,
          link_path: link_path,
          metadata: (notification.metadata || {}).merge(metadata || {}),
          occurred_at: occurred_at || notification.occurred_at || Time.current
        )
      end

      notification.save!
      notification
    end

    def sync_safety_check_notifications_for!(user)
      sessions = user.coconique_safety_check_sessions.needs_response.includes(:coconique_event).order(due_at: :desc, id: :desc).limit(10).to_a
      return if sessions.blank?

      latest = sessions.first
      upsert_dashboard_notification!(
        user: user,
        notification_key: "safety-check-#{latest.public_id}",
        kind: "safety_check",
        title: "帰宅確認に回答してください",
        body: "終了後のおでかけ確認が#{sessions.length}件あります。無事に終了したか、まだ続いているかを選択してください。",
        link_path: "/app/safety/check",
        occurred_at: latest.due_at || latest.created_at || Time.current,
        metadata: {
          safety_check_session_id: latest.public_id,
          pending_count: sessions.length,
          event_public_id: latest.coconique_event&.public_id,
          event_title: latest.coconique_event&.title
        }
      )
    end

    def sync_host_pending_notifications_for!(user)
      public_statuses = CoconiqueEvent.statuses.values_at("recruiting", "confirmed")
      requests = CoconiqueParticipationRequest
        .pending
        .joins(:coconique_event)
        .where(coconique_events: { host_id: user.id, status: public_statuses })
        .includes(:coconique_event)
        .ordered_recently
        .limit(100)
        .to_a

      requests.group_by(&:coconique_event).first(10).each do |event, rows|
        latest = rows.max_by(&:created_at)
        next if event.blank? || latest.blank?

        upsert_dashboard_notification!(
          user: user,
          notification_key: "host-pending-#{event.public_id}-#{latest.public_id}",
          kind: "host_pending",
          title: "参加申請が届いています",
          body: "募集中の『#{event.title.to_s.truncate(24)}』に参加申請が#{rows.length}件あります。参加承認チェックをしてください。",
          link_path: "/app/host/events/#{event.public_id}/requests",
          occurred_at: latest.created_at || Time.current,
          metadata: {
            event_public_id: event.public_id,
            event_title: event.title,
            pending_count: rows.length,
            latest_request_id: latest.public_id
          }
        )
      end
    end

    def sync_chat_unread_notifications_for!(user)
      event_ids = chat_accessible_event_ids_for(user)
      return if event_ids.blank?

      events_by_id = CoconiqueEvent.where(id: event_ids).index_by(&:id)
      read_states_by_event_id = CoconiqueEventChatRead
        .where(user: user, coconique_event_id: event_ids)
        .index_by(&:coconique_event_id)

      unread_messages = CoconiqueEventMessage
        .visible
        .where(coconique_event_id: event_ids)
        .where.not(user_id: user.id)
        .includes(:user, :coconique_event)
        .order(created_at: :desc, id: :desc)
        .select do |message|
          last_read_at = read_states_by_event_id[message.coconique_event_id]&.last_read_at
          last_read_at.blank? || message.created_at > last_read_at
        end

      unread_messages.group_by(&:coconique_event_id).first(10).each do |event_id, messages|
        event = events_by_id[event_id]
        latest = messages.max_by(&:created_at)
        next if event.blank? || latest.blank?

        display_name = latest.user.user_profile&.display_name || latest.user.email.to_s.split("@").first
        upsert_dashboard_notification!(
          user: user,
          notification_key: "chat-unread-#{event.public_id}-#{latest.public_id}",
          kind: "chat_unread",
          title: "参加者チャットに未確認メッセージがあります",
          body: "『#{event.title.to_s.truncate(24)}』の参加者チャットに未確認メッセージが#{messages.length}件あります。#{display_name}：#{latest.body.to_s.truncate(60)}",
          link_path: "/app/rooms/#{event.public_id}",
          occurred_at: latest.created_at || Time.current,
          metadata: {
            event_public_id: event.public_id,
            event_title: event.title,
            unread_count: messages.length,
            latest_message_id: latest.public_id,
            latest_message_body: latest.body.to_s.truncate(80),
            latest_message_user_display_name: display_name
          }
        )
      end
    end

    def chat_accessible_event_ids_for(user)
      hosted_event_ids = user.hosted_coconique_events.pluck(:id)
      approved_event_ids = user.coconique_participation_requests.approved.pluck(:coconique_event_id)

      (hosted_event_ids + approved_event_ids).uniq
    end
  end

  private

  def ensure_public_id
    self.public_id = "ntf-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def ensure_occurred_at
    self.occurred_at ||= Time.current
  end
end
