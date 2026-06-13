class CoconiqueUserAdminNote < ApplicationRecord
  belongs_to :user
  belongs_to :admin_user, class_name: "User", optional: true

  before_validation :ensure_public_id, on: :create
  before_validation :normalize_body

  validates :public_id, presence: true, uniqueness: true
  validates :body, presence: true, length: { maximum: 5000 }

  scope :ordered_recently, -> { order(created_at: :desc, id: :desc) }

  private

  def ensure_public_id
    self.public_id = "uan-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def normalize_body
    self.body = body.to_s.strip
  end
end
