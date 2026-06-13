class CoconiqueEventMessageReaction < ApplicationRecord
  EMOJI_KEYS = %w[thanks like ok smile laugh shocked clap hooray check heart exclamation question].freeze

  belongs_to :coconique_event_message
  belongs_to :user

  before_validation :ensure_public_id, on: :create
  before_validation :normalize_emoji_key

  validates :public_id, presence: true, uniqueness: true
  validates :emoji_key, presence: true, inclusion: { in: EMOJI_KEYS }
  validates :user_id, uniqueness: { scope: [:coconique_event_message_id, :emoji_key] }

  scope :recent, -> { order(created_at: :asc, id: :asc) }

  private

  def ensure_public_id
    self.public_id = "rxn-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def normalize_emoji_key
    self.emoji_key = emoji_key.to_s.strip
  end
end
