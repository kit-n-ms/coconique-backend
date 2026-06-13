class CoconiquePromoCodeRedemption < ApplicationRecord
  belongs_to :user

  enum :status, {
    redeemed: 0,
    revoked: 1
  }

  before_validation :ensure_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :code_digest, presence: true

  def self.code_digest_for(code)
    OpenSSL::HMAC.hexdigest("SHA256", digest_secret, normalize_code(code))
  end

  def self.normalize_code(code)
    code.to_s.strip.upcase.gsub(/[\s\-]/, "")
  end

  def self.valid_collaborator_code?(code)
    normalized = normalize_code(code)
    return false if normalized.blank?

    allowed_codes = ENV.fetch("COCONIQUE_COLLABORATOR_PROMO_CODES", "COCOBETA,FOUNDER,FRIEND").split(",").map { |item| normalize_code(item) }
    allowed_codes.include?(normalized)
  end

  def self.digest_secret
    Rails.application.secret_key_base.presence || ENV.fetch("SECRET_KEY_BASE", "coconique-development-secret")
  end

  def apply_to_user!
    transaction do
      update!(status: :redeemed, redeemed_at: Time.current)
      user.update!(
        beta_member_type: :collaborator,
        promo_code_digest: code_digest,
        promo_code_verified_at: Time.current,
        billing_exempted_at: Time.current,
        operator_verification_status: :beta_operator_verified,
        operator_verified_at: Time.current
      )
      CoconiqueBilling.activate_collaborator_free_plan!(
        user: user,
        source: self,
        metadata: { promo_code: code_label }
      )
      user.refresh_coconique_safety_registered_at!
    end
  end

  private

  def ensure_public_id
    self.public_id ||= "pcr_#{SecureRandom.base58(24)}"
  end
end
