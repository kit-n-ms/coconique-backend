class CoconiqueIdentityVerificationSession < ApplicationRecord
  belongs_to :user

  enum :status, {
    created: 0,
    processing: 1,
    verified: 2,
    rejected: 3,
    requires_input: 4,
    canceled: 5,
    expired: 6
  }

  before_validation :ensure_public_id, on: :create

  validates :public_id, presence: true, uniqueness: true
  validates :provider, presence: true
  validates :status, presence: true

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def mark_verified!(provider_session_id: self.provider_session_id, age_over_18: true, document_type: nil, provider_status: nil, metadata: {})
    verified_at_value = Time.current

    transaction do
      update!(
        status: :verified,
        provider_session_id: provider_session_id,
        provider_status: provider_status.presence || self.provider_status,
        document_type: document_type.presence || self.document_type,
        verified_at: verified_at_value,
        metadata: self.metadata.merge(metadata.stringify_keys)
      )
      user.update!(
        identity_verification_status: :verified,
        identity_provider: provider,
        identity_verification_id: provider_session_id.presence || public_id,
        identity_workflow_type: workflow_type,
        identity_document_type: document_type.presence || self.document_type,
        identity_external_session_deleted_at: nil,
        identity_verified_at: verified_at_value,
        age_verified: true,
        age_over_18: ActiveModel::Type::Boolean.new.cast(age_over_18)
      )
      user.refresh_coconique_safety_registered_at!
    end
  end

  def mark_rejected!(reason: nil, provider_status: nil, document_type: nil, metadata: {})
    transaction do
      update!(
        status: :rejected,
        provider_status: provider_status.presence || self.provider_status,
        document_type: document_type.presence || self.document_type,
        metadata: self.metadata.merge(metadata.stringify_keys).merge("rejected_reason" => reason).compact
      )
      user.update!(
        identity_verification_status: :rejected,
        identity_provider: provider,
        identity_verification_id: provider_session_id.presence || public_id,
        identity_workflow_type: workflow_type,
        identity_document_type: document_type.presence || self.document_type,
        age_verified: true,
        age_over_18: false
      )
      user.refresh_coconique_safety_registered_at!
    end
  end

  def mark_processing!(provider_status: nil, metadata: {})
    update!(
      status: :processing,
      provider_status: provider_status.presence || self.provider_status,
      metadata: self.metadata.merge(metadata.stringify_keys)
    )
    user.update!(identity_verification_status: :processing, identity_provider: provider)
    user.refresh_coconique_safety_registered_at!
  end

  def mark_requires_input!(provider_status: nil, metadata: {})
    update!(
      status: :requires_input,
      provider_status: provider_status.presence || self.provider_status,
      metadata: self.metadata.merge(metadata.stringify_keys)
    )
    user.update!(identity_verification_status: :requires_input, identity_provider: provider)
    user.refresh_coconique_safety_registered_at!
  end

  def mark_expired!(provider_status: nil, metadata: {})
    update!(
      status: :expired,
      provider_status: provider_status.presence || self.provider_status,
      metadata: self.metadata.merge(metadata.stringify_keys)
    )
    user.update!(identity_verification_status: :expired, identity_provider: provider)
    user.refresh_coconique_safety_registered_at!
  end

  def mark_canceled!(provider_status: nil, metadata: {})
    update!(
      status: :canceled,
      provider_status: provider_status.presence || self.provider_status,
      metadata: self.metadata.merge(metadata.stringify_keys)
    )
    user.update!(identity_verification_status: :canceled, identity_provider: provider)
    user.refresh_coconique_safety_registered_at!
  end

  def mark_provider_session_deleted!
    update!(deleted_at: Time.current)
    user.update!(identity_external_session_deleted_at: deleted_at) if user.identity_verification_id == provider_session_id
  end

  private

  def ensure_public_id
    self.public_id ||= "ivs_#{SecureRandom.base58(24)}"
  end
end
