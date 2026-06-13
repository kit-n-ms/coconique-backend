class CoconiqueAccountWithdrawalService
  WITHDRAWAL_EVENT_REASON = "ユーザー退会に伴い、予定をキャンセルしました。".freeze
  WITHDRAWAL_PARTICIPATION_REASON = "ユーザー退会に伴い、参加予定をキャンセルしました。".freeze
  WITHDRAWAL_TICKET_REASON = "ユーザー退会に伴う未使用主催チケット失効".freeze
  REASON_KEYS = %w[user_requested found_irreplaceable_relationship safety_concern pricing other].freeze

  def self.summary_for(user, now: Time.current)
    new(user, now: now).summary
  end

  def self.withdraw!(user, reason: nil, note: nil, request: nil)
    new(user).withdraw!(reason: reason, note: note, request: request)
  end

  def initialize(user, now: Time.current)
    @user = user
    @now = now
  end

  def summary
    user.sync_coconique_host_tickets! if user.respond_to?(:sync_coconique_host_tickets!)
    balance = CreditBalance.find_or_create_for!(user: user, app_key: CoconiqueBilling::APP_KEY)

    {
      "canWithdraw" => !user.banned? && !user.withdrawn?,
      "accountStatus" => user.status,
      "hostedUpcomingEventsCount" => hosted_upcoming_events.count,
      "approvedUpcomingParticipationsCount" => approved_upcoming_participations.count,
      "pendingSafetyChecksCount" => pending_safety_checks.count,
      "hostTicketBalance" => balance.balance,
      "availableHostTicketsCount" => user.coconique_host_ticket_lots.sum(:available_count).to_i,
      "reservedHostTicketsCount" => user.coconique_host_ticket_lots.sum(:reserved_count).to_i,
      "subscriptionActive" => user.coconique_billing_active?,
      "subscriptionPlan" => user.coconique_subscription_plan,
      "subscriptionStatus" => user.coconique_subscription_status,
      "currentPeriodEndsAt" => user.coconique_subscription_current_period_ends_at&.iso8601,
      "effects" => effects
    }
  end

  def withdraw!(reason: nil, note: nil, request: nil)
    raise ActiveRecord::RecordInvalid, user if user.banned?
    return summary if user.withdrawn?

    User.transaction do
      user.lock!
      cancel_hosted_events!
      withdraw_approved_participations!
      cancel_pending_safety_checks!
      disable_safety_settings!
      remove_public_and_notification_data!
      CoconiqueBilling.cancel_coconique_subscription!(user: user, reason: "withdrawal", source: user)
      CoconiqueBilling.forfeit_all_host_tickets_for_user!(user: user, reason: WITHDRAWAL_TICKET_REASON, source: user)

      user.update!(
        status: :withdrawn,
        withdrawn_at: Time.current,
        withdrawal_reason: reason.to_s.strip.presence || "user_requested",
        withdrawal_note: note.to_s.strip.presence,
        safety_registered_at: nil
      )

      user.auth_sessions.active.update_all(revoked_at: Time.current, updated_at: Time.current)

      AuditLog.record!(
        user: user,
        action: "coconique.account.withdrawn",
        request: request,
        target: user,
        metadata: {
          hosted_upcoming_events_count: hosted_upcoming_events.count,
          approved_upcoming_participations_count: approved_upcoming_participations.count,
          pending_safety_checks_count: pending_safety_checks.count,
          reason: user.withdrawal_reason
        }
      )
    end

    summary
  end

  private

  attr_reader :user, :now

  def effects
    [
      "ログインできなくなります。",
      "プロフィールは公開されなくなり、表示名は退会済み表示になります。",
      "開催予定がある場合はキャンセルされます。",
      "承認済み参加予定がある場合はキャンセルされます。",
      "未回答の安心帰宅チェックはキャンセルされます。",
      "月額課金は停止されます。",
      "未使用の月額付与チケット・追加購入チケットは失効します。",
      "決済履歴・通報対応・安全管理に必要な記録は、法令・利用規約に基づき一定期間保存されます。"
    ]
  end

  def hosted_upcoming_events
    user.hosted_coconique_events
      .where(status: CoconiqueEvent.statuses.values_at("draft", "reviewing", "recruiting", "closed", "confirmed"))
      .where("ends_at IS NULL OR ends_at > ?", now)
  end

  def approved_upcoming_participations
    user.coconique_participation_requests
      .approved
      .joins(:coconique_event)
      .where(coconique_events: { status: CoconiqueEvent.statuses.values_at("recruiting", "closed", "confirmed") })
      .where("coconique_events.ends_at > ?", now)
  end

  def pending_safety_checks
    user.coconique_safety_check_sessions.needs_response
  end

  def cancel_hosted_events!
    hosted_upcoming_events.find_each do |event|
      previous_status = event.status
      if event.draft? || event.reviewing?
        event.update!(status: :canceled, canceled_at: Time.current, cancellation_reason: WITHDRAWAL_EVENT_REASON)
      else
        event.cancel!(reason: WITHDRAWAL_EVENT_REASON, host_ticket_policy: :forfeit, cancellation_notice_kind: :host_withdrawal)
      end
      event.coconique_event_status_logs.create!(
        user: user,
        action: "coconique.event.canceled_by_account_withdrawal",
        from_status: previous_status,
        to_status: event.status,
        reason: WITHDRAWAL_EVENT_REASON
      )
    end
  end

  def withdraw_approved_participations!
    approved_upcoming_participations.find_each do |participation|
      participation.withdraw!
      CoconiqueNotification.create_system_notification!(
        user: participation.coconique_event.host,
        notification_key: "participant-withdrawn-by-account-withdrawal-#{participation.public_id}",
        title: "参加メンバーがキャンセルしました",
        body: "『#{participation.coconique_event.title.to_s.truncate(40)}』の参加メンバーが退会に伴い参加キャンセルとなりました。",
        link_path: "/app/host/events/#{participation.coconique_event.public_id}",
        occurred_at: Time.current,
        metadata: { participation_request_id: participation.public_id, event_public_id: participation.coconique_event.public_id }
      )
    end
  end

  def cancel_pending_safety_checks!
    pending_safety_checks.update_all(
      status: CoconiqueSafetyCheckSession.statuses[:canceled],
      next_reminder_at: Time.current,
      updated_at: Time.current
    )
  end

  def disable_safety_settings!
    setting = user.coconique_safety_check_setting
    return if setting.blank?

    setting.update!(mode: :off, enabled: false)
  end

  def remove_public_and_notification_data!
    profile = user.user_profile
    profile&.update_columns(
      display_name: "退会したユーザー",
      full_name: nil,
      legal_last_name: nil,
      legal_first_name: nil,
      legal_middle_name: nil,
      legal_last_name_kana: nil,
      legal_first_name_kana: nil,
      legal_middle_name_kana: nil,
      legal_full_name_raw: nil,
      avatar_url: nil,
      profile_headline: nil,
      bio: nil,
      interest_category_keys: [],
      participation_style_keys: [],
      preferred_areas: [],
      conversation_topics: [],
      communication_preferences: [],
      club_love_levels: {},
      public_age_label: "age_private",
      marketing_opt_in: false,
      updated_at: Time.current
    )

    user.coconique_event_favorites.destroy_all
    user.coconique_notifications.visible.update_all(deleted_at: Time.current, updated_at: Time.current)
    user.coconique_emergency_contacts.destroy_all
  end
end
