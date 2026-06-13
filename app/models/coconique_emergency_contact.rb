class CoconiqueEmergencyContact < ApplicationRecord
  include HasDigestToken

  MAX_ACTIVE_CONTACTS_PER_USER = 3
  APPROVAL_TOKEN_TTL = 14.days

  belongs_to :user
  has_many :coconique_emergency_contact_notifications, dependent: :restrict_with_error

  enum :status, {
    pending: 0,
    approved: 10,
    rejected: 20,
    revoked: 30
  }

  before_validation :ensure_public_id, on: :create
  before_validation :normalize_values

  validates :public_id, presence: true, uniqueness: true
  validates :name, presence: true, length: { maximum: 80 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 255 }
  validates :email, uniqueness: { scope: :user_id }
  validate :active_contact_limit

  scope :active, -> { where(status: [:pending, :approved]) }
  scope :approved_active, -> { approved.where(revoked_at: nil) }
  scope :ordered_recently, -> { order(updated_at: :desc, id: :desc) }

  def self.find_usable_approval_token!(token)
    contact = find_by!(approval_token_digest: digest(token))
    unless contact.approval_token_usable?
      contact.errors.add(:base, "承認URLの有効期限が切れています。")
      raise ActiveRecord::RecordInvalid, contact
    end

    contact
  end

  def approval_token_usable?
    pending? && approval_token_digest.present? && approval_token_expires_at.present? && approval_token_expires_at.future?
  end

  def issue_approval_token!
    token = self.class.generate_token

    update!(
      status: :pending,
      approval_token_digest: self.class.digest(token),
      approval_token_expires_at: Time.current + APPROVAL_TOKEN_TTL,
      last_invited_at: Time.current,
      rejected_at: nil,
      revoked_at: nil
    )

    token
  end

  def approve!
    update!(
      status: :approved,
      approved_at: Time.current,
      rejected_at: nil,
      revoked_at: nil,
      approval_token_digest: nil,
      approval_token_expires_at: nil
    )
  end

  def reject!
    update!(
      status: :rejected,
      rejected_at: Time.current,
      approval_token_digest: nil,
      approval_token_expires_at: nil
    )
  end

  def revoke!
    update!(
      status: :revoked,
      revoked_at: Time.current,
      approval_token_digest: nil,
      approval_token_expires_at: nil
    )
  end

  private

  def ensure_public_id
    self.public_id = "emc-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def normalize_values
    self.name = name.to_s.strip
    self.email = email.to_s.strip.downcase
  end

  def active_contact_limit
    return if user_id.blank? || revoked?

    count = self.class
      .where(user_id: user_id, status: self.class.statuses.values_at("pending", "approved"))
      .where.not(id: id)
      .count

    return if count < MAX_ACTIVE_CONTACTS_PER_USER

    errors.add(:base, "緊急連絡先は最大#{MAX_ACTIVE_CONTACTS_PER_USER}件まで登録できます。")
  end
end
