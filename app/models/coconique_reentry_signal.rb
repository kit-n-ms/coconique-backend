class CoconiqueReentrySignal < ApplicationRecord
  belongs_to :user

  enum :status, {
    observed: 0,
    matched_blocklist: 10,
    ignored: 20
  }

  validates :signal_kind, presence: true
  validates :signal_digest, presence: true
  validates :detected_at, presence: true
  validates :signal_digest, uniqueness: { scope: [:user_id, :signal_kind] }

  scope :recent_first, -> { order(detected_at: :desc, id: :desc) }
  scope :blocklistable, -> { where.not(signal_digest: nil) }
end
