class CoconiqueReentryBlocklistEntry < ApplicationRecord
  belongs_to :source_user, class_name: "User", optional: true

  validates :signal_kind, presence: true
  validates :signal_digest, presence: true
  validates :reason, presence: true
  validates :signal_digest, uniqueness: { scope: :signal_kind, conditions: -> { where(lifted_at: nil) } }

  scope :active, -> { where(lifted_at: nil) }
  scope :recent_first, -> { order(blocked_at: :desc, id: :desc) }

  def active?
    lifted_at.blank?
  end
end
