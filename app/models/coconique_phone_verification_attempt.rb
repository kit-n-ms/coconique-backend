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
    selected_provider = provider.presence || default_provider
    verification_code = code.presence || generated_code_for_environment(provider: selected_provider)
    provider_metadata = {
      "environment" => Rails.env,
      "fake_code_used" => fake_provider?(selected_provider)
    }

    if selected_provider == "twilio_verify"
      twilio_response = Coconique::SmsVerifications::TwilioVerifyProvider.new.start_verification(phone_number: normalized_phone)
      provider_metadata.merge!(
        "twilio_verification_sid" => twilio_response["sid"],
        "twilio_status" => twilio_response["status"],
        "twilio_channel" => twilio_response["channel"],
        "twilio_send_code_attempts_count" => Array(twilio_response["send_code_attempts"]).length,
        "twilio_created_at" => twilio_response["date_created"],
        "twilio_updated_at" => twilio_response["date_updated"]
      ).compact!
    end

    create!(
      user: user,
      phone_number_digest: digest_value(normalized_phone),
      code_digest: digest_value(verification_code),
      sent_to_masked: mask_phone_number(normalized_phone),
      provider: selected_provider,
      status: :pending,
      expires_at: CODE_TTL.from_now,
      metadata: provider_metadata
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
    ENV.fetch("COCONIQUE_SMS_PROVIDER", Rails.env.production? ? "twilio_verify" : "fake_sms")
  end

  def self.fake_provider?(provider = default_provider)
    provider.to_s == "fake_sms" || Rails.env.test?
  end

  def self.generated_code_for_environment(provider: default_provider)
    return DEV_TEST_CODE if fake_provider?(provider)

    # External providers such as Twilio Verify generate and validate the OTP on
    # the vendor side. Keep a digest placeholder so existing DB constraints stay
    # intact without storing vendor-generated OTPs locally.
    "external-#{SecureRandom.hex(16)}"
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

    verified = if provider == "twilio_verify"
      verify_with_twilio!(code)
    else
      self.class.digest_value(code.to_s.strip) == code_digest
    end

    return false unless verified

    mark_confirmed!
    true
  end

  def mark_confirmed!
    transaction do
      update!(status: :confirmed, confirmed_at: Time.current)
      user.update!(
        phone_verification_status: :verified,
        phone_verified_at: Time.current,
        phone_number_digest: phone_number_digest
      )
    end
  end

  def verify_with_twilio!(code)
    approved, response = Coconique::SmsVerifications::TwilioVerifyProvider.new.check_verification(
      attempt: self,
      code: code
    )

    self.metadata = metadata.merge(
      "twilio_check_status" => response["status"],
      "twilio_check_valid" => response["valid"],
      "twilio_check_sid" => response["sid"],
      "twilio_checked_at" => Time.current.iso8601
    ).compact
    save!

    approved
  end

  private

  def ensure_public_id
    self.public_id ||= "phv_#{SecureRandom.base58(24)}"
  end
end
