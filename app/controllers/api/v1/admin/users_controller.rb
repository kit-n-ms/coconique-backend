module Api
  module V1
    module Admin
      class UsersController < BaseController
        def index
          scope = User.includes(:user_profile, :coconique_safety_check_setting, :coconique_emergency_contacts, :coconique_user_restrictions).order(created_at: :desc)

          requested_status = params[:status].presence || params[:restriction_status].presence || params[:restrictionStatus].presence

          if requested_status.present? && CoconiqueUserRestriction.statuses.key?(requested_status)
            active_restriction_user_ids = CoconiqueUserRestriction
              .active
              .where(status: requested_status)
              .select(:user_id)
            scope = scope.where(id: active_restriction_user_ids)
          elsif requested_status.present? && User.statuses.key?(requested_status)
            scope = scope.where(status: requested_status)
          end

          if params[:role].present? && User.roles.key?(params[:role])
            scope = scope.where(role: params[:role])
          end

          if params[:q].present?
            keyword = params[:q].to_s.strip.downcase
            escaped = ActiveRecord::Base.sanitize_sql_like(keyword)
            scope = scope.left_outer_joins(:user_profile).where(
              "LOWER(users.email) LIKE :keyword OR LOWER(user_profiles.display_name) LIKE :keyword OR LOWER(user_profiles.full_name) LIKE :keyword",
              keyword: "%#{escaped}%"
            )
          end

          users, pagination = paginated(scope)

          render_success(
            {
              users: users.map { |user| admin_user_summary_json(user) },
              pagination: pagination
            }
          )
        end

        def show
          user = User
            .includes(
              :user_profile,
              :app_memberships,
              :credit_balances,
              :credit_transactions,
              :payment_checkout_sessions,
              :coconique_identity_verification_sessions,
              :coconique_phone_verification_attempts,
              :coconique_promo_code_redemptions,
              :stripe_customer,
              :terms_acceptances,
              :auth_sessions,
              :coconique_safety_check_setting,
              :coconique_emergency_contacts,
              :coconique_user_restrictions,
              :coconique_user_admin_notes,
              :given_coconique_feedbacks,
              :received_coconique_feedbacks,
              :hosted_coconique_events,
              coconique_user_blocks_as_blocker: [:blocked, :coconique_report, :lifted_by],
              coconique_user_blocks_as_blocked: [:blocker, :coconique_report, :lifted_by],
              coconique_participation_requests: :coconique_event,
              coconique_reports: [:reported_user, :coconique_event],
              reported_coconique_reports: [:reporter, :coconique_event]
            )
            .find(params[:id])

          render_success({ user: admin_user_detail_json(user) })
        end

        def status
          user = User.find(params[:id])
          next_status = params.require(:status)

          unless User.statuses.key?(next_status)
            return render_error(
              code: "INVALID_STATUS",
              message: "指定されたステータスは使用できません。",
              status: :unprocessable_entity
            )
          end

          if user.id == current_user.id && next_status != "active"
            return render_error(
              code: "CANNOT_CHANGE_OWN_STATUS",
              message: "自分自身のアカウントを停止・削除状態に変更することはできません。",
              status: :unprocessable_entity
            )
          end

          user.update!(status: next_status)

          if next_status != "active"
            user.auth_sessions.active.update_all(
              revoked_at: Time.current,
              updated_at: Time.current
            )
          end

          AuditLog.record!(
            user: current_user,
            action: "admin.user_status_updated",
            request: request,
            target: user,
            metadata: {
              status: next_status
            }
          )

          render_success({ user: admin_user_detail_json(user.reload) })
        end

        def add_note
          user = User.find(params[:id])
          body = params.require(:body).to_s

          note = user.coconique_user_admin_notes.create!(
            admin_user: current_user,
            body: body,
            metadata: { source: "admin_user_detail" }
          )

          AuditLog.record!(
            user: current_user,
            action: "admin.coconique_user_admin_note.created",
            request: request,
            target: user,
            metadata: { note_public_id: note.public_id }
          )

          render_success({ user: admin_user_detail_json(user.reload) }, status: :created)
        end

        private

        def admin_user_summary_json(user)
          profile = user.user_profile
          active_restriction = active_coconique_restriction_json(user)
          safety_setting = user.coconique_safety_check_setting
          contacts = user.coconique_emergency_contacts

          {
            "id" => user.id.to_s,
            "email" => user.email,
            "displayName" => profile&.display_name || user.email.to_s.split("@").first,
            "avatarUrl" => profile&.avatar_url,
            "emailVerified" => user.email_verified_at.present?,
            "status" => user.status,
            "role" => user.role,
            "createdAt" => user.created_at&.iso8601,
            "lastLoginAt" => user.last_login_at&.iso8601,
            "withdrawnAt" => user.respond_to?(:withdrawn_at) ? user.withdrawn_at&.iso8601 : nil,
            "withdrawalReason" => user.respond_to?(:withdrawal_reason) ? user.withdrawal_reason : nil,
            "identityVerification" => identity_verification_json(user, profile),
            "safetyCheck" => safety_check_summary_json(safety_setting),
            "emergencyContacts" => emergency_contact_summary_json(contacts),
            "activeRestriction" => active_restriction,
            "feedbackSummary" => CoconiqueFeedback.admin_summary_for_host(user),
            "reportsMadeCount" => user.coconique_reports.count,
            "reportsReceivedCount" => user.reported_coconique_reports.count,
            "hostedEventsCount" => user.hosted_coconique_events.count,
            "participationsCount" => user.coconique_participation_requests.count
          }
        end

        def admin_user_detail_json(user)
          admin_user_summary_json(user).merge(
            "profile" => admin_profile_json(user.user_profile),
            "hostedEvents" => user.hosted_coconique_events.order(created_at: :desc).limit(30).map { |event| admin_event_json(event) },
            "participations" => user.coconique_participation_requests.order(created_at: :desc).limit(50).map { |request| admin_participation_json(request) },
            "reportsMade" => user.coconique_reports.order(created_at: :desc).limit(50).map { |report| admin_report_brief_json(report) },
            "reportsReceived" => user.reported_coconique_reports.order(created_at: :desc).limit(50).map { |report| admin_report_brief_json(report) },
            "restrictions" => user.coconique_user_restrictions.order(created_at: :desc, id: :desc).limit(50).map { |restriction| admin_restriction_json(restriction) },
            "blocksMade" => user.coconique_user_blocks_as_blocker.order(created_at: :desc, id: :desc).limit(50).map { |block| admin_user_block_json(block) },
            "blocksReceived" => user.coconique_user_blocks_as_blocked.order(created_at: :desc, id: :desc).limit(50).map { |block| admin_user_block_json(block) },
            "feedbacksGiven" => user.given_coconique_feedbacks.includes(:host, :coconique_event).ordered_recently.limit(50).map { |feedback| admin_feedback_json(feedback) },
            "feedbacksReceived" => user.received_coconique_feedbacks.includes(:user, :coconique_event).ordered_recently.limit(50).map { |feedback| admin_feedback_json(feedback) },
            "safetyRegistration" => admin_safety_registration_json(user),
            "billing" => admin_billing_json(user),
            "hostTickets" => admin_host_tickets_json(user),
            "hostTicketLots" => user.coconique_host_ticket_lots.order(created_at: :desc).limit(50).map { |lot| admin_host_ticket_lot_json(lot) },
            "identityVerificationSessions" => user.coconique_identity_verification_sessions.recent_first.limit(20).map { |session| admin_identity_session_json(session) },
            "checkoutSessions" => user.payment_checkout_sessions.includes(:credit_product).order(created_at: :desc).limit(20).map { |session| admin_checkout_session_json(session) },
            "creditTransactions" => user.credit_transactions.where(app_key: ::CoconiqueBilling::APP_KEY).order(created_at: :desc).limit(50).map { |transaction| admin_credit_transaction_json(transaction) },
            "adminNotes" => user.coconique_user_admin_notes.ordered_recently.limit(50).map { |note| admin_note_json(note) },
            "appMemberships" => user.app_memberships.order(created_at: :desc).map { |membership| admin_membership_json(membership) },
            "termsAcceptances" => user.terms_acceptances.order(accepted_at: :desc).limit(10).map { |acceptance| admin_terms_acceptance_json(acceptance) },
            "authSessions" => user.auth_sessions.order(created_at: :desc).limit(10).map { |session| auth_session_json(session) }
          )
        end

        def admin_profile_json(profile)
          return nil if profile.blank?

          {
            "id" => profile.id,
            "displayName" => profile.display_name,
            "fullName" => profile.full_name,
            "legalLastName" => profile.legal_last_name,
            "legalFirstName" => profile.legal_first_name,
            "legalMiddleName" => profile.legal_middle_name,
            "legalLastNameKana" => profile.legal_last_name_kana,
            "legalFirstNameKana" => profile.legal_first_name_kana,
            "legalMiddleNameKana" => profile.legal_middle_name_kana,
            "identityBirthDate" => profile.identity_birth_date&.iso8601,
            "identityGender" => profile.identity_gender,
            "publicAgeLabel" => profile.public_age_label,
            "headline" => profile.profile_headline,
            "bio" => profile.bio,
            "interestCategoryKeys" => profile.interest_category_keys || [],
            "participationStyleKeys" => profile.participation_style_keys || [],
            "preferredAreas" => profile.preferred_areas || [],
            "conversationTopics" => profile.conversation_topics || [],
            "communicationPreferences" => profile.communication_preferences || [],
            "clubLoveLevels" => profile.club_love_levels || {},
            "avatarUrl" => profile.avatar_url,
            "createdAt" => profile.created_at&.iso8601,
            "updatedAt" => profile.updated_at&.iso8601
          }
        end

        def identity_verification_json(user, profile)
          profile_status = if profile.blank?
            "not_started"
          elsif profile.legal_last_name.present? && profile.legal_first_name.present? && profile.identity_birth_date.present? && profile.identity_gender.present?
            "profile_entered"
          else
            "incomplete"
          end

          {
            "status" => user.identity_verification_status,
            "profileStatus" => profile_status,
            "provider" => user.identity_provider,
            "providerLabel" => identity_provider_label(user.identity_provider),
            "providerSessionId" => user.identity_verification_id,
            "workflowType" => user.identity_workflow_type,
            "documentType" => user.identity_document_type,
            "verifiedAt" => user.identity_verified_at&.iso8601,
            "externalSessionDeletedAt" => user.identity_external_session_deleted_at&.iso8601,
            "ageVerified" => user.age_verified?,
            "ageOver18" => user.age_over_18?,
            "hasLegalName" => profile.present? && profile.legal_last_name.present? && profile.legal_first_name.present?,
            "hasBirthDate" => profile.present? && profile.identity_birth_date.present?,
            "hasGender" => profile.present? && profile.identity_gender.present?,
            "note" => "本人確認Providerの結果と、プロフィール本人情報の入力状態を表示しています。"
          }
        end

        def admin_safety_registration_json(user)
          missing = user.coconique_safety_missing_requirements

          {
            "canApplyOrPublish" => user.coconique_can_apply_or_publish?,
            "safetyRegisteredAt" => user.safety_registered_at&.iso8601,
            "missingRequirements" => missing,
            "memberType" => user.beta_member_type,
            "isCollaborator" => user.coconique_collaborator_beta?,
            "promoCodeVerified" => user.promo_code_verified?,
            "promoCodeVerifiedAt" => user.promo_code_verified_at&.iso8601,
            "operatorVerificationStatus" => user.operator_verification_status,
            "operatorVerifiedAt" => user.operator_verified_at&.iso8601,
            "phoneVerificationStatus" => user.phone_verification_status,
            "phoneVerifiedAt" => user.phone_verified_at&.iso8601,
            "cardRegistered" => user.card_registered?,
            "cardRegisteredAt" => user.card_registered_at&.iso8601,
            "billingExempted" => user.billing_exempted?,
            "billingExemptedAt" => user.billing_exempted_at&.iso8601
          }
        end

        def admin_billing_json(user)
          {
            "plan" => user.coconique_subscription_plan,
            "status" => user.coconique_subscription_status,
            "billingActive" => user.coconique_billing_active?,
            "startedAt" => user.coconique_subscription_started_at&.iso8601,
            "currentPeriodStartedAt" => user.coconique_subscription_current_period_started_at&.iso8601,
            "currentPeriodEndsAt" => user.coconique_subscription_current_period_ends_at&.iso8601,
            "canceledAt" => user.respond_to?(:coconique_subscription_canceled_at) ? user.coconique_subscription_canceled_at&.iso8601 : nil,
            "founderBetaJoinedAt" => user.coconique_founder_beta_joined_at&.iso8601,
            "cardRegistered" => user.card_registered?,
            "cardRegisteredAt" => user.card_registered_at&.iso8601,
            "billingExempted" => user.billing_exempted?,
            "billingExemptedAt" => user.billing_exempted_at&.iso8601,
            "stripeCustomerId" => user.stripe_customer&.stripe_customer_id,
            "founderBetaInitialPriceJpy" => ::CoconiqueBilling::FOUNDER_BETA_FIRST_MONTH_JPY,
            "founderBetaMonthlyPriceJpy" => ::CoconiqueBilling::FOUNDER_BETA_MONTHLY_JPY
          }
        end

        def admin_host_tickets_json(user)
          balance = ::CreditBalance.find_or_create_for!(user: user, app_key: ::CoconiqueBilling::APP_KEY)

          {
            "balance" => balance.balance,
            "monthlyGrant" => ::CoconiqueBilling::MONTHLY_HOST_TICKET_GRANT,
            "lastGrantedOn" => user.coconique_last_host_ticket_granted_on&.iso8601,
            "additionalTicketPriceJpy" => ::CoconiqueBilling::ADDITIONAL_HOST_TICKET_JPY,
            "additionalTicketExpiresInDays" => ::CoconiqueBilling::ADDITIONAL_HOST_TICKET_EXPIRES_IN_DAYS,
            "additionalTicketPurchaseLimitPerPeriod" => ::CoconiqueBilling::MAX_ADDITIONAL_HOST_TICKET_PURCHASES_PER_PERIOD,
            "additionalTicketPurchasesThisPeriod" => ::CoconiqueBilling.additional_host_ticket_purchases_count(user),
            "additionalTicketPurchaseAvailable" => user.coconique_additional_host_ticket_purchase_available?,
            "currentPeriodStartedAt" => user.coconique_subscription_current_period_started_at&.iso8601,
            "currentPeriodEndsAt" => user.coconique_subscription_current_period_ends_at&.iso8601,
            "canceledAt" => user.respond_to?(:coconique_subscription_canceled_at) ? user.coconique_subscription_canceled_at&.iso8601 : nil,
            "balanceUpdatedAt" => balance.updated_at&.iso8601
          }
        end

        def admin_host_ticket_lot_json(lot)
          {
            "id" => lot.public_id,
            "grantType" => lot.grant_type,
            "totalCount" => lot.total_count,
            "availableCount" => lot.available_count,
            "reservedCount" => lot.reserved_count,
            "consumedCount" => lot.consumed_count,
            "expiredCount" => lot.expired_count,
            "forfeitedCount" => lot.forfeited_count,
            "sourceType" => lot.source_type,
            "sourceId" => lot.source_id,
            "grantedAt" => lot.granted_at&.iso8601,
            "expiresAt" => lot.expires_at&.iso8601,
            "periodStartedAt" => lot.period_started_at&.iso8601,
            "periodEndsAt" => lot.period_ends_at&.iso8601,
            "metadata" => lot.metadata,
            "createdAt" => lot.created_at&.iso8601,
            "updatedAt" => lot.updated_at&.iso8601
          }
        end

        def admin_identity_session_json(session)
          {
            "id" => session.public_id,
            "provider" => session.provider,
            "providerLabel" => identity_provider_label(session.provider),
            "providerSessionId" => session.provider_session_id,
            "status" => session.status,
            "providerStatus" => session.provider_status,
            "workflowType" => session.workflow_type,
            "documentType" => session.document_type,
            "verifiedAt" => session.verified_at&.iso8601,
            "deletedAt" => session.deleted_at&.iso8601,
            "expiresAt" => session.expires_at&.iso8601,
            "createdAt" => session.created_at&.iso8601,
            "updatedAt" => session.updated_at&.iso8601
          }
        end

        def admin_checkout_session_json(session)
          {
            "id" => session.id,
            "productCode" => session.credit_product&.code,
            "productName" => session.credit_product&.name,
            "appKey" => session.credit_product&.app_key,
            "stripeCheckoutSessionId" => session.stripe_checkout_session_id,
            "status" => session.status,
            "amountTotal" => session.amount_total,
            "currency" => session.currency,
            "credits" => session.credits,
            "metadata" => session.metadata,
            "completedAt" => session.completed_at&.iso8601,
            "expiresAt" => session.expires_at&.iso8601,
            "createdAt" => session.created_at&.iso8601,
            "updatedAt" => session.updated_at&.iso8601
          }
        end

        def admin_credit_transaction_json(transaction)
          {
            "id" => transaction.id,
            "appKey" => transaction.app_key,
            "transactionType" => transaction.transaction_type,
            "amount" => transaction.amount,
            "balanceAfter" => transaction.balance_after,
            "description" => transaction.description,
            "sourceType" => transaction.source_type,
            "sourceId" => transaction.source_id,
            "metadata" => transaction.metadata,
            "createdAt" => transaction.created_at&.iso8601,
            "updatedAt" => transaction.updated_at&.iso8601
          }
        end

        def identity_provider_label(provider_key)
          ::Coconique::IdentityVerifications::ProviderFactory.provider_label(provider_key.presence || ::Coconique::IdentityVerifications::ProviderFactory.primary_provider_key)
        rescue StandardError
          provider_key.presence || "本人確認サービス"
        end

        def safety_check_summary_json(setting)
          return { "enabled" => false, "mode" => "off" } if setting.blank?

          {
            "enabled" => setting.effective_enabled?,
            "mode" => setting.mode,
            "startDelayMinutes" => setting.start_delay_minutes,
            "reminderIntervalMinutes" => setting.reminder_interval_minutes,
            "maxReminders" => setting.max_reminders,
            "notifyContactsOnNoResponse" => setting.notify_contacts_on_no_response,
            "notifyContactsOnHelp" => setting.notify_contacts_on_help,
            "shareEventTitle" => setting.share_event_title,
            "shareEventArea" => setting.share_event_area,
            "enabledSince" => setting.enabled_since&.iso8601,
            "disabledAt" => setting.disabled_at&.iso8601,
            "updatedAt" => setting.updated_at&.iso8601
          }
        end

        def emergency_contact_summary_json(contacts)
          records = Array(contacts).map do |contact|
            {
              "id" => contact.public_id,
              "name" => contact.name,
              "email" => contact.email,
              "status" => contact.status,
              "lastInvitedAt" => contact.last_invited_at&.iso8601,
              "approvedAt" => contact.approved_at&.iso8601,
              "revokedAt" => contact.revoked_at&.iso8601
            }
          end

          {
            "count" => records.size,
            "approvedCount" => records.count { |contact| contact["status"] == "approved" },
            "pendingCount" => records.count { |contact| contact["status"] == "pending" },
            "contacts" => records
          }
        end

        def admin_event_json(event)
          {
            "id" => event.public_id,
            "title" => event.title,
            "status" => event.status,
            "categoryKey" => event.category_key,
            "area" => event.area,
            "startsAt" => event.starts_at&.iso8601,
            "endsAt" => event.ends_at&.iso8601,
            "currentParticipants" => event.current_participants,
            "hostTicketReservationStatus" => event.respond_to?(:host_ticket_reservation_status) ? event.host_ticket_reservation_status : nil,
            "hostTicketReservedAt" => event.respond_to?(:host_ticket_reserved_at) ? event.host_ticket_reserved_at&.iso8601 : nil,
            "hostTicketConsumedAt" => event.respond_to?(:host_ticket_consumed_at) ? event.host_ticket_consumed_at&.iso8601 : nil,
            "hostTicketReleasedAt" => event.respond_to?(:host_ticket_released_at) ? event.host_ticket_released_at&.iso8601 : nil,
            "hostTicketForfeitedAt" => event.respond_to?(:host_ticket_forfeited_at) ? event.host_ticket_forfeited_at&.iso8601 : nil,
            "hostTicketReleaseReason" => event.respond_to?(:host_ticket_release_reason) ? event.host_ticket_release_reason : nil,
            "createdAt" => event.created_at&.iso8601
          }
        end

        def admin_participation_json(request)
          {
            "id" => request.public_id,
            "status" => request.status,
            "message" => request.message,
            "attendanceStatus" => request.attendance_status,
            "attendanceRecordedAt" => request.attendance_recorded_at&.iso8601,
            "createdAt" => request.created_at&.iso8601,
            "event" => admin_event_json(request.coconique_event)
          }
        end

        def admin_report_brief_json(report)
          {
            "id" => report.public_id,
            "createdAt" => report.created_at&.iso8601,
            "targetType" => report.target_type,
            "reason" => report.reason,
            "status" => report.status,
            "severity" => report.severity,
            "eventStatusAtReport" => report.event_status_at_report,
            "reportPhase" => report.report_phase,
            "otherUser" => admin_user_brief_json(report.reporter_id == report.reported_user_id ? nil : (report.reporter || report.reported_user)),
            "event" => report.coconique_event && admin_event_json(report.coconique_event)
          }
        end

        def admin_restriction_json(restriction)
          {
            "id" => restriction.public_id,
            "status" => restriction.status,
            "reason" => restriction.reason,
            "note" => restriction.note,
            "startsAt" => restriction.starts_at&.iso8601,
            "endsAt" => restriction.ends_at&.iso8601,
            "liftedAt" => restriction.lifted_at&.iso8601,
            "active" => restriction.active_now?,
            "createdAt" => restriction.created_at&.iso8601,
            "createdByAdmin" => admin_user_brief_json(restriction.created_by_admin),
            "liftedByAdmin" => admin_user_brief_json(restriction.lifted_by_admin),
            "report" => restriction.coconique_report && admin_report_brief_json(restriction.coconique_report)
          }
        end


        def admin_user_block_json(block)
          return nil if block.blank?

          {
            "id" => block.public_id,
            "reason" => block.reason,
            "reasonLabel" => CoconiqueUserBlock::REASON_LABELS[block.reason] || CoconiqueUserBlock::REASON_LABELS["other"],
            "note" => block.note,
            "active" => block.active?,
            "createdAt" => block.created_at&.iso8601,
            "liftedAt" => block.lifted_at&.iso8601,
            "blocker" => admin_user_brief_json(block.blocker),
            "blocked" => admin_user_brief_json(block.blocked),
            "liftedBy" => admin_user_brief_json(block.lifted_by),
            "report" => block.coconique_report && admin_report_brief_json(block.coconique_report)
          }
        end

        def admin_feedback_json(feedback)
          {
            "id" => feedback.public_id,
            "safetyAnswer" => feedback.safety_answer,
            "accuracyAnswer" => feedback.accuracy_answer,
            "joinAgainAnswer" => feedback.join_again_answer,
            "privateNote" => feedback.private_note,
            "status" => feedback.status,
            "publicCountable" => feedback.public_countable,
            "needsSupportFollowup" => feedback.needs_support_followup?,
            "createdAt" => feedback.created_at&.iso8601,
            "event" => admin_event_json(feedback.coconique_event),
            "user" => admin_user_brief_json(feedback.user),
            "host" => admin_user_brief_json(feedback.host)
          }
        end

        def admin_note_json(note)
          {
            "id" => note.public_id,
            "body" => note.body,
            "createdAt" => note.created_at&.iso8601,
            "adminUser" => admin_user_brief_json(note.admin_user)
          }
        end

        def admin_membership_json(membership)
          {
            "id" => membership.id,
            "appKey" => membership.app_key,
            "status" => membership.status,
            "startedAt" => membership.started_at&.iso8601,
            "createdAt" => membership.created_at&.iso8601
          }
        end

        def admin_terms_acceptance_json(acceptance)
          {
            "id" => acceptance.id,
            "appKey" => acceptance.app_key,
            "termsVersion" => acceptance.terms_version,
            "privacyVersion" => acceptance.privacy_version,
            "acceptedAt" => acceptance.accepted_at&.iso8601
          }
        end

        def auth_session_json(session)
          {
            "id" => session.id,
            "userId" => session.user_id,
            "expiresAt" => session.expires_at&.iso8601,
            "revokedAt" => session.revoked_at&.iso8601,
            "ipAddress" => session.ip_address,
            "userAgent" => session.user_agent,
            "createdAt" => session.created_at&.iso8601,
            "active" => session.revoked_at.nil? && session.expires_at.future?
          }
        end

        def admin_user_brief_json(user)
          return nil if user.blank?

          profile = user.user_profile
          {
            "id" => user.id.to_s,
            "email" => user.email,
            "displayName" => profile&.display_name || user.email.to_s.split("@").first,
            "avatarUrl" => profile&.avatar_url,
            "status" => user.status,
            "role" => user.role
          }
        end
      end
    end
  end
end
