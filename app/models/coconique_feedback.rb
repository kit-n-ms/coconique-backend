class CoconiqueFeedback < ApplicationRecord
  MIN_PUBLIC_COUNT = 3
  RATE_PUBLIC_COUNT = 10

  belongs_to :user
  belongs_to :host, class_name: "User"
  belongs_to :coconique_event
  belongs_to :coconique_participation_request

  enum :safety_answer, {
    safe: 0,
    minor_concern: 10,
    trouble: 20
  }, prefix: :safety

  enum :accuracy_answer, {
    matched: 0,
    slightly_different: 10,
    very_different: 20
  }, prefix: :accuracy

  enum :join_again_answer, {
    yes: 0,
    maybe: 10,
    no: 20
  }, prefix: :join_again

  enum :status, {
    submitted: 0,
    held: 10,
    excluded: 20
  }

  before_validation :ensure_public_id, on: :create
  before_validation :normalize_private_note
  before_validation :assign_event_and_host_from_participation

  validates :public_id, presence: true, uniqueness: true
  validates :coconique_participation_request_id, uniqueness: true
  validates :private_note, length: { maximum: 1000 }, allow_blank: true
  validate :participation_request_must_match_feedback
  validate :feedback_event_must_be_finished

  scope :ordered_recently, -> { order(created_at: :desc, id: :desc) }
  scope :public_countable, -> { submitted.where(public_countable: true).joins(:user).where(users: { status: User.statuses["active"] }) }

  def self.public_summary_for_host(host)
    return empty_public_summary if host.blank?

    scope = public_countable.where(host_id: host.id)
    scope = scope.where.not(coconique_event_id: unresolved_report_event_ids)
    build_public_summary(scope)
  end

  def self.admin_summary_for_host(host)
    return empty_admin_summary if host.blank?

    scope = where(host_id: host.id)
    public_summary = build_public_summary(public_countable.where(host_id: host.id).where.not(coconique_event_id: unresolved_report_event_ids))

    public_summary.merge(
      "submittedCount" => scope.submitted.count,
      "heldCount" => scope.held.count,
      "excludedCount" => scope.excluded.count,
      "safetyMinorConcernCount" => scope.safety_minor_concern.count,
      "safetyTroubleCount" => scope.safety_trouble.count,
      "accuracySlightlyDifferentCount" => scope.accuracy_slightly_different.count,
      "accuracyVeryDifferentCount" => scope.accuracy_very_different.count,
      "joinAgainMaybeCount" => scope.join_again_maybe.count,
      "joinAgainNoCount" => scope.join_again_no.count
    )
  end

  def needs_support_followup?
    safety_trouble? || accuracy_very_different? || join_again_no?
  end

  def soft_concern?
    safety_minor_concern? || accuracy_slightly_different? || join_again_maybe?
  end

  private

  def self.unresolved_report_event_ids
    CoconiqueReport
      .where(status: [:submitted, :reviewing, :waiting_user])
      .where.not(coconique_event_id: nil)
      .select(:coconique_event_id)
  end

  def self.build_public_summary(scope)
    total = scope.count
    join_yes = scope.join_again_yes.count
    safe_count = scope.safety_safe.count
    matched_count = scope.accuracy_matched.count

    display_mode = if total >= RATE_PUBLIC_COUNT
      "rate"
    elsif total >= MIN_PUBLIC_COUNT
      "count"
    elsif total.positive?
      "collecting"
    else
      "empty"
    end

    {
      "totalCount" => total,
      "joinAgainYesCount" => join_yes,
      "safetySafeCount" => safe_count,
      "accuracyMatchedCount" => matched_count,
      "displayMode" => display_mode,
      "isPubliclyVisible" => total >= MIN_PUBLIC_COUNT,
      "safetySafeRate" => percentage(safe_count, total),
      "accuracyMatchedRate" => percentage(matched_count, total),
      "joinAgainYesRate" => percentage(join_yes, total)
    }
  end

  def self.empty_public_summary
    {
      "totalCount" => 0,
      "joinAgainYesCount" => 0,
      "safetySafeCount" => 0,
      "accuracyMatchedCount" => 0,
      "displayMode" => "empty",
      "isPubliclyVisible" => false,
      "safetySafeRate" => nil,
      "accuracyMatchedRate" => nil,
      "joinAgainYesRate" => nil
    }
  end

  def self.empty_admin_summary
    empty_public_summary.merge(
      "submittedCount" => 0,
      "heldCount" => 0,
      "excludedCount" => 0,
      "safetyMinorConcernCount" => 0,
      "safetyTroubleCount" => 0,
      "accuracySlightlyDifferentCount" => 0,
      "accuracyVeryDifferentCount" => 0,
      "joinAgainMaybeCount" => 0,
      "joinAgainNoCount" => 0
    )
  end

  def self.percentage(count, total)
    return nil if total.zero?

    ((count.to_f / total) * 100).round
  end

  def ensure_public_id
    self.public_id = "fdb-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def normalize_private_note
    self.private_note = private_note.to_s.strip.presence
  end

  def assign_event_and_host_from_participation
    return if coconique_participation_request.blank?

    self.coconique_event ||= coconique_participation_request.coconique_event
    self.host ||= coconique_event&.host
  end

  def participation_request_must_match_feedback
    return if coconique_participation_request.blank?

    if user_id.present? && coconique_participation_request.user_id != user_id
      errors.add(:base, "この参加申請には安心フィードバックを送信できません。")
    end

    if coconique_event_id.present? && coconique_participation_request.coconique_event_id != coconique_event_id
      errors.add(:base, "参加申請とおでかけの組み合わせが一致しません。")
    end

    unless coconique_participation_request.approved?
      errors.add(:base, "参加が決まったおでかけだけ安心フィードバックを送信できます。")
    end

    if host_id.present? && host_id == user_id
      errors.add(:base, "自分自身には安心フィードバックを送信できません。")
    end
  end

  def feedback_event_must_be_finished
    event = coconique_event || coconique_participation_request&.coconique_event
    return if event.blank?

    if event.canceled?
      errors.add(:base, "キャンセル済みのおでかけには安心フィードバックを送信できません。")
      return
    end

    return if event.finished?
    return if event.ends_at.present? && event.ends_at <= Time.current

    errors.add(:base, "安心フィードバックはおでかけ終了後に送信できます。")
  end
end
