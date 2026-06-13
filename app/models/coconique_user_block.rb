class CoconiqueUserBlock < ApplicationRecord
  belongs_to :blocker, class_name: "User"
  belongs_to :blocked, class_name: "User"
  belongs_to :coconique_report, optional: true
  belongs_to :lifted_by, class_name: "User", optional: true

  before_validation :ensure_public_id, on: :create
  before_validation :normalize_fields

  validates :public_id, presence: true, uniqueness: true
  validates :blocker_id, presence: true
  validates :blocked_id, presence: true
  validates :note, length: { maximum: 1000 }, allow_blank: true
  validate :cannot_block_self
  validate :active_pair_uniqueness, if: -> { lifted_at.blank? }

  scope :active, -> { where(lifted_at: nil) }
  scope :ordered_recently, -> { order(created_at: :desc, id: :desc) }

  REASON_LABELS = {
    "not_compatible" => "相性が合わなかった",
    "privacy" => "知り合いなので表示したくない",
    "uncomfortable" => "不安・不快に感じた",
    "after_report" => "通報・相談後の遠慮設定",
    "other" => "その他"
  }.freeze

  def active?
    lifted_at.blank?
  end

  def lift!(user: nil)
    update!(lifted_at: Time.current, lifted_by: user)
  end

  def self.blocked_between?(user_a, user_b)
    return false if user_a.blank? || user_b.blank?
    return false if user_a.id == user_b.id

    active.where(blocker_id: user_a.id, blocked_id: user_b.id)
      .or(active.where(blocker_id: user_b.id, blocked_id: user_a.id))
      .exists?
  end

  def self.related_user_ids_for(user)
    return [] if user.blank?

    active
      .where("blocker_id = :id OR blocked_id = :id", id: user.id)
      .pluck(:blocker_id, :blocked_id)
      .flatten
      .uniq
      .reject { |id| id == user.id }
  end

  private

  def ensure_public_id
    self.public_id = "blk-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def normalize_fields
    self.reason = reason.to_s.presence || "other"
    self.note = note.to_s.strip.presence
    self.metadata ||= {}
  end

  def cannot_block_self
    return if blocker_id.blank? || blocked_id.blank? || blocker_id != blocked_id

    errors.add(:blocked_id, "自分自身を遠慮設定にはできません。")
  end

  def active_pair_uniqueness
    return if blocker_id.blank? || blocked_id.blank?

    duplicate = self.class.active
      .where(blocker_id: blocker_id, blocked_id: blocked_id)
      .where.not(id: id)
      .exists?

    errors.add(:base, "このメンバーはすでに遠慮設定されています。") if duplicate
  end
end
