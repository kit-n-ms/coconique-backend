module Api
  module V1
    module Coconique
      class SafetyRegistrationsController < BaseController
        before_action :set_intent, only: [:complete_intent]

        def status
          render_success(
            {
              safety_registration: serialize_coconique_safety_registration_status(current_user)
            }
          )
        end

        def create_intent
          intent = current_user.coconique_safety_registration_intents.create!(
            kind: normalized_intent_kind,
            coconique_event: intent_event,
            return_path: params[:return_path].to_s.strip.presence,
            payload: normalized_intent_payload,
            metadata: {
              "source" => params[:source].to_s.presence,
              "user_agent" => request.user_agent.to_s[0, 300]
            }
          )

          render_success(
            {
              intent: serialize_safety_registration_intent(intent),
              safety_registration: serialize_coconique_safety_registration_status(current_user)
            },
            status: :created
          )
        end

        def complete_intent
          if @intent.expired_now?
            @intent.update!(status: :expired)
            return render_error(
              code: "COCONIQUE_SAFETY_INTENT_EXPIRED",
              message: "安全登録の再開情報が期限切れです。もう一度操作をやり直してください。",
              status: :unprocessable_entity
            )
          end

          return unless require_coconique_safety_registration!(action_kind: @intent.kind, event: @intent.coconique_event)

          payload = case @intent.kind
          when "apply_event"
            complete_apply_event_intent!(@intent)
          when "publish_event"
            complete_publish_event_intent!(@intent)
          else
            {}
          end

          @intent.complete!

          render_success(
            payload.merge(
              intent: serialize_safety_registration_intent(@intent.reload),
              safety_registration: serialize_coconique_safety_registration_status(current_user)
            )
          )
        end

        def create_phone_verification
          phone_number = params.require(:phone_number)
          normalized_phone = CoconiquePhoneVerificationAttempt.normalize_phone_number(phone_number)

          if normalized_phone.blank? || normalized_phone.length < 10
            return render_error(
              code: "INVALID_PHONE_NUMBER",
              message: "電話番号を確認してください。",
              status: :unprocessable_entity
            )
          end

          current_user.update!(phone_verification_status: :pending)

          attempt = CoconiquePhoneVerificationAttempt.build_for!(
            user: current_user,
            phone_number: normalized_phone
          )

          render_success(
            {
              phone_verification: serialize_phone_verification_attempt(attempt),
              safety_registration: serialize_coconique_safety_registration_status(current_user)
            }.merge(fake_sms_debug_payload),
            status: :created
          )
        rescue ::Coconique::SmsVerifications::TwilioVerifyProvider::ConfigurationError,
          ::Coconique::SmsVerifications::TwilioVerifyProvider::ApiError => e
          Rails.logger.warn("[PhoneVerification] start failed: #{e.class}: #{e.message}")
          current_user.update!(phone_verification_status: :unverified) if current_user.phone_verification_pending?
          render_error(
            code: "SMS_PROVIDER_UNAVAILABLE",
            message: "SMS認証サービスの準備ができていません。時間をおいて再度お試しください。",
            status: :service_unavailable,
            data: { detail: Rails.env.production? ? nil : e.message }
          )
        end

        def confirm_phone_verification
          attempt_id = params[:verification_id].presence || params[:id].presence
          attempt = current_user.coconique_phone_verification_attempts.active_pending.find_by(public_id: attempt_id)
          attempt ||= current_user.coconique_phone_verification_attempts.active_pending.recent_first.first

          if attempt.blank?
            return render_error(
              code: "PHONE_VERIFICATION_NOT_FOUND",
              message: "有効なSMS認証が見つかりません。もう一度コードを送信してください。",
              status: :not_found
            )
          end

          unless attempt.verify!(params.require(:code))
            return render_error(
              code: "PHONE_VERIFICATION_FAILED",
              message: "認証コードが正しくないか、有効期限が切れています。",
              status: :unprocessable_entity
            )
          end

          render_success(
            {
              phone_verification: serialize_phone_verification_attempt(attempt.reload),
              safety_registration: serialize_coconique_safety_registration_status(current_user.reload)
            }
          )
        rescue ::Coconique::SmsVerifications::TwilioVerifyProvider::ConfigurationError,
          ::Coconique::SmsVerifications::TwilioVerifyProvider::ApiError => e
          Rails.logger.warn("[PhoneVerification] confirm failed: #{e.class}: #{e.message}")
          render_error(
            code: "SMS_PROVIDER_CONFIRM_FAILED",
            message: "SMS認証コードを確認できませんでした。少し時間をおいて再度お試しください。",
            status: :unprocessable_entity,
            data: { detail: Rails.env.production? ? nil : e.message }
          )
        end

        def create_identity_verification
          if current_user.coconique_collaborator_beta?
            return render_success(
              {
                identity_verification: nil,
                safety_registration: serialize_coconique_safety_registration_status(current_user),
                message: "協力者βメンバーは本人確認書類の提出は不要です。"
              }
            )
          end

          session = create_provider_identity_session!

          render_success(
            {
              identity_verification: serialize_identity_verification_session(session),
              safety_registration: serialize_coconique_safety_registration_status(current_user.reload)
            },
            status: :created
          )
        rescue ::Coconique::IdentityVerifications::DiditProvider::ConfigurationError,
          ::Coconique::IdentityVerifications::DiditProvider::ApiError,
          ::Coconique::IdentityVerifications::QuickTrustProvider::ConfigurationError,
          ::Coconique::IdentityVerifications::QuickTrustProvider::ApiError,
          ::Coconique::IdentityVerifications::QuickTrustProvider::LiveApiNotImplementedError,
          ::Coconique::IdentityVerifications::StripeIdentityProvider::ConfigurationError => e
          Rails.logger.warn("[IdentityVerification] start failed: #{e.class}: #{e.message}")
          render_error(
            code: "IDENTITY_PROVIDER_UNAVAILABLE",
            message: "本人確認サービスの準備ができていません。時間をおいて再度お試しください。",
            status: :service_unavailable,
            data: { detail: Rails.env.production? ? nil : e.message }
          )
        end


        def sync_identity_verification
          session = identity_session_for_sync

          if session.blank?
            return render_error(
              code: "IDENTITY_VERIFICATION_SESSION_NOT_FOUND",
              message: "本人確認セッションが見つかりません。もう一度本人確認を開始してください。",
              status: :not_found
            )
          end

          synced_session = sync_identity_session_from_provider(session)

          render_success(
            {
              identity_verification: serialize_identity_verification_session(synced_session.reload),
              safety_registration: serialize_coconique_safety_registration_status(current_user.reload)
            }
          )
        rescue ::Coconique::IdentityVerifications::DiditProvider::ConfigurationError,
          ::Coconique::IdentityVerifications::DiditProvider::ApiError => e
          Rails.logger.warn("[IdentityVerification] sync failed: #{e.class}: #{e.message}")
          render_error(
            code: "IDENTITY_PROVIDER_SYNC_FAILED",
            message: "本人確認結果の反映確認に失敗しました。少し時間をおいて再度お試しください。",
            status: :unprocessable_entity,
            data: { detail: Rails.env.production? ? nil : e.message }
          )
        end

        def fake_complete_identity_verification
          unless Rails.env.development? || Rails.env.test? || ActiveModel::Type::Boolean.new.cast(ENV["COCONIQUE_ALLOW_FAKE_IDENTITY"])
            return render_error(
              code: "FAKE_IDENTITY_DISABLED",
              message: "この環境では開発用の本人確認完了処理は利用できません。",
              status: :forbidden
            )
          end

          session_id = params[:session_id].presence || params[:identity_session_id].presence
          session = if session_id.present?
            current_user.coconique_identity_verification_sessions.find_by!(public_id: session_id)
          else
            current_user.coconique_identity_verification_sessions.recent_first.first || current_user.coconique_identity_verification_sessions.create!(
              provider: "fake_identity",
              status: :processing,
              provider_session_id: "fake_#{SecureRandom.hex(10)}",
              workflow_type: "standard_document",
              provider_status: "fake_processing",
              return_url: params[:return_url].to_s.presence,
              metadata: { "created_by" => "fake_complete" }
            )
          end

          session.mark_verified!(
            provider_session_id: session.provider_session_id.presence || "fake_#{SecureRandom.hex(10)}",
            age_over_18: params.key?(:age_over_18) ? params[:age_over_18] : true,
            document_type: session.document_type.presence || "driving_license",
            provider_status: "fake_approved",
            metadata: { "fake_completed_at" => Time.current.iso8601 }
          )

          render_success(
            {
              identity_verification: serialize_identity_verification_session(session.reload),
              safety_registration: serialize_coconique_safety_registration_status(current_user.reload)
            }
          )
        end

        def redeem_promo_code
          code = params.require(:code)

          unless CoconiquePromoCodeRedemption.valid_collaborator_code?(code)
            return render_error(
              code: "INVALID_PROMO_CODE",
              message: "プロモーションコードを確認してください。",
              status: :unprocessable_entity
            )
          end

          redemption = current_user.coconique_promo_code_redemptions.find_or_initialize_by(
            code_digest: CoconiquePromoCodeRedemption.code_digest_for(code)
          )
          redemption.code_label ||= CoconiquePromoCodeRedemption.normalize_code(code)
          redemption.status ||= :redeemed
          redemption.save!
          redemption.apply_to_user!

          render_success(
            {
              promo_code_redemption: {
                id: redemption.public_id,
                codeLabel: redemption.code_label,
                redeemedAt: redemption.redeemed_at&.iso8601
              },
              safety_registration: serialize_coconique_safety_registration_status(current_user.reload)
            }
          )
        end

        def fake_complete_payment_method
          unless Rails.env.development? || Rails.env.test? || ActiveModel::Type::Boolean.new.cast(ENV["COCONIQUE_ALLOW_FAKE_PAYMENT_METHOD"])
            return render_error(
              code: "FAKE_PAYMENT_METHOD_DISABLED",
              message: "この環境では開発用の支払い方法登録完了処理は利用できません。",
              status: :forbidden
            )
          end

          CoconiqueBilling.activate_founder_beta_subscription!(
            user: current_user,
            source: current_user,
            metadata: { fake_payment_method: true }
          )

          render_success(
            {
              safety_registration: serialize_coconique_safety_registration_status(current_user.reload)
            }
          )
        end

        private

        def set_intent
          @intent = current_user.coconique_safety_registration_intents.find_by!(public_id: params[:id])
        end

        def normalized_intent_kind
          kind = params[:kind].to_s
          return kind if CoconiqueSafetyRegistrationIntent.kinds.key?(kind)

          raise ActionController::ParameterMissing, :kind
        end

        def intent_event
          public_id = params[:event_id].presence || params[:draft_event_id].presence || params[:coconique_event_id].presence
          return nil if public_id.blank?

          current_user.hosted_coconique_events.find_by(public_id: public_id) || CoconiqueEvent.find_by!(public_id: public_id)
        end

        def normalized_intent_payload
          raw_payload = params[:payload].is_a?(ActionController::Parameters) ? params[:payload].permit!.to_h : params[:payload]
          payload = raw_payload.is_a?(Hash) ? raw_payload : {}

          %w[event_id draft_event_id message].each do |key|
            payload[key] = params[key] if params[key].present?
          end

          payload.stringify_keys.slice("event_id", "draft_event_id", "message")
        end

        def identity_session_for_sync
          session_id = params[:identity_session_id].presence || params[:session_id].presence || params[:id].presence
          provider_session_id = params[:provider_session_id].presence || params[:verification_session_id].presence || params[:verificationSessionId].presence

          if session_id.present?
            found = current_user.coconique_identity_verification_sessions.find_by(public_id: session_id)
            return found if found.present?
          end

          if provider_session_id.present?
            found = current_user.coconique_identity_verification_sessions.find_by(provider_session_id: provider_session_id)
            return found if found.present?
          end

          current_user.coconique_identity_verification_sessions.recent_first.first
        end

        def sync_identity_session_from_provider(session)
          case session.provider.to_s
          when "didit"
            provider = ::Coconique::IdentityVerifications::DiditProvider.new
            decision = provider.retrieve_decision(session.provider_session_id)
            provider.apply_decision_to_session!(
              session,
              decision,
              webhook_metadata: {
                "didit_sync_source" => "safety_registration_page",
                "didit_synced_at" => Time.current.iso8601
              }
            )
          else
            session
          end
        end

        def create_provider_identity_session!
          return_url = normalized_identity_return_url
          workflow_type = normalized_identity_workflow_type

          ::Coconique::IdentityVerifications::ProviderFactory.current.create_session(
            user: current_user,
            return_url: return_url,
            workflow_type: workflow_type
          )
        end

        def normalized_identity_return_url
          supplied = params[:return_url].to_s.strip.presence
          configured = ENV["COCONIQUE_IDENTITY_PUBLIC_RETURN_URL"].to_s.strip.presence || ENV["COCONIQUE_IDENTITY_RETURN_URL"].to_s.strip.presence
          fallback = "http://localhost:5173/identity/return"

          configured || supplied || fallback
        end

        def normalized_identity_workflow_type
          requested = params[:workflow_type].to_s.presence || params[:document_route].to_s.presence
          return "my_number_front_only" if requested == "my_number_front_only" && ::Coconique::IdentityVerifications::ProviderFactory.my_number_enabled_for_current_provider?

          "standard_document"
        end

        def fake_sms_debug_payload
          return {} unless CoconiquePhoneVerificationAttempt.fake_provider?

          { debug: { sms_code: CoconiquePhoneVerificationAttempt::DEV_TEST_CODE } }
        end

        def serialize_phone_verification_attempt(attempt)
          {
            id: attempt.public_id,
            status: attempt.status,
            sentToMasked: attempt.sent_to_masked,
            provider: attempt.provider,
            expiresAt: attempt.expires_at&.iso8601,
            confirmedAt: attempt.confirmed_at&.iso8601,
            attemptsCount: attempt.attempts_count
          }
        end

        def serialize_identity_verification_session(session)
          {
            id: session.public_id,
            provider: session.provider,
            providerSessionId: session.provider_session_id,
            status: session.status,
            url: session.url,
            returnUrl: session.return_url,
            expiresAt: session.expires_at&.iso8601,
            verifiedAt: session.verified_at&.iso8601,
            workflowType: session.respond_to?(:workflow_type) ? session.workflow_type : nil,
            documentType: session.respond_to?(:document_type) ? session.document_type : nil,
            providerStatus: session.respond_to?(:provider_status) ? session.provider_status : nil
          }
        end

        def serialize_safety_registration_intent(intent)
          {
            id: intent.public_id,
            kind: intent.kind,
            status: intent.status,
            eventId: intent.coconique_event&.public_id,
            returnPath: intent.return_path,
            expiresAt: intent.expires_at&.iso8601,
            completedAt: intent.completed_at&.iso8601,
            payload: intent.payload || {}
          }
        end

        def complete_apply_event_intent!(intent)
          event = intent.coconique_event || CoconiqueEvent.find_by!(public_id: intent.payload["event_id"])
          return {} unless require_joinable_event!(event)
          return {} unless require_not_enryo_event!(event)

          current_request = current_user.coconique_participation_requests
            .where(coconique_event: event, status: CoconiqueParticipationRequest::CURRENT_REQUEST_STATUSES)
            .order(created_at: :desc, id: :desc)
            .first

          participation_request = current_request || current_user.coconique_participation_requests.create!(
            coconique_event: event,
            status: :pending,
            message: intent.payload["message"].to_s.strip.presence || "安全登録完了後に参加申請しました。"
          )

          AuditLog.record!(
            user: current_user,
            action: current_request.present? ? "coconique.safety_intent.apply_event.existing_request" : "coconique.safety_intent.apply_event.created_request",
            request: request,
            target: participation_request,
            metadata: { event_public_id: event.public_id, intent_id: intent.public_id }
          )

          {
            participation_request: serialize_participation_request(participation_request.reload),
            nextPath: "/app/events/#{event.public_id}/request/complete?requestId=#{participation_request.public_id.presence || participation_request.id}"
          }
        end

        def complete_publish_event_intent!(intent)
          event = intent.coconique_event || current_user.hosted_coconique_events.find_by!(public_id: intent.payload["draft_event_id"] || intent.payload["event_id"])
          return {} unless require_event_host!(event)
          return {} unless require_publishable_event!(event)
          return {} unless require_host_ticket_available!(event: event)

          unless event.visible_to_members_status?
            return {} unless consume_host_ticket_for_event!(event)

            previous_status = event.status
            event.publish!
            create_status_log!(event: event, action: "coconique.safety_intent.event.published", from_status: previous_status, to_status: event.status)

            AuditLog.record!(
              user: current_user,
              action: "coconique.safety_intent.event.published",
              request: request,
              target: event,
              metadata: { intent_id: intent.public_id }
            )
          end

          {
            event: serialize_event(event.reload),
            nextPath: "/app/host/new/complete?status=recruiting&eventId=#{event.public_id}"
          }
        end

        def create_status_log!(event:, action:, from_status:, to_status:, reason: nil)
          event.coconique_event_status_logs.create!(
            user: current_user,
            action: action,
            from_status: from_status,
            to_status: to_status,
            reason: reason
          )
        end
      end
    end
  end
end
