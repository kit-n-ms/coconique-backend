class CoconiqueEvent < ApplicationRecord
  CATEGORY_KEYS = %w[culture walk watching cafe seasonal].freeze

  belongs_to :host, class_name: "User", optional: true
  belongs_to :host_ticket_lot, class_name: "CoconiqueHostTicketLot", optional: true

  has_many :coconique_event_favorites, dependent: :destroy
  has_many :favorited_users,
    through: :coconique_event_favorites,
    source: :user

  has_many :coconique_participation_requests, dependent: :destroy
  has_many :coconique_event_status_logs, dependent: :destroy
  has_many :coconique_event_messages, dependent: :destroy
  has_many :coconique_feedbacks, dependent: :destroy
  has_many :coconique_event_chat_reads, dependent: :destroy
  has_many :participants,
    through: :coconique_participation_requests,
    source: :user

  enum :status, {
    draft: 0,
    reviewing: 10,
    recruiting: 20,
    closed: 30,
    confirmed: 40,
    finished: 50,
    canceled: 60
  }

  enum :host_ticket_reservation_status, {
    unreserved: 0,
    reserved: 10,
    consumed: 20,
    released: 30,
    forfeited: 40
  }, prefix: :host_ticket

  before_validation :ensure_public_id, on: :create
  before_validation :normalize_target_members
  before_validation :normalize_member_visibility_flags
  before_validation :normalize_area_region
  before_validation :normalize_image_urls

  validates :public_id, presence: true, uniqueness: true
  validates :title, presence: true, length: { maximum: 120 }
  validates :category_key, presence: true, inclusion: { in: CATEGORY_KEYS }
  validates :area, presence: true, length: { maximum: 120 }
  validates :venue_name, length: { maximum: 120 }, allow_blank: true
  validates :area_prefecture, length: { maximum: 20 }, allow_blank: true
  validates :area_city, length: { maximum: 40 }, allow_blank: true
  validates :starts_at, :ends_at, presence: true
  validates :meeting_place, presence: true, length: { maximum: 180 }
  validates :reference_url, length: { maximum: 500 }, allow_blank: true
  validates :cancellation_reason, length: { maximum: 1000 }, allow_blank: true
  validate :image_urls_limit
  validates :capacity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 30 }
  validates :min_participants, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 30 }
  validates :current_participants, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :interested_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :ends_at_after_starts_at
  validate :recruitment_ends_at_before_starts_at
  validate :min_participants_within_capacity

  scope :upcoming, -> { where("starts_at >= ?", Time.current).order(:starts_at, :id) }
  scope :visible_to_members, -> { where(status: [:recruiting, :confirmed]) }
  scope :accepting_applications, -> { where("recruitment_ends_at IS NULL OR recruitment_ends_at > ?", Time.current) }
  scope :with_available_slots, -> { where("current_participants < capacity") }
  scope :ordered_for_dashboard, -> { visible_to_members.accepting_applications.with_available_slots.where("ends_at > ?", Time.current).order(:starts_at, :id) }
  scope :hosted_ordered, -> { order(starts_at: :asc, id: :asc) }

  scope :finish_due, ->(now = Time.current) {
    where(status: [:recruiting, :confirmed, :closed])
      .where("ends_at <= ?", now)
      .order(:ends_at, :id)
  }

  scope :recruitment_expired_without_approved_participants, ->(now = Time.current) {
    where(status: [:recruiting, :closed])
      .where("recruitment_ends_at IS NOT NULL AND recruitment_ends_at <= ?", now)
      .order(:recruitment_ends_at, :id)
  }

  def self.cancel_recruitment_expired_without_approved_participants!(now: Time.current)
    recruitment_expired_without_approved_participants(now).find_each do |event|
      event.with_lock do
        event.reload
        next unless event.recruiting? || event.closed?
        next if event.approved_participants?
        next if event.recruitment_ends_at.blank? || event.recruitment_ends_at > now

        previous_status = event.status
        event.cancel!(
          reason: "承認済み参加者がいないまま募集期限を過ぎたため、自動キャンセルにしました。",
          host_ticket_policy: :release,
          cancellation_notice_kind: :auto_without_approved
        )
        event.coconique_event_status_logs.create!(
          user: nil,
          action: "coconique.event.auto_canceled_without_approved_participants",
          from_status: previous_status,
          to_status: event.status,
          reason: event.cancellation_reason
        )
      end
    rescue StandardError => e
      Rails.logger.warn("[CoconiqueEvent] failed to auto cancel expired event #{event&.id}: #{e.class} #{e.message}")
      next
    end
  end

  def self.finish_due_events!(now: Time.current)
    # 募集期限切れだけでは、通常のAPIアクセス時にイベントを即キャンセルしない。
    # ただし終了予定時刻を過ぎた募集については、承認済み参加者がいなければ
    # 自動キャンセル＋主催チケット返還とし、安心帰宅チェックも作成しない。
    # これにより「誰も承認されず終了した募集」でチケットだけ減る状態を避ける。
    finish_due(now).find_each do |event|
      event.with_lock do
        event.reload
        next unless event.recruiting? || event.confirmed? || event.closed?
        next if event.ends_at.blank? || event.ends_at > now

        previous_status = event.status
        event.finish!
        auto_canceled = event.canceled? && !event.approved_participants?
        event.coconique_event_status_logs.create!(
          user: nil,
          action: auto_canceled ? "coconique.event.auto_canceled_without_approved_participants" : "coconique.event.auto_finished",
          from_status: previous_status,
          to_status: event.status,
          reason: auto_canceled ? event.cancellation_reason : "終了予定時刻を過ぎたため自動的に終了済みにしました。"
        )
      end
    rescue StandardError => e
      Rails.logger.warn("[CoconiqueEvent] failed to auto finish event #{event&.id}: #{e.class} #{e.message}")
      next
    end
  end


  def self.cancel_open_events_for_restricted_user!(user, reason:)
    return 0 if user.blank?

    count = 0
    where(host_id: user.id, status: [:recruiting, :confirmed, :closed]).find_each do |event|
      event.with_lock do
        event.reload
        next unless event.recruiting? || event.confirmed? || event.closed?

        previous_status = event.status
        event.cancel!(reason: reason, cancellation_notice_kind: :account_restriction)
        event.coconique_event_status_logs.create!(
          user: nil,
          action: "coconique.event.canceled_by_user_restriction",
          from_status: previous_status,
          to_status: event.status,
          reason: reason
        )
        count += 1
      end
    rescue StandardError => e
      Rails.logger.warn("[CoconiqueEvent] failed to cancel restricted user's event #{event&.id}: #{e.class} #{e.message}")
      next
    end

    count
  end

  def favorited_by?(user)
    return false if user.blank? || new_record?

    coconique_event_favorites.exists?(user_id: user.id)
  end

  def participation_request_for(user)
    return nil if user.blank? || new_record?

    # 取り下げ後の再申請では、古い withdrawn 履歴と新しい pending 申請が併存する。
    # 募集詳細のボタン制御や集合場所の表示判定では、現在効いている申請を優先する。
    coconique_participation_requests
      .where(user_id: user.id, status: CoconiqueParticipationRequest::CURRENT_REQUEST_STATUSES)
      .order(created_at: :desc, id: :desc)
      .first ||
      coconique_participation_requests
        .where(user_id: user.id)
        .order(created_at: :desc, id: :desc)
        .first
  end

  def hosted_by?(user)
    return false if user.blank?

    host_id == user.id
  end

  def visible_to?(user)
    (visible_to_members_status? && recruitment_open?) || hosted_by?(user) || user&.admin?
  end

  def visible_to_members_status?
    recruiting? || confirmed?
  end

  def recruitment_open?
    recruitment_ends_at.blank? || recruitment_ends_at > Time.current
  end

  def approved_participants?
    coconique_participation_requests.approved.exists?
  end

  def publish!
    update!(
      status: :recruiting,
      published_at: published_at || Time.current,
      closed_at: nil,
      canceled_at: nil,
      finished_at: nil,
      cancellation_reason: nil
    )
  end

  def close!
    update!(
      status: :closed,
      closed_at: Time.current
    )
  end

  def reopen!
    update!(
      status: :recruiting,
      published_at: published_at || Time.current,
      closed_at: nil
    )
  end

  def cancel!(reason: nil, host_ticket_policy: :forfeit, cancellation_notice_kind: :generic)
    transaction do
      update!(
        status: :canceled,
        canceled_at: Time.current,
        cancellation_reason: reason.presence || cancellation_reason
      )

      clear_favorites!

      case host_ticket_policy.to_sym
      when :release
        CoconiqueBilling.release_reserved_host_ticket_for_event!(event: self, reason: reason.presence || "自動返還")
      when :forfeit
        CoconiqueBilling.forfeit_reserved_host_ticket_for_event!(event: self, reason: reason.presence || "主催者都合キャンセル")
      when :keep
        # 管理画面などで別途判断する場合に使用する。
      end

      notify_canceled_to_applicants_and_participants!(kind: cancellation_notice_kind)
    end
  end

  def finish!
    transaction do
      clear_favorites!

      if approved_participants?
        update!(
          status: :finished,
          finished_at: Time.current
        )
        CoconiqueBilling.consume_reserved_host_ticket_for_event!(event: self)
      else
        update!(
          status: :canceled,
          canceled_at: Time.current,
          cancellation_reason: "承認済み参加者がいないまま終了したため、自動キャンセルにしました。"
        )
        CoconiqueBilling.release_reserved_host_ticket_for_event!(event: self, reason: "承認済み参加者がいないまま終了したため自動返還")
        notify_auto_canceled_without_approved_participants!
        notify_canceled_to_applicants_and_participants!(kind: :auto_without_approved)
      end
    end
  end

  private


  def notify_auto_canceled_without_approved_participants!
    return if host.blank?

    CoconiqueNotification.create_system_notification!(
      user: host,
      notification_key: "event-auto-canceled-without-approved-#{public_id}",
      title: "募集が自動キャンセルされました",
      body: "『#{title.to_s.truncate(40)}』は承認済み参加者なしで自動キャンセルとなり、チケットが返還されました。",
      link_path: "/app/host/events/#{public_id}",
      occurred_at: canceled_at || Time.current,
      metadata: {
        event_public_id: public_id,
        event_title: title,
        host_ticket_returned: true,
        auto_canceled_without_approved_participants: true
      }
    )
  rescue StandardError => e
    Rails.logger.warn("[CoconiqueEvent] failed to notify auto cancellation for #{id}: #{e.class} #{e.message}")
    nil
  end

  def notify_canceled_to_applicants_and_participants!(kind: :generic)
    recipients = coconique_participation_requests
      .where(status: [:pending, :approved])
      .includes(:user)
      .map(&:user)
      .compact
      .uniq
      .reject { |recipient| recipient.id == host_id }

    return if recipients.blank?

    body = cancellation_notice_body(kind)
    recipients.each do |recipient|
      CoconiqueNotification.create_system_notification!(
        user: recipient,
        notification_key: "event-canceled-#{public_id}-#{kind}-#{recipient.id}",
        title: "予定がキャンセルされました",
        body: body,
        link_path: "/app/events/#{public_id}",
        occurred_at: canceled_at || Time.current,
        metadata: {
          event_public_id: public_id,
          event_title: title,
          cancellation_kind: kind.to_s,
          host_id: host_id
        }
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[CoconiqueEvent] failed to notify event cancellation to participants for #{id}: #{e.class} #{e.message}")
    nil
  end

  def cancellation_notice_body(kind)
    prefix = "#{event_date_label}の#{title.to_s.truncate(40)}"
    case kind.to_sym
    when :host_withdrawal
      "#{prefix}は主催ユーザーの退会によりキャンセルとなりました。"
    when :host_cancel
      "#{prefix}は主催ユーザーの判断によりキャンセルとなりました。"
    else
      "#{prefix}はキャンセルとなりました。"
    end
  end

  def event_date_label
    target = starts_at || canceled_at || Time.current
    target.in_time_zone("Asia/Tokyo").strftime("%-m月%-d日")
  end

  def clear_favorites!
    coconique_event_favorites.destroy_all
  end

  def ensure_public_id
    self.public_id = "evt-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def normalize_target_members
    self.target_members = Array(target_members).map(&:to_s).reject(&:blank?)
  end

  def normalize_area_region
    self.area_prefecture = area_prefecture.to_s.strip.presence
    self.area_city = area_city.to_s.strip.presence

    if area_prefecture.present?
      self.area = [area_prefecture, area_city].compact_blank.join(" ")
    else
      self.area = area.to_s.strip.presence
    end
  end

  def normalize_member_visibility_flags
    self.same_gender_only = ActiveModel::Type::Boolean.new.cast(same_gender_only)
    self.same_generation_only = ActiveModel::Type::Boolean.new.cast(same_generation_only)
  end

  def normalize_image_urls
    self.image_urls = Array(image_urls).map(&:to_s).reject(&:blank?).first(5)
    self.image_url = image_urls.first if image_url.blank? && image_urls.present?
  end

  def image_urls_limit
    return if image_urls.blank? || image_urls.length <= 5

    errors.add(:image_urls, "must be 5 or fewer")
  end

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, "must be after starts_at")
  end

  def recruitment_ends_at_before_starts_at
    return if recruitment_ends_at.blank? || starts_at.blank?
    return if recruitment_ends_at < starts_at

    errors.add(:recruitment_ends_at, "must be before starts_at")
  end

  def min_participants_within_capacity
    return if min_participants.blank? || capacity.blank?
    return if min_participants <= capacity

    errors.add(:min_participants, "must be less than or equal to capacity")
  end
end
