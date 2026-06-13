class CoconiqueReportEvidence < ApplicationRecord
  belongs_to :coconique_report

  enum :evidence_type, {
    event_snapshot: 0,
    message_snapshot: 10,
    user_snapshot: 20,
    safety_check_snapshot: 30,
    system_log: 40,
    attachment: 50,
    chat_log_snapshot: 60
  }

  before_validation :ensure_public_id, on: :create
  before_validation :ensure_metadata

  validates :public_id, presence: true, uniqueness: true
  validates :body, length: { maximum: 10_000 }, allow_blank: true

  private

  def ensure_public_id
    self.public_id = "evd-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def ensure_metadata
    self.metadata ||= {}
  end
end
