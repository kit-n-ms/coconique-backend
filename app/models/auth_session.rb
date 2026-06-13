class AuthSession < ApplicationRecord
  TOKEN_BYTES = 48

  belongs_to :user

  validates :session_token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> {
    where(revoked_at: nil)
      .where("expires_at > ?", Time.current)
  }

  def self.create_for!(user:, request:)
    session_token = generate_token
    csrf_token = generate_token

    session = create!(
      user: user,
      session_token_digest: digest(session_token),
      csrf_token_digest: digest(csrf_token),
      expires_at: Time.current + session_ttl,
      ip_address: request.remote_ip,
      user_agent: request.user_agent.to_s.truncate(1000)
    )

    [session, session_token, csrf_token]
  end

  def self.generate_token
    SecureRandom.urlsafe_base64(TOKEN_BYTES)
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  def self.session_ttl
    ENV.fetch("AUTH_SESSION_TTL_DAYS", "14").to_i.days
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def rotate_csrf_token!
    token = self.class.generate_token

    update!(
      csrf_token_digest: self.class.digest(token)
    )

    token
  end
end