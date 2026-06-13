class StripeWebhookEvent < ApplicationRecord
  validates :stripe_event_id, presence: true, uniqueness: true
  validates :event_type, presence: true

  def processed?
    processed_at.present?
  end
end