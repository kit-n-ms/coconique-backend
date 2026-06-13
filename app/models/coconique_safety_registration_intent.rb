class CoconiqueSafetyRegistrationIntent < ApplicationRecord
  belongs_to :user
  belongs_to :coconique_event, optional: true

  enum :kind, {
    apply_event: 0,
    publish_event: 1,
    open_chat: 2,
    view_meeting_place: 3
  }

  enum :status, {
    pending: 0,
    completed: 1,
    expired: 2,
    canceled: 3
  }

  before_validation :ensure_public_id, on: :create
  before_validation :set_default_expiry, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :kind, presence: true
  validates :expires_at, presence: true

  scope :active_pending, -> { pending.where("expires_at > ?", Time.current) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def expired_now?
    pending? && Time.current > expires_at
  end

  def complete!
    update!(status: :completed, completed_at: Time.current)
  end

  private

  def ensure_public_id
    self.public_id ||= "sri_#{SecureRandom.base58(24)}"
  end

  def set_default_expiry
    self.expires_at ||= 2.hours.from_now
  end
end
