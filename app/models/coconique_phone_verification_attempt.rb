class CoconiquePhoneVerificationAttempt < ApplicationRecord
  include HasDigestToken

  CODE_TTL = 10.minutes
  MAX_ATTEMPTS = 5
  DEV_TEST_CODE = "123456"

  belongs_to :user

  enum :status, {
    pending: 0,
    confirmed: 1,
    expired: 2,
    failed: 3,
    canceled: 4
  }

  before_validation :ensure_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :phone_number_digest, presence: true
  validates :code_digest, presence: true
  validates :sent_to_masked, presence: true
  validates :provider, presence: true
  validates :expires_at, presence: true

  scope :active_pending, -> { pending.where("expires_at > ?", Time.current) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def self.build_for!(user:, phone_number:, provider: nil, code: nil)
    normalized_phone = normalize_phone_number(phone_number)
    verification_code = code.presence || generated_code_for_environment

    create!(
      user: user,
      phone_number_digest: digest_value(normalized_phone),
      code_digest: digest_value(verification_code),
      sent_to_masked: mask_phone_number(normalized_phone),
      provider: provider.presence || default_provider,
      status: :pending,
      expires_at: CODE_TTL.from_now,
      metadata: {
        "environment" => Rails.env,
        "fake_code_used" => fake_provider?
      }
    )
  end

  def self.normalize_phone_number(value)
    value.to_s.tr("０-９", "0-9").gsub(/[^0-9+]/, "").strip
  end

  def self.digest_value(value)
    OpenSSL::HMAC.hexdigest("SHA256", digest_secret, value.to_s)
  end

  def self.mask_phone_number(value)
    normalized = normalize_phone_number(value)
    return "未入力" if normalized.blank?
    return "****" if normalized.length <= 4

    "#{normalized[0, 3]}****#{normalized[-4, 4]}"
  end

  def self.default_provider
    ENV.fetch("COCONIQUE_SMS_PROVIDER", Rails.env.production? ? "firebase_phone_auth" : "fake_sms")
  end

  def self.fake_provider?
    default_provider == "fake_sms" || Rails.env.development? || Rails.env.test?
  end

  def self.generated_code_for_environment
    return DEV_TEST_CODE if fake_provider?

    SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
  end

  def self.digest_secret
    Rails.application.secret_key_base.presence || ENV.fetch("SECRET_KEY_BASE", "coconique-development-secret")
  end

  def verify!(code)
    return false unless pending?

    if Time.current > expires_at
      update!(status: :expired)
      return false
    end

    increment!(:attempts_count)

    if attempts_count > MAX_ATTEMPTS
      update!(status: :failed)
      return false
    end

    return false unless self.class.digest_value(code.to_s.strip) == code_digest

    transaction do
      update!(status: :confirmed, confirmed_at: Time.current)
      user.update!(
        phone_verification_status: :verified,
        phone_verified_at: Time.current,
        phone_number_digest: phone_number_digest
      )
    end

    true
  end

  private

  def ensure_public_id
    self.public_id ||= "phv_#{SecureRandom.base58(24)}"
  end
end
