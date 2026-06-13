module Api
  module V1
    module Coconique
      class BaseController < ApplicationController
        EVENT_INPUT_TIME_ZONE = ActiveSupport::TimeZone["Asia/Tokyo"]

        before_action :require_login!
        before_action :finish_due_coconique_events!
        before_action :sync_coconique_safety_check_sessions!

        private


        def finish_due_coconique_events!
          current_user&.sync_coconique_host_tickets! if current_user&.persisted?
          CoconiqueEvent.finish_due_events!
        rescue StandardError => e
          Rails.logger.warn("[CoconiqueEvent] finish_due_events failed: #{e.class} #{e.message}")
          nil
        end

        def sync_coconique_safety_check_sessions!
          CoconiqueSafetyCheckSession.create_due_sessions!
          CoconiqueSafetyCheckSession.process_due_notifications!
        rescue NameError
          # 安全確認系のmigration前でも既存機能を止めない。
          nil
        rescue ActiveRecord::StatementInvalid => e
          Rails.logger.warn("[CoconiqueSafetyCheckSession] sync skipped: #{e.class} #{e.message}")
          nil
        rescue StandardError => e
          Rails.logger.warn("[CoconiqueSafetyCheckSession] sync failed: #{e.class} #{e.message}")
          nil
        end

        def find_event!
          public_id = params[:event_public_id] || params[:chat_room_event_id] || params[:event_id] || params[:public_id] || params[:id]
          CoconiqueEvent.find_by!(public_id: public_id)
        end

        def find_participation_request!
          value = params[:participation_request_id] || params[:public_id] || params[:id]
          CoconiqueParticipationRequest.find_by!(public_id: value)
        rescue ActiveRecord::RecordNotFound
          CoconiqueParticipationRequest.find(value)
        end

        def favorite_events_for_current_user
          # 「気になる」は参加申請・承認後もユーザー本人が見返せる保存リストとして扱う。
          # ただし、募集停止・キャンセル・終了・募集期間終了など、参加者向けに表示できない予定は
          # ordered_for_dashboard 側で除外する。
          events_without_enryo_scope(current_user.favorite_coconique_events.ordered_for_dashboard)
        end

        def require_event_host!(event)
          return true if current_user.admin? || event.hosted_by?(current_user)

          render_error(
            code: "FORBIDDEN",
            message: "この予定を管理する権限がありません。",
            status: :forbidden
          )

          false
        end

        def require_request_owner_or_event_host!(participation_request)
          return true if current_user.admin?
          return true if participation_request.user_id == current_user.id
          return true if participation_request.coconique_event.hosted_by?(current_user)

          render_error(
            code: "FORBIDDEN",
            message: "この申請を確認する権限がありません。",
            status: :forbidden
          )

          false
        end

        def enryo_related_user_ids
          @enryo_related_user_ids ||= CoconiqueUserBlock.related_user_ids_for(current_user)
        rescue NameError, ActiveRecord::StatementInvalid
          []
        end

        def enryo_between?(other_user)
          return false if current_user.blank? || other_user.blank? || current_user.id == other_user.id

          CoconiqueUserBlock.blocked_between?(current_user, other_user)
        rescue NameError, ActiveRecord::StatementInvalid
          false
        end

        def events_without_enryo_scope(scope)
          scoped = apply_member_visibility_scope(scope)

          # 運営により一部制限・一時凍結・垢BANされたユーザーの公開中募集は、
          # 既存データのキャンセル処理がまだ走っていない場合でも参加者向けには表示しない。
          restricted_host_ids = CoconiqueUserRestriction.active.select(:user_id)
          scoped = scoped.where.not(host_id: restricted_host_ids)

          ids = enryo_related_user_ids
          return scoped if ids.blank?

          # 遠慮設定中の相手が主催する募集だけでなく、
          # その相手がすでに参加確定している募集も参加者向け一覧から外す。
          blocked_participation_event_ids = CoconiqueParticipationRequest.approved
            .where(user_id: ids)
            .select(:coconique_event_id)

          scoped.where.not(host_id: ids).where.not(id: blocked_participation_event_ids)
        end

        def apply_member_visibility_scope(scope)
          return scope if current_user&.admin?

          profile = current_user&.user_profile
          gender = profile&.identity_gender.to_s
          age_labels = same_generation_public_age_labels_for(profile&.public_age_label)

          scoped = scope.left_outer_joins(host: :user_profile)
          member_conditions = []
          values = { current_user_id: current_user&.id }

          if %w[female male other].include?(gender)
            member_conditions << "COALESCE(coconique_events.same_gender_only, FALSE) = FALSE OR user_profiles.identity_gender = :identity_gender"
            values[:identity_gender] = gender
          else
            member_conditions << "COALESCE(coconique_events.same_gender_only, FALSE) = FALSE"
          end

          if age_labels.present?
            member_conditions << "COALESCE(coconique_events.same_generation_only, FALSE) = FALSE OR user_profiles.public_age_label IN (:same_generation_labels)"
            values[:same_generation_labels] = age_labels
          else
            member_conditions << "COALESCE(coconique_events.same_generation_only, FALSE) = FALSE"
          end

          # 自分が主催する募集は条件に関係なく表示し、
          # 他ユーザーの募集は「同性限定」「同年代限定」の両条件に合う場合だけ表示する。
          member_visibility_sql = member_conditions.map { |condition| "(#{condition})" }.join(" AND ")
          scoped.where("coconique_events.host_id = :current_user_id OR (#{member_visibility_sql})", values)
        rescue ActiveRecord::StatementInvalid => e
          Rails.logger.warn("[CoconiqueEvent] member visibility scope skipped: #{e.class} #{e.message}")
          scope
        end

        def same_generation_public_age_labels_for(label)
          case label.to_s
          when "early_20s", "late_20s" then %w[early_20s late_20s]
          when "early_30s", "late_30s" then %w[early_30s late_30s]
          when "early_40s", "late_40s" then %w[early_40s late_40s]
          when "50s" then %w[50s]
          when "60s_or_over" then %w[60s_or_over]
          else []
          end
        end

        def event_matches_member_visibility?(event, user = current_user)
          return true if user.blank? || user.admin? || event.hosted_by?(user)

          profile = user.user_profile
          host_profile = event.host&.user_profile

          if event.same_gender_only?
            return false unless %w[female male other].include?(profile&.identity_gender.to_s)
            return false unless profile.identity_gender == host_profile&.identity_gender
          end

          if event.same_generation_only?
            user_labels = same_generation_public_age_labels_for(profile&.public_age_label)
            return false if user_labels.blank?
            return false unless user_labels.include?(host_profile&.public_age_label.to_s)
          end

          true
        end

        def require_event_member_visibility_match!(event)
          return true if event_matches_member_visibility?(event)

          render_error(
            code: "COCONIQUE_EVENT_MEMBER_CONDITION_NOT_MATCHED",
            message: "この募集は募集条件に当てはまるメンバーにのみ表示されています。",
            status: :forbidden
          )

          false
        end

        def event_has_enryo_participant?(event)
          ids = enryo_related_user_ids
          return false if ids.blank?

          event.coconique_participation_requests.approved.where(user_id: ids).exists?
        end

        def require_not_enryo_user!(user, message: "このメンバーとは遠慮設定中のため、この操作はできません。")
          return true unless enryo_between?(user)

          render_error(
            code: "COCONIQUE_USER_BLOCKED",
            message: message,
            status: :forbidden
          )

          false
        end

        def require_not_enryo_event!(event)
          return false unless require_event_member_visibility_match!(event)
          return false unless require_not_enryo_user!(event.host, message: "この募集の主催メンバーとは遠慮設定中のため、この操作はできません。")

          return true unless event_has_enryo_participant?(event)

          render_error(
            code: "COCONIQUE_EVENT_HAS_BLOCKED_MEMBER",
            message: "遠慮設定中のメンバーが参加予定のため、この募集には参加申請できません。",
            status: :forbidden
          )

          false
        end

        def require_coconique_safety_registration!(action_kind:, event: nil)
          return true if current_user&.coconique_can_apply_or_publish?

          render_safety_registration_required!(action_kind: action_kind, event: event)
          false
        end

        def render_safety_registration_required!(action_kind:, event: nil)
          render json: {
            ok: false,
            error: {
              code: "COCONIQUE_SAFETY_REGISTRATION_REQUIRED",
              message: "この機能を利用するには、初回のみ安全登録が必要です。電話番号確認と本人確認を完了してください。"
            },
            data: {
              safety_registration: serialize_coconique_safety_registration_status(current_user),
              action_kind: action_kind,
              event_id: event&.public_id
            }
          }, status: :forbidden
        end

        def require_host_ticket_available!(event: nil)
          return true if event&.host_ticket_reserved? || event&.host_ticket_consumed?
          current_user.sync_coconique_host_tickets! if current_user.respond_to?(:sync_coconique_host_tickets!)
          return true if current_user.coconique_host_ticket_balance.positive?

          render_error(
            code: "COCONIQUE_HOST_TICKET_REQUIRED",
            message: "募集を公開するには主催チケットが1枚必要です。月5枚の主催チケットを使い切った場合は、追加チケットを購入してください。",
            status: :payment_required,
            data: {
              host_ticket_balance: current_user.coconique_host_ticket_balance,
              monthly_host_ticket_grant: CoconiqueBilling::MONTHLY_HOST_TICKET_GRANT,
              additional_host_ticket_price_jpy: CoconiqueBilling::ADDITIONAL_HOST_TICKET_JPY,
              additional_host_ticket_expires_in_days: CoconiqueBilling::ADDITIONAL_HOST_TICKET_EXPIRES_IN_DAYS,
              additional_host_ticket_purchase_available: current_user.coconique_additional_host_ticket_purchase_available?,
              additional_host_ticket_purchase_limit_per_period: CoconiqueBilling::MAX_ADDITIONAL_HOST_TICKET_PURCHASES_PER_PERIOD,
              additional_host_ticket_purchases_this_period: CoconiqueBilling.additional_host_ticket_purchases_count(current_user)
            }
          )

          false
        end

        def consume_host_ticket_for_event!(event)
          return true if event.host_ticket_reserved? || event.host_ticket_consumed?

          CoconiqueBilling.reserve_host_ticket_for_event!(event: event, user: current_user)
          true
        rescue CoconiqueBilling::InsufficientHostTickets
          render_error(
            code: "COCONIQUE_HOST_TICKET_REQUIRED",
            message: "募集を公開するには主催チケットが1枚必要です。月5枚の主催チケットを使い切った場合は、追加チケットを購入してください。",
            status: :payment_required,
            data: {
              host_ticket_balance: current_user.coconique_host_ticket_balance,
              monthly_host_ticket_grant: CoconiqueBilling::MONTHLY_HOST_TICKET_GRANT,
              additional_host_ticket_price_jpy: CoconiqueBilling::ADDITIONAL_HOST_TICKET_JPY,
              additional_host_ticket_expires_in_days: CoconiqueBilling::ADDITIONAL_HOST_TICKET_EXPIRES_IN_DAYS,
              additional_host_ticket_purchase_available: current_user.coconique_additional_host_ticket_purchase_available?,
              additional_host_ticket_purchase_limit_per_period: CoconiqueBilling::MAX_ADDITIONAL_HOST_TICKET_PURCHASES_PER_PERIOD,
              additional_host_ticket_purchases_this_period: CoconiqueBilling.additional_host_ticket_purchases_count(current_user)
            }
          )

          false
        end

        def serialize_coconique_safety_registration_status(user)
          collaborator = user.coconique_collaborator_beta?
          missing = user.coconique_safety_missing_requirements

          {
            "canApplyOrPublish" => user.coconique_can_apply_or_publish?,
            "memberType" => user.beta_member_type,
            "isCollaborator" => collaborator,
            "requiresIdentity" => !collaborator,
            "accountStatus" => user.status,
            "emailVerified" => user.email_verified?,
            "cardRegistered" => user.card_registered?,
            "billingExempted" => user.billing_exempted?,
            "billingActive" => user.coconique_billing_active?,
            "subscriptionStatus" => user.coconique_subscription_status,
            "subscriptionPlan" => user.coconique_subscription_plan,
            "subscriptionStartedAt" => user.coconique_subscription_started_at&.iso8601,
            "currentPeriodStartedAt" => user.coconique_subscription_current_period_started_at&.iso8601,
            "currentPeriodEndsAt" => user.coconique_subscription_current_period_ends_at&.iso8601,
            "founderBetaJoinedAt" => user.coconique_founder_beta_joined_at&.iso8601,
            "hostTicketBalance" => user.persisted? ? user.coconique_host_ticket_balance : 0,
            "monthlyHostTicketGrant" => CoconiqueBilling::MONTHLY_HOST_TICKET_GRANT,
            "additionalHostTicketPriceJpy" => CoconiqueBilling::ADDITIONAL_HOST_TICKET_JPY,
            "additionalHostTicketExpiresInDays" => CoconiqueBilling::ADDITIONAL_HOST_TICKET_EXPIRES_IN_DAYS,
            "additionalHostTicketPurchaseAvailable" => user.persisted? ? user.coconique_additional_host_ticket_purchase_available? : false,
            "additionalHostTicketPurchaseLimitPerPeriod" => CoconiqueBilling::MAX_ADDITIONAL_HOST_TICKET_PURCHASES_PER_PERIOD,
            "additionalHostTicketPurchasesThisPeriod" => user.persisted? ? CoconiqueBilling.additional_host_ticket_purchases_count(user) : 0,
            "promoCodeVerified" => user.promo_code_verified?,
            "phoneVerified" => user.phone_verified?,
            "phoneVerificationStatus" => user.phone_verification_status,
            "phoneVerifiedAt" => user.phone_verified_at&.iso8601,
            "identityVerified" => user.identity_verified?,
            "identityVerificationStatus" => user.identity_verification_status,
            "identityProvider" => user.identity_provider,
            "identityProviderPrimary" => ::Coconique::IdentityVerifications::ProviderFactory.primary_provider_key,
            "identityProviderFallback" => ::Coconique::IdentityVerifications::ProviderFactory.fallback_provider_key,
            "identityProviderLabel" => ::Coconique::IdentityVerifications::ProviderFactory.provider_label(::Coconique::IdentityVerifications::ProviderFactory.primary_provider_key),
            "identityWorkflowType" => user.respond_to?(:identity_workflow_type) ? user.identity_workflow_type : nil,
            "identityDocumentType" => user.respond_to?(:identity_document_type) ? user.identity_document_type : nil,
            "myNumberIdentityEnabled" => ::Coconique::IdentityVerifications::ProviderFactory.my_number_enabled_for_current_provider?,
            "identityVerifiedAt" => user.identity_verified_at&.iso8601,
            "ageVerified" => user.age_verified?,
            "ageOver18" => user.age_over_18?,
            "operatorVerificationStatus" => user.operator_verification_status,
            "operatorVerified" => user.beta_operator_verified?,
            "operatorVerifiedAt" => user.operator_verified_at&.iso8601,
            "safetyRegisteredAt" => user.safety_registered_at&.iso8601,
            "missingRequirements" => missing,
            "nextStep" => safety_registration_next_step_for(user, missing),
            "badges" => safety_registration_badges_for(user)
          }
        end

        def safety_registration_next_step_for(user, missing)
          return "complete" if missing.blank?
          return "email" if missing.include?("email")
          return "card" if missing.include?("card") || missing.include?("subscription")
          return "promo_code" if missing.include?("promo_code")
          return "phone" if missing.include?("phone")
          return "identity" if missing.include?("identity") || missing.include?("age_over_18")
          return "account_status" if missing.include?("account_status")

          missing.first
        end

        def safety_registration_badges_for(user)
          badges = []
          badges << { "key" => "phone_verified", "label" => "電話番号確認済み" } if user.phone_verified?
          badges << { "key" => "identity_verified", "label" => "本人確認済み" } if user.identity_verified?
          badges << { "key" => "beta_collaborator", "label" => "β協力メンバー" } if user.coconique_collaborator_beta?
          badges << { "key" => "operator_verified", "label" => "運営確認済み" } if user.beta_operator_verified?
          badges << { "key" => "founder", "label" => "Founder" } if user.coconique_subscription_plan.to_s == "founder_beta" && user.coconique_billing_active?
          badges
        end


        def serialize_event(event, include_user_context: true, visibility: :auto)
          request_for_user = include_user_context ? event.participation_request_for(current_user) : nil
          effective_visibility = resolve_event_visibility(event, request_for_user, visibility)

          payload = base_event_payload(event, include_user_context: include_user_context, request_for_user: request_for_user)

          case effective_visibility
          when :public_card
            payload
          when :public_detail
            payload.merge(public_event_detail_payload(event, meeting_place_hidden: true))
          else
            payload.merge(full_event_payload(event, meeting_place_hidden: false))
          end
        end

        def serialize_event_card(event, include_user_context: true)
          serialize_event(event, include_user_context: include_user_context, visibility: :public_card)
        end

        def serialize_host_event(event)
          serialize_event(event, include_user_context: true, visibility: :full)
        end

        def resolve_event_visibility(event, request_for_user, requested_visibility)
          return requested_visibility unless requested_visibility == :auto
          return :full if event.hosted_by?(current_user) || current_user&.admin?
          return :full if request_for_user&.approved? && current_user&.coconique_can_apply_or_publish?

          :public_detail
        end

        def base_event_payload(event, include_user_context:, request_for_user: nil)
          {
            "id" => event.public_id,
            "title" => event.title,
            "categoryKey" => event.category_key,
            "area" => event.area,
            "areaPrefecture" => event.respond_to?(:area_prefecture) ? event.area_prefecture : nil,
            "areaCity" => event.respond_to?(:area_city) ? event.area_city : nil,
            "startsAt" => event.starts_at&.iso8601,
            "endsAt" => event.ends_at&.iso8601,
            "imageUrl" => event.image_url,
            "capacity" => event.capacity,
            "minParticipants" => event.min_participants,
            "currentParticipants" => event.current_participants,
            "interestedCount" => event.interested_count,
            "costLabel" => event.cost_label,
            "hostDisplayName" => event.host_display_name,
            "hostAgeGroup" => event.host_age_group,
            "hostUserId" => event.host_id&.to_s,
            "summary" => event.summary,
            "status" => event.status,
            "isFavorite" => include_user_context ? event.favorited_by?(current_user) : false,
            "requestStatus" => blocking_request_status_for(request_for_user),
            "isHostedByCurrentUser" => event.hosted_by?(current_user),
            "isEnryoWithHost" => include_user_context ? enryo_between?(event.host) : false,
            "sameGenderOnly" => event.same_gender_only?,
            "sameGenerationOnly" => event.same_generation_only?,
            "hostTicketConsumedAt" => event.respond_to?(:host_ticket_consumed_at) ? event.host_ticket_consumed_at&.iso8601 : nil,
            "hostTicketReservationStatus" => event.respond_to?(:host_ticket_reservation_status) ? event.host_ticket_reservation_status : nil,
            "hostTicketReservedAt" => event.respond_to?(:host_ticket_reserved_at) ? event.host_ticket_reserved_at&.iso8601 : nil,
            "hostTicketReleasedAt" => event.respond_to?(:host_ticket_released_at) ? event.host_ticket_released_at&.iso8601 : nil,
            "memberConditionMatched" => include_user_context ? event_matches_member_visibility?(event) : true
          }
        end

        def blocking_request_status_for(participation_request)
          return nil if participation_request.blank?
          return participation_request.status if participation_request.pending? || participation_request.approved? || participation_request.rejected?

          nil
        end

        def public_event_detail_payload(event, meeting_place_hidden: true)
          {
            "meetingPlaceIsHidden" => meeting_place_hidden,
            "imageUrls" => event.image_urls.presence || Array(event.image_url).compact,
            "dressCode" => event.dress_code,
            "hostMessage" => event.host_message,
            "recruitmentEndsAt" => event.recruitment_ends_at&.iso8601,
            "targetMembers" => event.target_members || [],
            "isPublicGamblingWatching" => event.is_public_gambling_watching,
            "requiresAge20Verified" => event.requires_age20_verified,
            "sameGenderOnly" => event.same_gender_only?,
            "sameGenerationOnly" => event.same_generation_only?
          }
        end

        def full_event_payload(event, meeting_place_hidden:)
          public_event_detail_payload(event, meeting_place_hidden: meeting_place_hidden).merge(
            "meetingPlace" => meeting_place_hidden ? nil : event.meeting_place,
            "referenceUrl" => event.reference_url,
            "publishedAt" => event.published_at&.iso8601,
            "closedAt" => event.closed_at&.iso8601,
            "canceledAt" => event.canceled_at&.iso8601,
            "finishedAt" => event.finished_at&.iso8601,
            "cancellationReason" => event.cancellation_reason,
            "createdAt" => event.created_at&.iso8601,
            "updatedAt" => event.updated_at&.iso8601,
            "statusHistory" => serialize_event_status_history(event)
          )
        end

        def serialize_event_status_history(event)
          return [] unless event.hosted_by?(current_user) || current_user&.admin?

          event.coconique_event_status_logs.order(created_at: :desc).limit(30).map do |log|
            {
              "id" => log.id.to_s,
              "action" => log.action,
              "fromStatus" => log.from_status,
              "toStatus" => log.to_status,
              "reason" => log.reason,
              "createdAt" => log.created_at&.iso8601,
              "userDisplayName" => log.user&.user_profile&.display_name || log.user&.email&.split("@")&.first
            }
          end
        end

        def meeting_place_hidden?(event, request_for_user)
          return false if event.hosted_by?(current_user) || current_user&.admin?
          return false if request_for_user&.approved?

          true
        end

        def require_publicly_available_event!(event)
          return true if event.visible_to_members_status? && event.recruitment_open?

          message = case event.status
          when "closed"
            "この募集は停止されました。"
          when "canceled"
            "この募集はキャンセルされました。"
          when "finished"
            "この募集は終了しました。"
          else
            if event.visible_to_members_status? && !event.recruitment_open?
              "この募集は締め切られました。"
            else
              "この募集は現在表示できません。"
            end
          end

          render_error(
            code: "EVENT_NOT_AVAILABLE",
            message: message,
            status: :unprocessable_entity
          )

          false
        end

        def require_joinable_event!(event)
          return false unless require_publicly_available_event!(event)

          if event.hosted_by?(current_user)
            render_error(
              code: "OWN_EVENT_NOT_JOINABLE",
              message: "自分が主催する募集には参加申請できません。",
              status: :unprocessable_entity
            )

            return false
          end

          if event.current_participants >= event.capacity
            render_error(
              code: "EVENT_FULL",
              message: "この募集は定員に達しています。",
              status: :unprocessable_entity
            )

            return false
          end

          true
        end

        def require_pending_request!(participation_request, message: "この申請は現在変更できません。")
          return true if participation_request.pending?

          render_error(
            code: "PARTICIPATION_REQUEST_NOT_PENDING",
            message: message,
            status: :unprocessable_entity
          )

          false
        end

        def serialize_participation_request_summary(participation_request)
          event = participation_request.coconique_event
          viewer_role = participation_request_viewer_role(participation_request)

          {
            "id" => participation_request.public_id.presence || participation_request.id.to_s,
            "eventId" => event.public_id,
            "event" => serialize_event_card(event),
            "status" => participation_request.status,
            "reviewedAt" => participation_request.reviewed_at&.iso8601,
            "withdrawnAt" => participation_request.withdrawn_at&.iso8601,
            "attendanceStatus" => participation_request.attendance_status,
            "attendanceRecordedAt" => participation_request.attendance_recorded_at&.iso8601,
            "createdAt" => participation_request.created_at&.iso8601,
            "updatedAt" => participation_request.updated_at&.iso8601,
            "viewerRole" => viewer_role,
            "canWithdraw" => viewer_role == "participant" && participation_request.pending?,
            "canEditMessage" => viewer_role == "participant" && participation_request.pending?,
            "canApprove" => ["host", "admin"].include?(viewer_role) && participation_request.pending?,
            "canReject" => ["host", "admin"].include?(viewer_role) && participation_request.pending?,
            "user" => serialize_participation_request_user(participation_request.user)
          }
        end

        def serialize_participation_request_detail(participation_request)
          event = participation_request.coconique_event
          viewer_role = participation_request_viewer_role(participation_request)

          serialize_participation_request_summary(participation_request).merge(
            "event" => serialize_event(event),
            "message" => participation_request.message,
            "attendanceNote" => participation_request.attendance_note,
            "attendanceRecordedByDisplayName" => attendance_recorded_by_display_name(participation_request),
            "reviewedByDisplayName" => reviewer_display_name(participation_request),
            "viewerRole" => viewer_role,
            "user" => serialize_participation_request_user(participation_request.user, include_context: true)
          )
        end

        # 後方互換用。詳細系レスポンスではこのメソッドを使う。
        def serialize_participation_request(participation_request)
          serialize_participation_request_detail(participation_request)
        end

        def serialize_participation_request_user(user, include_context: false)
          profile = user.user_profile
          payload = {
            "id" => user.id.to_s,
            "displayName" => profile&.display_name || user.email.split("@").first,
            "profilePath" => "/app/members/#{user.id}",
            "avatarUrl" => profile&.avatar_url
          }

          return payload unless include_context

          payload.merge(
            "locale" => profile&.locale,
            "timezone" => profile&.timezone
          )
        end

        def participation_request_viewer_role(participation_request)
          return "admin" if current_user&.admin?
          return "host" if participation_request.coconique_event.hosted_by?(current_user)
          return "participant" if participation_request.user_id == current_user&.id

          "unknown"
        end

        def serialize_member_profile(user)
          profile = user.user_profile
          is_enryo = enryo_between?(user)
          if is_enryo && current_user&.id != user.id && !current_user&.admin?
            return {
              "id" => user.id.to_s,
              "displayName" => profile&.display_name.presence || "ココニークメンバー",
              "avatarUrl" => profile&.avatar_url,
              "headline" => "遠慮設定中のメンバーです",
              "publicAgeLabel" => nil,
              "bio" => nil,
              "interestCategoryKeys" => [],
              "participationStyleKeys" => [],
              "preferredAreas" => [],
              "conversationTopics" => [],
              "communicationPreferences" => [],
              "joinedAt" => nil,
              "emailVerified" => nil,
              "hostedEventsCount" => 0,
              "approvedParticipationsCount" => 0,
              "favoriteCategoryKeys" => [],
              "feedbackSummary" => CoconiqueFeedback.empty_public_summary,
              "viewerRelationship" => "blocked",
              "isEnryo" => true,
              "publicHostedEvents" => []
            }
          end

          public_hosted_events = events_without_enryo_scope(user.hosted_coconique_events.ordered_for_dashboard).limit(6)
          approved_requests = user.coconique_participation_requests.approved.includes(:coconique_event)
          favorite_category_keys = favorite_category_keys_for(user, public_hosted_events, approved_requests)

          {
            "id" => user.id.to_s,
            "displayName" => profile&.display_name.presence || user.email.to_s.split("@").first,
            "avatarUrl" => profile&.avatar_url,
            "headline" => profile&.profile_headline.presence || "ココニークメンバー",
            "publicAgeLabel" => profile&.public_age_label,
            "bio" => profile&.bio,
            "interestCategoryKeys" => profile&.interest_category_keys || [],
            "participationStyleKeys" => profile&.participation_style_keys || [],
            "preferredAreas" => profile&.preferred_areas || [],
            "conversationTopics" => profile&.conversation_topics || [],
            "communicationPreferences" => profile&.communication_preferences || [],
            "joinedAt" => user.created_at&.iso8601,
            "emailVerified" => user.email_verified?,
            "hostedEventsCount" => user.hosted_coconique_events.visible_to_members.count,
            "approvedParticipationsCount" => user.coconique_participation_requests.approved.count,
            "favoriteCategoryKeys" => favorite_category_keys,
            "feedbackSummary" => CoconiqueFeedback.public_summary_for_host(user),
            "viewerRelationship" => viewer_relationship_to(user),
            "isEnryo" => is_enryo,
            "publicHostedEvents" => public_hosted_events.map { |event| serialize_event_card(event, include_user_context: false) }
          }
        end

        def favorite_category_keys_for(user, public_hosted_events, approved_requests)
          category_keys = public_hosted_events.map(&:category_key) + approved_requests.map { |request| request.coconique_event&.category_key }
          category_keys.compact.tally.sort_by { |_key, count| -count }.map(&:first).first(5)
        end

        def viewer_relationship_to(user)
          return "self" if current_user&.id == user.id

          if user.hosted_coconique_events.joins(:coconique_participation_requests).where(coconique_participation_requests: { user_id: current_user&.id }).exists?
            return "host"
          end

          if current_user&.hosted_coconique_events&.joins(:coconique_participation_requests)&.where(coconique_participation_requests: { user_id: user.id })&.exists?
            return "participant"
          end

          "member"
        end

        def reviewer_display_name(participation_request)
          reviewer = participation_request.reviewed_by
          return nil if reviewer.blank?

          reviewer.user_profile&.display_name || reviewer.email.split("@").first
        end

        def attendance_recorded_by_display_name(participation_request)
          recorder = participation_request.attendance_recorded_by
          return nil if recorder.blank?

          recorder.user_profile&.display_name || recorder.email.split("@").first
        end


        def serialize_emergency_contact(contact)
          {
            "id" => contact.public_id,
            "name" => contact.name,
            "email" => contact.email,
            "status" => contact.status,
            "lastInvitedAt" => contact.last_invited_at&.iso8601,
            "approvedAt" => contact.approved_at&.iso8601,
            "rejectedAt" => contact.rejected_at&.iso8601,
            "revokedAt" => contact.revoked_at&.iso8601,
            "createdAt" => contact.created_at&.iso8601,
            "updatedAt" => contact.updated_at&.iso8601
          }
        end

        def serialize_safety_check_setting(setting)
          {
            "enabled" => setting.enabled,
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

        def serialize_safety_check_session(session)
          event = session.coconique_event

          {
            "id" => session.public_id,
            "eventId" => event.public_id,
            "event" => serialize_event_card(event),
            "role" => session.role,
            "status" => session.status,
            "responseKind" => safety_response_kind_for(session),
            "dueAt" => session.due_at&.iso8601,
            "nextReminderAt" => session.next_reminder_at&.iso8601,
            "remindersSentCount" => session.reminders_sent_count,
            "maxReminders" => session.max_reminders,
            "reminderIntervalMinutes" => session.reminder_interval_minutes,
            "extendedCount" => session.extended_count,
            "maxExtensions" => CoconiqueSafetyCheckSession::MAX_EXTENSIONS,
            "answeredAt" => session.answered_at&.iso8601,
            "escalatedAt" => session.escalated_at&.iso8601,
            "helpNote" => session.help_note,
            "notifyContactsOnNoResponse" => session.notify_contacts_on_no_response?,
            "notifyContactsOnHelp" => session.notify_contacts_on_help?,
            "shareEventTitle" => session.share_event_title?,
            "shareEventArea" => session.share_event_area?,
            "createdAt" => session.created_at&.iso8601,
            "updatedAt" => session.updated_at&.iso8601
          }
        end

        def safety_response_kind_for(session)
          return "safe" if session.responded_safe?
          return "extended" if session.responded_extended?
          return "help" if session.responded_help?

          nil
        end

        def require_publishable_event!(event)
          errors = publishable_errors_for(event)
          return true if errors.blank?

          render_error(
            code: "EVENT_NOT_PUBLISHABLE",
            message: "公開に必要な入力内容を確認してください。#{errors.join(' / ')}",
            status: :unprocessable_entity
          )

          false
        end

        def publishable_errors_for(event)
          errors = []
          errors << "タイトルを入力してください" if event.title.blank? || event.title == "無題の予定"
          errors << "カテゴリを選択してください" if event.category_key.blank?
          errors << "予定説明を入力してください" if event.summary.blank?
          errors << "集合場所を入力してください" if event.meeting_place.blank? || event.meeting_place == "未設定"
          errors << "開始日時を未来にしてください" if event.starts_at.blank? || event.starts_at <= Time.current
          errors << "終了日時は開始日時より後にしてください" if event.starts_at.present? && event.ends_at.present? && event.ends_at <= event.starts_at
          errors << "募集締切を入力してください" if event.recruitment_ends_at.blank?
          errors << "募集締切は現在時刻より後にしてください" if event.recruitment_ends_at.present? && event.recruitment_ends_at <= Time.current
          errors << "募集締切は開始日時より前にしてください" if event.recruitment_ends_at.present? && event.starts_at.present? && event.recruitment_ends_at >= event.starts_at
          errors << "最少開催人数は定員以下にしてください" if event.min_participants.present? && event.capacity.present? && event.min_participants > event.capacity
          errors
        end

        def event_attributes_from_params
          permitted = params.permit(
            :title,
            :categoryKey,
            :category_key,
            :area,
            :areaPrefecture,
            :area_prefecture,
            :areaCity,
            :area_city,
            :startsAt,
            :starts_at,
            :endsAt,
            :ends_at,
            :meetingPlace,
            :meeting_place,
            :imageUrl,
            :image_url,
            :capacity,
            :minParticipants,
            :min_participants,
            :recruitmentEndsAt,
            :recruitment_ends_at,
            :summary,
            :referenceUrl,
            :reference_url,
            :costLabel,
            :cost_label,
            :dressCode,
            :dress_code,
            :hostMessage,
            :host_message,
            :hostAgeGroup,
            :host_age_group,
            :rulesAccepted,
            :rules_accepted,
            :sameGenderOnly,
            :same_gender_only,
            :sameGenerationOnly,
            :same_generation_only,
            targetMembers: [],
            imageUrls: [],
            image_urls: []
          )

          attrs = {
            title: permitted[:title],
            category_key: first_present(permitted[:categoryKey], permitted[:category_key]),
            area_prefecture: first_present(permitted[:areaPrefecture], permitted[:area_prefecture]),
            area_city: first_present(permitted[:areaCity], permitted[:area_city]),
            area: event_area_from_params(permitted),
            starts_at: parse_event_time_param(first_present(permitted[:startsAt], permitted[:starts_at])),
            ends_at: parse_event_time_param(first_present(permitted[:endsAt], permitted[:ends_at])),
            meeting_place: first_present(permitted[:meetingPlace], permitted[:meeting_place]),
            image_url: first_present(permitted[:imageUrl], permitted[:image_url]),
            image_urls: first_present(permitted[:imageUrls], permitted[:image_urls]),
            capacity: permitted[:capacity],
            min_participants: first_present(permitted[:minParticipants], permitted[:min_participants]),
            recruitment_ends_at: parse_event_time_param(first_present(permitted[:recruitmentEndsAt], permitted[:recruitment_ends_at])),
            summary: permitted[:summary],
            reference_url: first_present(permitted[:referenceUrl], permitted[:reference_url]),
            cost_label: first_present(permitted[:costLabel], permitted[:cost_label]),
            dress_code: first_present(permitted[:dressCode], permitted[:dress_code]),
            host_message: first_present(permitted[:hostMessage], permitted[:host_message]),
            host_age_group: first_present(permitted[:hostAgeGroup], permitted[:host_age_group]),
            same_gender_only: ActiveModel::Type::Boolean.new.cast(first_present(permitted[:sameGenderOnly], permitted[:same_gender_only])),
            same_generation_only: ActiveModel::Type::Boolean.new.cast(first_present(permitted[:sameGenerationOnly], permitted[:same_generation_only])),
            target_members: permitted[:targetMembers]
          }.compact

          attrs[:image_urls] = Array(attrs[:image_urls]).map(&:to_s).reject(&:blank?).first(5) if attrs.key?(:image_urls)
          attrs[:image_url] = attrs[:image_urls].first if attrs[:image_url].blank? && attrs[:image_urls].present?
          attrs[:image_url] ||= default_event_image_url(attrs[:category_key])
          attrs[:image_urls] = [attrs[:image_url]] if attrs[:image_urls].blank? && attrs[:image_url].present?
          attrs[:cost_label] ||= "各自負担"
          attrs[:dress_code] ||= "ドレスコードなし"
          attrs[:host_message] ||= "安心して参加できるよう、当日の流れを丁寧に案内します。"
          attrs[:host_display_name] = current_user.user_profile&.display_name || "ココさん"

          attrs
        end

        def first_present(*values)
          values.find { |value| value.present? }
        end

        def parse_event_time_param(value)
          return nil if value.blank?

          text = value.to_s.strip
          return nil if text.blank?

          # フロントからは基本的に `2026-07-01T09:00:00.000Z` のような
          # タイムゾーン付きISO8601で送る。既存クライアントやcurl等から
          # `2026-07-01T18:00` のようなタイムゾーンなし文字列が来た場合は、
          # Coconiqueの主対象である日本時間として解釈する。
          if text.match?(/(?:Z|[+-]\d{2}:?\d{2})\z/)
            Time.zone.parse(text)
          else
            EVENT_INPUT_TIME_ZONE.parse(text)
          end
        rescue ArgumentError, TypeError
          text
        end

        def event_area_from_params(permitted)
          prefecture = first_present(permitted[:areaPrefecture], permitted[:area_prefecture]).to_s.strip.presence
          city = first_present(permitted[:areaCity], permitted[:area_city]).to_s.strip.presence
          return [prefecture, city].compact_blank.join(" ") if prefecture.present?

          permitted[:area].presence || fallback_area_from_meeting_place(first_present(permitted[:meetingPlace], permitted[:meeting_place]))
        end

        def fallback_area_from_meeting_place(meeting_place)
          return "未設定" if meeting_place.blank?

          meeting_place.to_s.split(/[ 　]/).first.presence || "未設定"
        end

        def default_event_image_url(category_key)
          case category_key.to_s
          when "culture"
            "https://images.unsplash.com/photo-1518998053901-5348d3961a04?auto=format&fit=crop&w=1200&q=80"
          when "cafe"
            "https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=1200&q=80"
          when "watching"
            "https://images.unsplash.com/photo-1516321318423-f06f85e504b3?auto=format&fit=crop&w=1200&q=80"
          when "seasonal"
            "https://images.unsplash.com/photo-1533294455009-a77b7557d2d1?auto=format&fit=crop&w=1200&q=80"
          else
            "https://images.unsplash.com/photo-1545569341-9eb8b30979d9?auto=format&fit=crop&w=1200&q=80"
          end
        end
      end
    end
  end
end
