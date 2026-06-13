class CoconiqueParticipationRequest < ApplicationRecord
  belongs_to :user
  belongs_to :coconique_event
  belongs_to :reviewed_by, class_name: "User", optional: true
  belongs_to :attendance_recorded_by, class_name: "User", optional: true
  has_one :coconique_feedback, dependent: :destroy

  enum :status, {
    draft: 0,
    pending: 10,
    approved: 20,
    rejected: 30,
    withdrawn: 40,
    auto_withdrawn: 50
  }

  enum :attendance_status, {
    unconfirmed: 0,
    attended: 10,
    absent: 20
  }, prefix: :attendance

  CURRENT_REQUEST_STATUSES = %w[draft pending approved rejected].freeze

  before_validation :ensure_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :message, length: { maximum: 1000 }
  validates :attendance_note, length: { maximum: 1000 }, allow_blank: true
  validate :one_current_request_per_user_and_event

  scope :current_for_event, -> { where(status: CURRENT_REQUEST_STATUSES) }
  scope :active, -> { where(status: [:pending, :approved]) }
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
end
