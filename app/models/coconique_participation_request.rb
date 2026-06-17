class CoconiqueParticipationRequest < ApplicationRecord
  belongs_to :user
  belongs_to :coconique_event
  belongs_to :reviewed_by, class_name: "User", optional: true
  belongs_to :attendance_recorded_by, class_name: "User", optional: true
  belongs_to :canceled_by, class_name: "User", optional: true
  has_one :coconique_feedback, dependent: :destroy

  enum :status, {
    draft: 0,
    pending: 10,
    approved: 20,
    rejected: 30,
    withdrawn: 40,
    auto_withdrawn: 50,
    canceled: 60
  }

  enum :attendance_status, {
    unconfirmed: 0,
    attended: 10,
    absent: 20
  }, prefix: :attendance

  CURRENT_REQUEST_STATUSES = %w[draft pending approved rejected].freeze
  CANCEL_REASON_CATEGORIES = %w[personal_schedule sick urgent weather_transport event_changed other system host_cancel withdrawal safety].freeze
  NO_POINT_CANCEL_CATEGORIES = %w[weather_transport event_changed host_cancel system safety].freeze

  before_validation :ensure_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :message, length: { maximum: 1000 }
  validates :attendance_note, length: { maximum: 1000 }, allow_blank: true
  validates :cancellation_message, length: { maximum: 1000 }, allow_blank: true
  validates :cancellation_reason_category, inclusion: { in: CANCEL_REASON_CATEGORIES }, allow_blank: true
  validate :one_current_request_per_user_and_event

  scope :current_for_event, -> { where(status: CURRENT_REQUEST_STATUSES) }
  scope :active, -> { where(status: [:pending, :approved]) }
  scope :cancelled_by_participant, -> { where(status: :canceled) }
  scope :for_participant_history, -> { includes(:coconique_event).order(created_at: :desc, id: :desc) }
  scope :ordered_recently, -> { order(created_at: :desc, id: :desc) }

  def current_request_status?
    CURRENT_REQUEST_STATUSES.include?(status)
  end

  def approve!(reviewer:)
    transaction do
      previously_approved = approved?
      ensure_event_has_capacity! unless previously_approved

      update!(
        status: :approved,
        reviewed_by: reviewer,
        reviewed_at: Time.current,
        withdrawn_at: nil
      )

      unless previously_approved
        increment_event_participants!
        confirm_event_if_minimum_reached!
        auto_withdraw_pending_requests_if_event_full!
      end
    end
  end

  def reject!(reviewer:)
    transaction do
      previously_approved = approved?

      update!(
        status: :rejected,
        reviewed_by: reviewer,
        reviewed_at: Time.current,
        withdrawn_at: nil
      )

      decrement_event_participants! if previously_approved
    end
  end

  def withdraw!
    transaction do
      previously_approved = approved?

      update!(
        status: :withdrawn,
        withdrawn_at: Time.current
      )

      decrement_event_participants! if previously_approved
    end
  end


  def cancel_by_participant!(category:, message: nil, actor: user, now: Time.current)
    if pending?
      withdraw!
      notify_host_of_pending_withdrawal!(actor: actor)
      return self
    end

    unless approved?
      errors.add(:base, "参加確定済みの予定だけキャンセルできます。")
      raise ActiveRecord::RecordInvalid, self
    end

    normalized_category = normalize_cancel_category(category)
    timing = cancellation_timing_for(now)
    points = late_cancel_points_for(category: normalized_category, timing: timing)

    transaction do
      update!(
        status: :canceled,
        withdrawn_at: now,
        canceled_at: now,
        canceled_by: actor,
        cancellation_reason_category: normalized_category,
        cancellation_message: message.to_s.strip.presence,
        cancellation_timing: timing,
        late_cancel_points: points,
        cancellation_metadata: (cancellation_metadata || {}).merge("actor" => "participant")
      )

      decrement_event_participants!
      create_participant_cancel_chat_message!
      notify_host_of_participant_cancel!(timing: timing, points: points)
      notify_waiting_users_about_open_slot!
    end

    self
  end

  def auto_withdraw_by_system!(reason:, actor: nil, notify_host: false, user_message: nil, now: Time.current, category: "system")
    return self unless pending? || approved?

    previously_approved = approved?
    normalized_category = normalize_cancel_category(category)
    timing = cancellation_timing_for(now)

    transaction do
      update!(
        status: :auto_withdrawn,
        withdrawn_at: now,
        canceled_at: now,
        canceled_by: actor,
        cancellation_reason_category: normalized_category,
        cancellation_message: user_message.to_s.strip.presence || reason.to_s.strip.presence,
        cancellation_timing: timing,
        late_cancel_points: 0,
        cancellation_metadata: (cancellation_metadata || {}).merge("actor" => "system", "system_reason" => reason.to_s)
      )

      decrement_event_participants! if previously_approved
      create_system_cancel_chat_message!(body: user_message.to_s.strip.presence || reason.to_s.strip.presence) if previously_approved
      notify_host_of_system_cancel!(body: user_message.to_s.strip.presence || reason.to_s.strip.presence) if notify_host || previously_approved
      notify_waiting_users_about_open_slot! if previously_approved
    end

    self
  end

  def cancel_by_host!(reviewer:, reason: nil, user_message: nil, now: Time.current)
    unless approved?
      errors.add(:base, "参加確定済みのメンバーだけキャンセルできます。")
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      update!(
        status: :auto_withdrawn,
        reviewed_by: reviewer,
        reviewed_at: reviewed_at || now,
        withdrawn_at: now,
        canceled_at: now,
        canceled_by: reviewer,
        cancellation_reason_category: "host_cancel",
        cancellation_message: user_message.to_s.strip.presence || reason.to_s.strip.presence,
        cancellation_timing: cancellation_timing_for(now),
        late_cancel_points: 0,
        cancellation_metadata: (cancellation_metadata || {}).merge("actor" => "host", "reason" => reason.to_s.strip.presence)
      )

      decrement_event_participants!
      create_system_cancel_chat_message!(body: "#{display_name_for(user)}さんの参加はキャンセルとなりました。")
      notify_participant_of_host_cancel!(body: user_message.to_s.strip.presence)
      notify_waiting_users_about_open_slot!
    end

    self
  end

  def cancellable_by_participant?
    pending? || approved?
  end

  def cancel_deadline
    candidate = coconique_event.recruitment_ends_at
    default_deadline = coconique_event.starts_at&.-(24.hours)
    [candidate, default_deadline].compact.min
  end

  def record_attendance!(status:, recorder:, note: nil)
    unless approved?
      errors.add(:base, "承認済みの参加者だけ参加実績を記録できます。")
      raise ActiveRecord::RecordInvalid, self
    end

    update!(
      attendance_status: status,
      attendance_recorded_by: recorder,
      attendance_recorded_at: Time.current,
      attendance_note: note
    )
  end

  private

  def normalize_cancel_category(category)
    value = category.to_s.strip
    CANCEL_REASON_CATEGORIES.include?(value) ? value : "other"
  end

  def cancellation_timing_for(now)
    return "after_start" if coconique_event.starts_at.present? && now >= coconique_event.starts_at
    deadline = cancel_deadline
    return "before_deadline" if deadline.blank? || now <= deadline

    "after_deadline"
  end

  def late_cancel_points_for(category:, timing:)
    return 0 if timing == "before_deadline"
    return 0 if NO_POINT_CANCEL_CATEGORIES.include?(category)
    return 2 if timing == "after_start"

    1
  end

  def display_name_for(target_user)
    target_user&.user_profile&.display_name.presence || target_user&.email.to_s.split("@").first || "メンバー"
  end

  def create_participant_cancel_chat_message!
    return unless coconique_event.coconique_event_messages.exists?

    body = "#{display_name_for(user)}さんが参加をキャンセルしました。"
    body += "\n伝言：#{cancellation_message}" if cancellation_message.present?
    coconique_event.coconique_event_messages.create!(user: user, kind: :system, body: body)
  rescue StandardError => e
    Rails.logger.warn("[CoconiqueParticipationRequest] failed to create cancel chat message: #{e.class} #{e.message}")
    nil
  end

  def create_system_cancel_chat_message!(body:)
    return if body.blank?
    system_user = coconique_event.host || user
    coconique_event.coconique_event_messages.create!(user: system_user, kind: :system, body: body)
  rescue StandardError => e
    Rails.logger.warn("[CoconiqueParticipationRequest] failed to create system cancel chat message: #{e.class} #{e.message}")
    nil
  end

  def notify_host_of_pending_withdrawal!(actor: user)
    return if coconique_event.host.blank?

    CoconiqueNotification.create_system_notification!(
      user: coconique_event.host,
      notification_key: "participation-withdrawn-#{public_id}",
      title: "参加申請が取り下げられました",
      body: "『#{coconique_event.title.to_s.truncate(40)}』への参加申請が取り下げられました。",
      link_path: "/app/host/events/#{coconique_event.public_id}",
      occurred_at: withdrawn_at || Time.current,
      metadata: { participation_request_id: public_id, event_public_id: coconique_event.public_id, actor_user_id: actor&.id }
    )
  end

  def notify_host_of_participant_cancel!(timing:, points:)
    return if coconique_event.host.blank?

    body = "『#{coconique_event.title.to_s.truncate(40)}』の参加メンバーが参加キャンセルしました。"
    if coconique_event.current_participants < coconique_event.min_participants
      body += " 参加人数が最少開催人数を下回っています。予定をキャンセルする場合、主催チケットは返還対象です。"
    end

    CoconiqueNotification.create_system_notification!(
      user: coconique_event.host,
      notification_key: "participant-canceled-#{public_id}",
      title: "参加メンバーがキャンセルしました",
      body: body,
      link_path: "/app/host/events/#{coconique_event.public_id}",
      occurred_at: canceled_at || Time.current,
      metadata: { participation_request_id: public_id, event_public_id: coconique_event.public_id, timing: timing, late_cancel_points: points }
    )
  end

  def notify_host_of_system_cancel!(body:)
    return if coconique_event.host.blank?

    CoconiqueNotification.create_system_notification!(
      user: coconique_event.host,
      notification_key: "participant-system-canceled-#{public_id}",
      title: "参加メンバーの参加がキャンセルされました",
      body: body.presence || "安全管理上の理由により、参加メンバーの参加はキャンセルとなりました。",
      link_path: "/app/host/events/#{coconique_event.public_id}",
      occurred_at: canceled_at || Time.current,
      metadata: { participation_request_id: public_id, event_public_id: coconique_event.public_id }
    )
  end

  def notify_participant_of_host_cancel!(body: nil)
    CoconiqueNotification.create_system_notification!(
      user: user,
      notification_key: "host-canceled-participation-#{public_id}",
      title: "参加がキャンセルとなりました",
      body: body.presence || "この予定への参加はキャンセルとなりました。また別の募集をご確認ください。",
      link_path: "/app/participations/#{public_id}",
      occurred_at: canceled_at || Time.current,
      metadata: { participation_request_id: public_id, event_public_id: coconique_event.public_id }
    )
  end

  def notify_waiting_users_about_open_slot!
    return unless coconique_event.recruiting? || coconique_event.confirmed?
    return unless coconique_event.current_participants < coconique_event.capacity

    coconique_event.coconique_event_favorites.includes(:user).find_each do |favorite|
      next if favorite.user_id == user_id || favorite.user_id == coconique_event.host_id
      CoconiqueNotification.create_system_notification!(
        user: favorite.user,
        notification_key: "event-slot-opened-#{coconique_event.public_id}-#{favorite.user_id}",
        title: "募集枠が空きました",
        body: "『#{coconique_event.title.to_s.truncate(40)}』に募集枠が空きました。参加申請できるか確認してみてください。",
        link_path: "/app/events/#{coconique_event.public_id}",
        occurred_at: Time.current,
        metadata: { event_public_id: coconique_event.public_id, event_title: coconique_event.title }
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[CoconiqueParticipationRequest] failed to notify slot open: #{e.class} #{e.message}")
    nil
  end

  def ensure_public_id
    self.public_id = "prq-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def one_current_request_per_user_and_event
    return if user_id.blank? || coconique_event_id.blank?
    return unless current_request_status?

    duplicate_exists = self.class
      .where(user_id: user_id, coconique_event_id: coconique_event_id, status: CURRENT_REQUEST_STATUSES)
      .where.not(id: id)
      .exists?

    errors.add(:base, "この募集にはすでに有効な参加申請があります。") if duplicate_exists
  end

  def ensure_event_has_capacity!
    coconique_event.with_lock do
      if coconique_event.current_participants >= coconique_event.capacity
        errors.add(:base, "定員に達しています。")
        raise ActiveRecord::RecordInvalid, self
      end
    end
  end

  def increment_event_participants!
    coconique_event.with_lock do
      coconique_event.update!(current_participants: coconique_event.current_participants + 1)
    end
  end

  def decrement_event_participants!
    coconique_event.with_lock do
      coconique_event.update!(
        current_participants: [coconique_event.current_participants - 1, 0].max
      )
    end
  end

  def confirm_event_if_minimum_reached!
    coconique_event.with_lock do
      next_count = coconique_event.current_participants
      if coconique_event.recruiting? && next_count >= coconique_event.min_participants
        coconique_event.update!(status: :confirmed)
      end
    end
  end

  def auto_withdraw_pending_requests_if_event_full!
    coconique_event.reload
    return if coconique_event.current_participants < coconique_event.capacity

    coconique_event.coconique_participation_requests.pending.where.not(id: id).find_each do |request|
      request.auto_withdraw_by_system!(
        reason: "event_full",
        actor: reviewed_by,
        notify_host: false,
        user_message: "この募集は満員になったため、今回の参加申請は終了しました。募集枠が空いた場合は通知されます。",
        category: "system"
      )

      CoconiqueEventFavorite.find_or_create_by!(user: request.user, coconique_event: coconique_event)
    end
  rescue StandardError => e
    Rails.logger.warn("[CoconiqueParticipationRequest] failed to auto withdraw pending full event requests: #{e.class} #{e.message}")
  end
end
