module HasDigestToken
  extend ActiveSupport::Concern

  TOKEN_BYTES = 48

  class_methods do
    def generate_token
      SecureRandom.urlsafe_base64(TOKEN_BYTES)
    end

    def digest(token)
      OpenSSL::Digest::SHA256.hexdigest(token.to_s)
    end
  end

  def usable?
    used_at.nil? && expires_at.future?
  end

  def mark_used!
    update!(used_at: Time.current)
  end
end
