class CoconiqueEventMessage < ApplicationRecord
  belongs_to :coconique_event
  belongs_to :user

  has_many :coconique_event_message_reactions, dependent: :destroy

  enum :kind, {
    message: 0,
    system: 10,
    lost_item: 20
  }

  before_validation :ensure_public_id, on: :create
  before_validation :normalize_body
  before_validation :normalize_image_urls

  validates :public_id, presence: true, uniqueness: true
  validates :body, presence: true, length: { maximum: 1000 }
  validate :image_urls_limit
  validate :image_urls_are_data_urls

  scope :visible, -> { where(deleted_at: nil) }
  scope :ordered_chronologically, -> { order(created_at: :asc, id: :asc) }
  scope :recent, -> { ordered_chronologically }

  def deleted?
    deleted_at.present?
  end

  def image_urls
    raw_image_urls = if has_attribute?(:image_urls)
      self[:image_urls]
    else
      metadata_value_for_image_urls
    end

    Array(raw_image_urls).map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def image_urls=(value)
    normalized_urls = normalize_image_urls_value(value)

    if has_attribute?(:image_urls)
      self[:image_urls] = normalized_urls
    else
      self.metadata = (metadata || {}).merge("image_urls" => normalized_urls)
    end
  end

  def image_count
    image_urls.size
  end

  private

  def metadata_value_for_image_urls
    return nil unless metadata.respond_to?(:[])

    metadata["image_urls"] || metadata[:image_urls]
  end

  def normalize_image_urls_value(value)
    Array(value).map(&:to_s).map(&:strip).reject(&:blank?).first(3)
  end

  def ensure_public_id
    self.public_id = "msg-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def normalize_body
    self.body = body.to_s.strip
  end

  def normalize_image_urls
    self.image_urls = image_urls
  end

  def image_urls_limit
    return if image_urls.size <= 3

    errors.add(:image_urls, "は3枚まで登録できます")
  end

  def image_urls_are_data_urls
    image_urls.each do |url|
      next if url.start_with?("data:image/webp;base64,", "data:image/png;base64,", "data:image/jpeg;base64,", "https://", "http://")

      errors.add(:image_urls, "には画像URLまたは画像Data URLを指定してください")
    end
  end
end
