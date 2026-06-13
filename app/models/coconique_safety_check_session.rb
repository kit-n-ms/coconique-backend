class CoconiqueSafetyCheckSession < ApplicationRecord
  DEFAULT_EXTENSION_MINUTES = 60
  MAX_EXTENSIONS = 3

  belongs_to :coconique_event
  belongs_to :coconique_participation_request, optional: true
  belongs_to :user

  has_many :coconique_emergency_contact_notifications, dependent: :destroy

  enum :role, {
    participant: 0,
    host: 10
  }

  enum :status, {
    waiting: 0,
    safe: 10,
    extended: 20,
    help: 30,
    no_response: 40,
    escalated: 50,
    canceled: 60
  }

  enum :response_kind, {
    responded_safe: 10,
    responded_extended: 20,
    responded_help: 30
  }

  before_validation :ensure_public_id, on: :create
  before_validation :ensure_due_defaults

  validates :public_id, presence: true, uniqueness: true
  validates :due_at, :next_reminder_at, presence: true
  validates :reminders_sent_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :extended_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :needs_response, -> { where(status: [:waiting, :extended]) }
  scope :ordered_recently, -> { order(due_at: :desc, id: :desc) }

  def self.create_due_sessions!(now: Time.current)
    CoconiqueEvent
      .where(status: CoconiqueEvent.statuses[:finished])
      .where("ends_at <= ?", now)
      .includes(:host, coconique_participation_requests: :user)
      .find_each do |event|
        create_for_event!(event, now: now)
      end
  end

  def self.create_for_event!(event, now: Time.current)
    # 承認済み参加者がいない予定は、実開催ではなく自動キャンセル/返還対象として扱う。
    # ホストだけに安心帰宅チェックが走ると不自然なため作成しない。
    return unless event.approved_participants?

    create_for_user_and_event!(user: event.host, event: event, role: :host, participation_request: nil, now: now) if event.host.present?

    event.coconique_participation_requests.approved.includes(:user).find_each do |request|
      create_for_user_and_event!(
        user: request.user,
        event: event,
        role: :participant,
        participation_request: request,
        now: now
      )
    end
  end

  def self.create_for_user_and_event!(user:, event:, role:, participation_request:, now: Time.current)
    setting = user.coconique_safety_check_setting || CoconiqueSafetyCheckSetting.default_for(user)
    setting.save! if setting.new_record?

    event_ended_at = event.ends_at || event.finished_at || now
    return unless setting.effective_for_event_end?(event_ended_at)
    return if exists?(coconique_event: event, user: user, role: roles.fetch(role.to_s))

    due_at = event_ended_at + setting.start_delay_minutes.minutes

    create!(
      coconique_event: event,
      coconique_participation_request: participation_request,
      user: user,
      role: role,
      status: :waiting,
      due_at: due_at,
      next_reminder_at: due_at,
      metadata: {
        setting_mode: setting.mode,
        reminder_interval_minutes: setting.reminder_interval_minutes,
        max_reminders: setting.max_reminders,
        notify_contacts_on_no_response: setting.notify_contacts_on_no_response,
        notify_contacts_on_help: setting.notify_contacts_on_help,
        share_event_title: setting.share_event_title,
        share_event_area: setting.share_event_area
      }
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def self.process_due_notifications!(now: Time.current)
    needs_response.where("next_reminder_at <= ?", now).find_each do |session|
      session.process_due_notification!(now: now)
    rescue StandardError => e
      Rails.logger.warn("[CoconiqueSafetyCheckSession] failed to process #{session&.id}: #{e.class} #{e.message}")
      next
    end
  end

  def process_due_notification!(now: Time.current)
    return unless waiting? || extended?
    return if next_reminder_at.blank? || next_reminder_at > now

    unless active_setting_still_allows_notification?
      update!(status: :canceled, next_reminder_at: now)
      return
    end

    if reminders_sent_count < max_reminders
      CoconiqueSafetyMailer.safety_check_reminder(self).deliver_later
      update!(
        reminders_sent_count: reminders_sent_count + 1,
        next_reminder_at: now + reminder_interval_minutes.minutes
      )
      return
    end

    handle_no_response!(now: now)
  end

  def answer_safe!
    update!(
      status: :safe,
      response_kind: :responded_safe,
      answered_at: Time.current,
      next_reminder_at: Time.current
    )
  end

  def answer_extended!(minutes: DEFAULT_EXTENSION_MINUTES)
    normalized_minutes = [[minutes.to_i, 30].max, 24 * 60].min

    if extended_count >= MAX_EXTENSIONS
      errors.add(:base, "延長できる回数を超えています。")
      raise ActiveRecord::RecordInvalid, self
    end

    next_due_at = Time.current + normalized_minutes.minutes

    update!(
      status: :extended,
      response_kind: :responded_extended,
      due_at: next_due_at,
      next_reminder_at: next_due_at,
      reminders_sent_count: 0,
      extended_count: extended_count + 1,
      answered_at: nil
    )
  end

  def answer_help!(note: nil)
    update!(
      status: :help,
      response_kind: :responded_help,
      answered_at: Time.current,
      help_note: note.to_s.strip.presence,
      next_reminder_at: Time.current
    )

    notify_emergency_contacts!(kind: :help) if notify_contacts_on_help?
  end

  def handle_no_response!(now: Time.current)
    update!(status: :no_response, escalated_at: now)
    notify_emergency_contacts!(kind: :no_response) if notify_contacts_on_no_response?
  end

  def notify_emergency_contacts!(kind:)
    contacts = user.coconique_emergency_contacts.approved_active.order(:id)

    contacts.find_each do |contact|
      notification = coconique_emergency_contact_notifications.create!(
        coconique_emergency_contact: contact,
        kind: kind,
        status: :pending,
        metadata: {
          event_public_id: coconique_event.public_id,
          event_starts_at: coconique_event.starts_at&.iso8601,
          event_ends_at: coconique_event.ends_at&.iso8601
        }
      )

      CoconiqueSafetyMailer.emergency_contact_notification(notification).deliver_later
      notification.mark_sent!
    rescue StandardError => e
      notification&.mark_failed!(e.message)
      Rails.logger.warn("[CoconiqueSafetyCheckSession] emergency contact notification failed: #{e.class} #{e.message}")
      next
    end
  end

  def reminder_interval_minutes
    (metadata || {})["reminder_interval_minutes"].presence&.to_i || 30
  end

  def max_reminders
    (metadata || {})["max_reminders"].presence&.to_i || 3
  end

  def notify_contacts_on_no_response?
    (metadata || {})["notify_contacts_on_no_response"] != false
  end

  def notify_contacts_on_help?
    (metadata || {})["notify_contacts_on_help"] == true
  end

  def share_event_title?
    (metadata || {})["share_event_title"] == true
  end

  def share_event_area?
    (metadata || {})["share_event_area"] == true
  end

  def active_setting_still_allows_notification?
    setting = user.coconique_safety_check_setting || CoconiqueSafetyCheckSetting.default_for(user)
    setting.save! if setting.new_record?

    event_ended_at = coconique_event.ends_at || coconique_event.finished_at || created_at
    setting.effective_for_event_end?(event_ended_at)
  end

  def cancel_if_inactive_setting!(now: Time.current)
    return false unless waiting? || extended?
    return false if active_setting_still_allows_notification?

    update!(status: :canceled, next_reminder_at: now)
    true
  end

  private

  def ensure_public_id
    self.public_id = "sfs-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def ensure_due_defaults
    self.due_at ||= Time.current
    self.next_reminder_at ||= due_at
    self.reminders_sent_count ||= 0
    self.extended_count ||= 0
    self.metadata ||= {}
  end
end
