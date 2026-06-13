class EmailWebhookEvent < ApplicationRecord
  PROVIDER_RESEND = "resend"

  validates :provider, presence: true
  validates :event_id, presence: true, uniqueness: { scope: :provider }
  validates :event_type, presence: true
  validates :payload, presence: true
  validates :metadata, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def processed?
    processed_at.present?
  end
end