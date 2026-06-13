module Coconique
  module IdentityVerifications
    ProviderResult = Struct.new(
      :provider,
      :provider_session_id,
      :status,
      :url,
      :return_url,
      :expires_at,
      :workflow_type,
      :document_type,
      :provider_status,
      :metadata,
      keyword_init: true
    )
  end
end
