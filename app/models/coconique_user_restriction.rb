class CoconiqueUserRestriction < ApplicationRecord
  belongs_to :user
  belongs_to :coconique_report, optional: true
  belongs_to :created_by_admin, class_name: "User", optional: true
  belongs_to :lifted_by_admin, class_name: "User", optional: true

  enum :status, {
    restricted: 0,
    suspended: 10,
    banned: 20
  }

  before_validation :ensure_public_id, on: :create
  before_validation :ensure_defaults
  after_commit :apply_user_account_status!, on: [:create, :update]

  validates :public_id, presence: true, uniqueness: true
  validates :reason, presence: true, length: { maximum: 500 }
  validates :note, length: { maximum: 5000 }, allow_blank: true

  scope :active, ->(now = Time.current) { where(lifted_at: nil).where("starts_at <= ?", now).where("ends_at IS NULL OR ends_at > ?", now) }
  scope :ordered_recently, -> { order(created_at: :desc, id: :desc) }

  def active_now?(now = Time.current)
    lifted_at.blank? && starts_at <= now && (ends_at.blank? || ends_at > now)
  end

  def lift!(admin_user:, note: nil)
    update!(
      lifted_at: Time.current,
      lifted_by_admin: admin_user,
      metadata: (metadata || {}).merge("lift_note" => note.to_s.strip.presence)
    )
    sync_user_status_after_lift!
  end

  private

  def ensure_public_id
    self.public_id = "urs-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def ensure_defaults
    self.starts_at ||= Time.current
    self.metadata ||= {}
  end

  def apply_user_account_status!
    return unless active_now?

    cancel_open_events_for_restricted_user!

    if suspended?
      # BANから一時凍結へ変更した場合も、アカウント状態を現在の最新制限に合わせる。
      user.update!(status: :suspended) unless user.suspended?
      apply_account_billing_policy!(for_ban: false)
      user.auth_sessions.active.update_all(revoked_at: Time.current, updated_at: Time.current)
    elsif banned?
      user.update!(status: :banned) unless user.banned?
      apply_account_billing_policy!(for_ban: true)
      user.auth_sessions.active.update_all(revoked_at: Time.current, updated_at: Time.current)
    end
  end


  def cancel_open_events_for_restricted_user!
    reason_text = case status
                  when "banned" then "アカウントが垢BANされたため、募集中の予定を運営側でキャンセルしました。"
                  when "suspended" then "アカウントが一時凍結されたため、募集中の予定を運営側でキャンセルしました。"
                  else "アカウントが一部制限中になったため、募集中の予定を運営側でキャンセルしました。"
                  end

    canceled_count = CoconiqueEvent.cancel_open_events_for_restricted_user!(user, reason: reason_text)
    return unless canceled_count.positive? && persisted?

    update_column(:metadata, (metadata || {}).merge("canceled_open_events_count" => canceled_count, "canceled_open_events_at" => Time.current.iso8601))
  end

  def apply_account_billing_policy!(for_ban:)
    CoconiqueBilling.cancel_coconique_subscription!(
      user: user,
      reason: for_ban ? "ban" : "suspension",
      source: self
    )

    if for_ban
      CoconiqueBilling.forfeit_all_host_tickets_for_user!(
        user: user,
        reason: "規約違反・BANに伴う主催チケット没収",
        source: self,
        admin: created_by_admin
      )
    end
  rescue NameError, ActiveRecord::StatementInvalid => e
    Rails.logger.warn("[CoconiqueUserRestriction] billing policy skipped: #{e.class} #{e.message}")
  end

  def sync_user_status_after_lift!
    return if user.coconique_user_restrictions.active.where.not(id: id).where(status: [:suspended, :banned]).exists?
    return unless user.suspended? || user.banned?

    user.update!(status: :active)
  end
end
