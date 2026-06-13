class CoconiqueReport < ApplicationRecord
  belongs_to :reporter, class_name: "User"
  belongs_to :reported_user, class_name: "User", optional: true
  belongs_to :coconique_event, optional: true
  belongs_to :coconique_event_message, optional: true
  belongs_to :coconique_safety_check_session, optional: true

  has_many :coconique_report_evidences, dependent: :destroy
  has_many :coconique_report_actions, dependent: :destroy
  has_many :coconique_user_restrictions, dependent: :nullify
  has_many :coconique_user_blocks, dependent: :nullify

  enum :target_type, {
    event: 0,
    user: 10,
    message: 20,
    safety_check: 30
  }, prefix: :target

  enum :reason, {
    other: 0,
    romantic_or_pickup: 10,
    external_contact: 20,
    solicitation: 30,
    harassment: 40,
    content_mismatch: 50,
    danger_or_anxiety: 60,
    no_show_or_late: 70,
    gambling_inducement: 80,
    impersonation_or_false_info: 90
  }, prefix: :reason

  enum :status, {
    submitted: 0,
    reviewing: 10,
    waiting_user: 20,
    action_taken: 30,
    dismissed: 40,
    closed: 50
  }

  enum :severity, {
    low: 0,
    normal: 10,
    high: 20,
    urgent: 30
  }

  enum :report_phase, {
    before_event: 0,
    during_event: 10,
    after_event: 20,
    after_room_closed: 30,
    unknown_phase: 90
  }

  before_validation :ensure_public_id, on: :create
  before_validation :normalize_detail
  before_validation :ensure_snapshot

  validates :public_id, presence: true, uniqueness: true
  validates :detail, length: { maximum: 3000 }, allow_blank: true
  validates :target_public_id, length: { maximum: 120 }, allow_blank: true
  validates :reporter_role, length: { maximum: 80 }, allow_blank: true
  validates :event_status_at_report, length: { maximum: 80 }, allow_blank: true

  scope :ordered_for_admin, -> { order(created_at: :desc, id: :desc) }

  def close_with_status!(next_status:, admin_user:, note: nil)
    previous = status
    update!(status: next_status)

    coconique_report_actions.create!(
      admin_user: admin_user,
      action_type: :status_change,
      previous_status: previous,
      next_status: status,
      note: note
    )
  end

  private

  def ensure_public_id
    self.public_id = "rpt-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def normalize_detail
    self.detail = detail.to_s.strip.presence
  end

  def ensure_snapshot
    self.snapshot ||= {}
  end
end
