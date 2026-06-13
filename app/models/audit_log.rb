class AuditLog < ApplicationRecord
  belongs_to :user, optional: true

  validates :action, presence: true

  def self.record!(user:, action:, request:, target: nil, metadata: {})
    create!(
      user: user,
      action: action,
      target_type: target&.class&.name,
      target_id: target&.id&.to_s,
      metadata: metadata || {},
      ip_address: request.remote_ip,
      user_agent: request.user_agent.to_s.truncate(1000)
    )
  rescue StandardError => e
    Rails.logger.warn("[AuditLog] failed: #{e.class} #{e.message}")
    nil
  end
end