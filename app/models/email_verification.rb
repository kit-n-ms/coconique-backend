class EmailVerification < ApplicationRecord
  include HasDigestToken

  PURPOSE_EMAIL_VERIFICATION = "email_verification".freeze
  PURPOSE_EMAIL_CHANGE = "email_change".freeze

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validates :purpose, presence: true, inclusion: { in: [PURPOSE_EMAIL_VERIFICATION, PURPOSE_EMAIL_CHANGE] }
  validates :pending_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :pending_email_required_for_email_change

  scope :usable, -> {
    where(used_at: nil)
      .where("expires_at > ?", Time.current)
  }

  def self.create_for!(user:, purpose: PURPOSE_EMAIL_VERIFICATION, pending_email: nil)
    token = generate_token

    verification = create!(
      user: user,
      token_digest: digest(token),
      expires_at: Time.current + token_ttl,
      purpose: purpose.presence || PURPOSE_EMAIL_VERIFICATION,
      pending_email: pending_email.to_s.strip.downcase.presence
    )

    [verification, token]
  end

  def self.token_ttl
    ENV.fetch("EMAIL_VERIFICATION_TTL_HOURS", "24").to_i.hours
  end

  def email_change?
    purpose.to_s == PURPOSE_EMAIL_CHANGE
  end

  def confirm!
    transaction do
      raise ActiveRecord::RecordInvalid, self unless usable?

      if email_change?
        user.update!(email: pending_email, email_verified_at: Time.current)
      else
        user.update!(email_verified_at: user.email_verified_at || Time.current)
      end

      mark_used!
    end
  end

  private

  def pending_email_required_for_email_change
    return unless email_change?
    return if pending_email.present?

    errors.add(:pending_email, "を入力してください")
  end
end
