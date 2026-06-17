class User < ApplicationRecord
  has_secure_password

  has_one :user_profile, dependent: :destroy

  has_many :auth_sessions, dependent: :destroy
  has_many :email_verifications, dependent: :destroy
  has_many :password_resets, dependent: :destroy
  has_many :terms_acceptances, dependent: :destroy
  has_many :app_memberships, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  has_many :hosted_coconique_events,
    class_name: "CoconiqueEvent",
    foreign_key: :host_id,
    dependent: :nullify
  has_many :coconique_event_favorites, dependent: :destroy
  has_many :favorite_coconique_events,
    through: :coconique_event_favorites,
    source: :coconique_event
  has_many :coconique_participation_requests, dependent: :destroy
  has_many :coconique_event_messages, dependent: :destroy
  has_many :coconique_event_message_reactions, dependent: :destroy
  has_many :coconique_event_chat_reads, dependent: :destroy
  has_many :coconique_notifications, dependent: :destroy
  has_many :coconique_emergency_contacts, dependent: :destroy
  has_one :coconique_safety_check_setting, dependent: :destroy
  has_many :coconique_safety_check_sessions, dependent: :destroy
  has_many :coconique_reports, foreign_key: :reporter_id, dependent: :nullify
  has_many :reported_coconique_reports, class_name: "CoconiqueReport", foreign_key: :reported_user_id, dependent: :nullify
  has_many :given_coconique_feedbacks, class_name: "CoconiqueFeedback", foreign_key: :user_id, dependent: :destroy
  has_many :received_coconique_feedbacks, class_name: "CoconiqueFeedback", foreign_key: :host_id, dependent: :nullify
  has_many :coconique_user_restrictions, dependent: :destroy
  has_many :coconique_user_admin_notes, dependent: :destroy
  has_many :coconique_user_blocks_as_blocker,
    class_name: "CoconiqueUserBlock",
    foreign_key: :blocker_id,
    dependent: :destroy
  has_many :coconique_user_blocks_as_blocked,
    class_name: "CoconiqueUserBlock",
    foreign_key: :blocked_id,
    dependent: :destroy

  has_many :coconique_phone_verification_attempts, dependent: :destroy
  has_many :coconique_identity_verification_sessions, dependent: :destroy
  has_many :coconique_promo_code_redemptions, dependent: :destroy
  has_many :coconique_safety_registration_intents, dependent: :destroy
  has_many :coconique_host_ticket_lots, dependent: :destroy
  has_many :coconique_reentry_signals, dependent: :destroy
  has_many :coconique_reentry_blocklist_entries, class_name: "CoconiqueReentryBlocklistEntry", foreign_key: :source_user_id, dependent: :nullify

  has_one :stripe_customer, dependent: :destroy

  has_many :payment_checkout_sessions, dependent: :destroy
  has_many :credit_balances, dependent: :destroy
  has_many :credit_transactions, dependent: :destroy

  enum :status, {
    active: 0,
    suspended: 1,
    withdrawn: 2,
    banned: 3
  }

  enum :role, {
    general: 0,
    admin: 10
  }

  enum :beta_member_type, {
    general: 0,
    collaborator: 1
  }, prefix: :beta_member

  enum :phone_verification_status, {
    unverified: 0,
    pending: 1,
    verified: 2
  }, prefix: :phone_verification

  enum :identity_verification_status, {
    not_started: 0,
    processing: 1,
    verified: 2,
    rejected: 3,
    requires_input: 4,
    canceled: 5,
    expired: 6
  }, prefix: :identity_verification

  enum :operator_verification_status, {
    none: 0,
    beta_operator_verified: 1
  }, prefix: :operator_verification

  enum :coconique_subscription_status, {
    none: 0,
    trialing: 1,
    active: 2,
    past_due: 3,
    canceled: 4,
    unpaid: 5,
    incomplete: 6
  }, prefix: :coconique_subscription

  before_validation :normalize_email

  validates :email,
    presence: true,
    uniqueness: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }

  validates :password,
    length: { minimum: 12 },
    if: -> { password.present? }

  def email_verified?
    email_verified_at.present?
  end

  def phone_verified?
    phone_verification_verified? && phone_verified_at.present?
  end

  def identity_verified?
    identity_verification_verified? && identity_verified_at.present? && age_over_18?
  end

  def promo_code_verified?
    promo_code_verified_at.present? && beta_member_collaborator?
  end

  def beta_operator_verified?
    operator_verification_beta_operator_verified? && operator_verified_at.present?
  end

  def card_registered?
    card_registered_at.present? || billing_exempted?
  end

  def billing_exempted?
    billing_exempted_at.present?
  end

  def coconique_billing_active?
    return false if withdrawn? || banned?
    return true if billing_exempted?
    return true if coconique_subscription_active? || coconique_subscription_trialing?
    return true if CoconiqueBilling.paid_subscription_evidence?(self)

    false
  end

  def coconique_subscription_founder_beta_like?
    coconique_subscription_plan.to_s == "founder_beta" || coconique_stripe_subscription_id.present?
  end

  def coconique_withdrawn?
    withdrawn? || withdrawn_at.present?
  end

  def coconique_host_ticket_balance
    return 0 unless persisted?

    CreditBalance.find_or_create_for!(user: self, app_key: CoconiqueBilling::APP_KEY).balance
  end

  def grant_coconique_monthly_host_tickets!(source: self, force: false)
    CoconiqueBilling.grant_monthly_host_tickets!(user: self, source: source, force: force)
  end

  def sync_coconique_host_tickets!
    CoconiqueBilling.sync_host_tickets_for_user!(user: self)
  end

  def coconique_additional_host_ticket_purchase_available?
    CoconiqueBilling.additional_host_ticket_purchase_available?(self)
  end

  def activate_coconique_founder_beta_subscription!(source: self)
    CoconiqueBilling.activate_founder_beta_subscription!(user: self, source: source)
  end

  def coconique_collaborator_beta?
    beta_member_collaborator? && promo_code_verified? && beta_operator_verified?
  end

  def coconique_identity_route_required?
    !coconique_collaborator_beta?
  end

  def coconique_active_account_restriction?
    return false unless persisted?

    coconique_user_restrictions.active.where(status: [:restricted, :suspended, :banned]).exists?
  end

  def coconique_reentry_blocked?
    return false unless persisted?

    Coconique::ReentrySignals.blocked_identity_signal?(self) || Coconique::ReentrySignals.blocked_payment_signal?(self)
  rescue NameError, ActiveRecord::StatementInvalid
    false
  end

  def coconique_can_apply_or_publish?
    return false unless active?
    return false if coconique_active_account_restriction?
    return false if coconique_reentry_blocked?
    return false unless email_verified?

    if coconique_collaborator_beta?
      promo_code_verified? && beta_operator_verified? && coconique_billing_active?
    else
      card_registered? && coconique_billing_active? && identity_verified?
    end
  end

  def coconique_safety_missing_requirements
    missing = []
    missing << "email" unless email_verified?

    if coconique_collaborator_beta?
      missing << "promo_code" unless promo_code_verified?
      missing << "operator_verification" unless beta_operator_verified?
      missing << "subscription" unless coconique_billing_active?
    else
      missing << "card" unless card_registered?
      missing << "subscription" unless coconique_billing_active?
      missing << "identity" unless identity_verified?
      missing << "age_over_18" unless age_over_18?
    end

    missing << "account_status" unless active? && !coconique_active_account_restriction? && !coconique_reentry_blocked?
    missing
  end

  def refresh_coconique_safety_registered_at!
    next_value = coconique_can_apply_or_publish? ? Time.current : nil
    update_columns(safety_registered_at: next_value, updated_at: Time.current) if safety_registered_at != next_value
  end

  def mark_card_registered!
    update!(card_registered_at: Time.current)
    refresh_coconique_safety_registered_at!
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end