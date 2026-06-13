class PasswordReset < ApplicationRecord
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

    reset = create!(
      user: user,
      token_digest: digest(token),
      expires_at: Time.current + token_ttl
    )

    [reset, token]
  end

  def self.token_ttl
    ENV.fetch("PASSWORD_RESET_TTL_MINUTES", "30").to_i.minutes
  end

  def confirm!(password:, password_confirmation:)
    transaction do
      raise ActiveRecord::RecordInvalid, self unless usable?

      user.update!(
        password: password,
        password_confirmation: password_confirmation
      )

      mark_used!

      # パスワード変更後は既存セッションを全失効
      user.auth_sessions.active.update_all(
        revoked_at: Time.current,
        updated_at: Time.current
      )
    end
  end
end