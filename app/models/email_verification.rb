class EmailVerification < ApplicationRecord
  include HasDigestToken

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :usable, -> {
    where(used_at: nil)
      .where("expires_at > ?", Time.current)
  }

  def self.create_for!(user:)
    token = generate_token

    verification = create!(
      user: user,
      token_digest: digest(token),
      expires_at: Time.current + token_ttl
    )

    [verification, token]
  end

  def self.token_ttl
    ENV.fetch("EMAIL_VERIFICATION_TTL_HOURS", "24").to_i.hours
  end

  def confirm!
    transaction do
      raise ActiveRecord::RecordInvalid, self unless usable?

      mark_used!

      user.update!(
        email_verified_at: user.email_verified_at || Time.current
      )
    end
  end
end