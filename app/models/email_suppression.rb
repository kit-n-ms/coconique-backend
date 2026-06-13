class EmailSuppression < ApplicationRecord
  REASON_BOUNCED = "bounced"
  REASON_COMPLAINED = "complained"
  REASON_FAILED = "failed"
  REASON_SUPPRESSED = "suppressed"

  validates :email, presence: true, uniqueness: true
  validates :reason, presence: true
  validates :source, presence: true
  validates :suppressed_at, presence: true
  validates :metadata, presence: true

  before_validation :normalize_email

  def self.suppressed?(email)
    normalized = email.to_s.strip.downcase
    return false if normalized.blank?

    exists?(email: normalized)
  end

  def self.suppress!(
    email:,
    reason:,
    source:,
    source_event_id:,
    metadata: {}
  )
    normalized = email.to_s.strip.downcase
    return if normalized.blank?

    record = find_or_initialize_by(email: normalized)

    record.assign_attributes(
      reason: reason,
      source: source,
      source_event_id: source_event_id,
      suppressed_at: record.suppressed_at || Time.current,
      metadata: (record.metadata || {}).merge(metadata || {})
    )

    record.save!
    record
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end