class CoconiqueEmergencyContactNotification < ApplicationRecord
  belongs_to :coconique_safety_check_session
  belongs_to :coconique_emergency_contact

  enum :kind, {
    no_response: 0,
    help: 10
  }

  enum :status, {
    pending: 0,
    sent: 10,
    failed: 20,
    skipped: 30
  }

  before_validation :ensure_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true

  delegate :user, :coconique_event, to: :coconique_safety_check_session

  def mark_sent!
    update!(status: :sent, sent_at: Time.current, error_message: nil)
  end

  def mark_failed!(message)
    update!(status: :failed, error_message: message.to_s.truncate(1000))
  end

  private

  def ensure_public_id
    self.public_id = "ecn-#{SecureRandom.hex(8)}" if public_id.blank?
  end
end
