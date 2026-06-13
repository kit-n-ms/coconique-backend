class CoconiqueSafetyCheckSetting < ApplicationRecord
  belongs_to :user

  enum :mode, {
    off: 0,
    standard: 10,
    careful: 20,
    custom: 30
  }

  before_validation :apply_mode_defaults
  before_save :sync_activation_window
  after_commit :cancel_pending_sessions_when_disabled, on: [:create, :update]

  validates :start_delay_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 5, less_than_or_equal_to: 24 * 60 }
  validates :reminder_interval_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 5, less_than_or_equal_to: 24 * 60 }
  validates :max_reminders, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 10 }

  def self.default_for(user)
    find_or_initialize_by(user: user) do |setting|
      setting.enabled = true
      setting.mode = :standard
      setting.start_delay_minutes = 60
      setting.reminder_interval_minutes = 30
      setting.max_reminders = 3
      setting.notify_contacts_on_no_response = true
      setting.notify_contacts_on_help = false
      setting.share_event_title = false
      setting.share_event_area = false
      setting.enabled_since = Time.current
    end
  end

  def effective_enabled?
    enabled? && !off?
  end

  # 「オンにしている間に終了した予定」だけを帰宅確認対象にするための判定。
  # 帰宅確認機能の導入前・オフ期間中に終了した過去イベントへ、あとから通知が飛ぶことを防ぐ。
  def effective_for_event_end?(ended_at)
    return false unless effective_enabled?
    return false if ended_at.blank?

    activation_started_at = enabled_since || created_at
    return false if activation_started_at.blank?

    ended_at >= activation_started_at
  end

  private

  def apply_mode_defaults
    self.enabled = false if off?

    case mode
    when "standard", nil
      self.mode ||= :standard
      self.enabled = true if enabled.nil?
      self.start_delay_minutes = 60 if start_delay_minutes.blank?
      self.reminder_interval_minutes = 30 if reminder_interval_minutes.blank?
      self.max_reminders = 3 if max_reminders.blank?
    when "careful"
      self.enabled = true if enabled.nil?
      self.start_delay_minutes = 30 if start_delay_minutes.blank?
      self.reminder_interval_minutes = 20 if reminder_interval_minutes.blank?
      self.max_reminders = 5 if max_reminders.blank?
    when "custom"
      self.enabled = true if enabled.nil?
    end

    self.start_delay_minutes ||= 60
    self.reminder_interval_minutes ||= 30
    self.max_reminders ||= 3
    self.notify_contacts_on_no_response = true if notify_contacts_on_no_response.nil?
    self.notify_contacts_on_help = false if notify_contacts_on_help.nil?
    self.share_event_title = false if share_event_title.nil?
    self.share_event_area = false if share_event_area.nil?
  end

  def sync_activation_window
    now = Time.current

    if effective_enabled?
      # 新規作成時、またはオフからオンに戻した時点を起点にする。
      # これにより、オフ期間中に終了済みの予定はあとから対象にならない。
      if new_record? || will_save_change_to_enabled? || will_save_change_to_mode?
        previously_enabled = persisted? && enabled_was == true && mode_was.to_s != "off"
        self.enabled_since = now unless previously_enabled && enabled_since.present?
      end
      self.disabled_at = nil
    else
      self.disabled_at = now if new_record? || will_save_change_to_enabled? || will_save_change_to_mode? || disabled_at.blank?
    end
  end

  def cancel_pending_sessions_when_disabled
    return if effective_enabled?

    CoconiqueSafetyCheckSession
      .where(user: user, status: [:waiting, :extended])
      .update_all(status: CoconiqueSafetyCheckSession.statuses[:canceled], next_reminder_at: Time.current, updated_at: Time.current)
  end
end
