class CoconiqueHostTicketLot < ApplicationRecord
  belongs_to :user
  belongs_to :source, polymorphic: true, optional: true
  has_many :reserved_coconique_events,
    class_name: "CoconiqueEvent",
    foreign_key: :host_ticket_lot_id,
    dependent: :nullify

  enum :grant_type, {
    monthly_grant: 0,
    purchase_grant: 10,
    admin_grant: 20,
    collaborator_grant: 30
  }, prefix: :grant

  before_validation :ensure_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :total_count, :available_count, :reserved_count, :consumed_count, :expired_count, :forfeited_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :counts_do_not_exceed_total

  scope :available, ->(now = Time.current) {
    where("available_count > 0")
      .where("expires_at IS NULL OR expires_at > ?", now)
  }
  scope :due_to_expire, ->(now = Time.current) {
    where("available_count > 0")
      .where.not(expires_at: nil)
      .where("expires_at <= ?", now)
  }

  def available?
    available_count.positive? && (expires_at.blank? || expires_at > Time.current)
  end

  private

  def ensure_public_id
    self.public_id = "htl-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def counts_do_not_exceed_total
    used_count = available_count.to_i + reserved_count.to_i + consumed_count.to_i + expired_count.to_i + forfeited_count.to_i
    return if used_count <= total_count.to_i

    errors.add(:base, "host ticket lot counts exceed total")
  end
end
