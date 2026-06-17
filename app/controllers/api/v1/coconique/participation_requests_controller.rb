module Api
  module V1
    module Coconique
      class ParticipationRequestsController < BaseController
        before_action :set_participation_request, only: [:show, :update, :approve, :reject, :withdraw, :cancel, :host_cancel, :attendance]
        before_action :set_event_for_collection, only: [:index, :participants]

        def index
          requests = if @event_for_collection.present?
            return unless require_event_host!(@event_for_collection)

            @event_for_collection.coconique_participation_requests.includes(:user, :coconique_event).ordered_recently
          elsif params[:role].to_s == "host"
            CoconiqueParticipationRequest
              .joins(:coconique_event)
              .where(coconique_events: { host_id: current_user.id })
              .includes(:user, :coconique_event)
              .ordered_recently
          else
            current_user.coconique_participation_requests.for_participant_history
          end

          if params[:status].present? && CoconiqueParticipationRequest.statuses.key?(params[:status])
            requests = requests.where(status: params[:status])
          end

          render_success(
            {
              participation_requests: requests.map { |participation_request| serialize_participation_request_summary(participation_request) }
            }
          )
        end

        def show
          return unless require_request_owner_or_event_host!(@participation_request)

          render_success(
            {
              participation_request: serialize_participation_request(@participation_request)
            }
          )
        end


        def participants
          return unless require_event_host!(@event_for_collection)

          requests = @event_for_collection.coconique_participation_requests
            .approved
            .includes(:user, :coconique_event)
            .ordered_recently

          render_success(
            {
              event: serialize_host_event(@event_for_collection),
              participants: requests.map { |participation_request| serialize_participation_request_summary(participation_request) }
            }
          )
        end

        def create
          event = find_event!
          return unless require_joinable_event!(event)
          return unless require_not_enryo_event!(event)
          return unless require_coconique_safety_registration!(action_kind: "apply_event", event: event)

          current_request = current_user.coconique_participation_requests
            .where(coconique_event: event, status: CoconiqueParticipationRequest::CURRENT_REQUEST_STATUSES)
            .order(created_at: :desc, id: :desc)
            .first

          if current_request.present?
            return render_existing_current_request!(current_request)
          end

          had_withdrawn_history = current_user.coconique_participation_requests
            .where(coconique_event: event, status: [:withdrawn, :auto_withdrawn])
            .exists?

          participation_request = current_user.coconique_participation_requests.build(
            coconique_event: event,
            status: :pending,
            message: normalized_message
          )

          participation_request.save!

          AuditLog.record!(
            user: current_user,
            action: had_withdrawn_history ? "coconique.participation_request.resubmitted" : "coconique.participation_request.created",
            request: request,
            target: participation_request
          )

          render_success(
            {
              participation_request: serialize_participation_request(participation_request)
            },
            status: :created
          )
        end

        def update
          unless @participation_request.user_id == current_user.id
            return render_error(
              code: "FORBIDDEN",
              message: "この申請を編集する権限がありません。",
              status: :forbidden
            )
          end

          return unless require_pending_request!(
            @participation_request,
            message: "申請済み内容は、確認中の間だけ編集できます。"
          )

          @participation_request.update!(message: normalized_message)

          render_success(
            {
              participation_request: serialize_participation_request(@participation_request.reload)
            }
          )
        end

        def approve
          event = @participation_request.coconique_event
          return unless require_event_host!(event)
          return unless require_event_approvable!(event)
          return unless require_not_enryo_user!(@participation_request.user, message: "この申請者とは遠慮設定中のため、参加メンバーに迎えることはできません。")
          return unless require_pending_request!(
            @participation_request,
            message: "確認中の申請だけ承認できます。"
          )

          @participation_request.approve!(reviewer: current_user)
          create_approval_chat_message!(@participation_request)

          AuditLog.record!(
            user: current_user,
            action: "coconique.participation_request.approved",
            request: request,
            target: @participation_request
          )

          render_success(
            {
              participation_request: serialize_participation_request(@participation_request.reload)
            }
          )
        end

        def reject
          event = @participation_request.coconique_event
          return unless require_event_host!(event)
          return unless require_pending_request!(
            @participation_request,
            message: "確認中の申請だけ見送りにできます。"
          )

          @participation_request.reject!(reviewer: current_user)

          AuditLog.record!(
            user: current_user,
            action: "coconique.participation_request.rejected",
            request: request,
            target: @participation_request
          )

          render_success(
            {
              participation_request: serialize_participation_request(@participation_request.reload)
            }
          )
        end


        def attendance
          event = @participation_request.coconique_event
          return unless require_event_host!(event)
          return unless require_finished_event_for_attendance!(event)
          return unless require_approved_participation_request!(@participation_request)

          attendance_status = normalized_attendance_status
          return if attendance_status.blank?

          @participation_request.record_attendance!(
            status: attendance_status,
            recorder: current_user,
            note: normalized_attendance_note
          )

          AuditLog.record!(
            user: current_user,
            action: "coconique.participation_request.attendance_recorded",
            request: request,
            target: @participation_request,
            metadata: {
              event_public_id: event.public_id,
              attendance_status: @participation_request.attendance_status
            }
          )

          render_success(
            {
              participation_request: serialize_participation_request(@participation_request.reload)
            }
          )
        end

        def withdraw
          unless @participation_request.user_id == current_user.id
            return render_error(
              code: "FORBIDDEN",
              message: "この申請を取り下げる権限がありません。",
              status: :forbidden
            )
          end

          return unless require_pending_request!(
            @participation_request,
            message: "この申請は現在取り下げできません。"
          )

          @participation_request.withdraw!

          AuditLog.record!(
            user: current_user,
            action: "coconique.participation_request.withdrawn",
            request: request,
            target: @participation_request
          )

          render_success(
            {
              participation_request: serialize_participation_request(@participation_request.reload)
            }
          )
        end

        def cancel
          unless @participation_request.user_id == current_user.id
            return render_error(
              code: "FORBIDDEN",
              message: "この参加をキャンセルする権限がありません。",
              status: :forbidden
            )
          end

          unless @participation_request.cancellable_by_participant?
            return render_error(
              code: "PARTICIPATION_REQUEST_NOT_CANCELABLE",
              message: "この参加申請は現在キャンセルできません。",
              status: :unprocessable_entity
            )
          end

          if @participation_request.pending?
            @participation_request.withdraw!
            action_name = "coconique.participation_request.withdrawn"
          else
            @participation_request.cancel_by_participant!(
              category: normalized_cancel_reason_category,
              message: normalized_cancel_message,
              actor: current_user
            )
            action_name = "coconique.participation_request.canceled_by_participant"
          end

          AuditLog.record!(
            user: current_user,
            action: action_name,
            request: request,
            target: @participation_request,
            metadata: {
              event_public_id: @participation_request.coconique_event.public_id,
              cancellation_reason_category: @participation_request.cancellation_reason_category,
              cancellation_timing: @participation_request.cancellation_timing,
              late_cancel_points: @participation_request.late_cancel_points
            }
          )

          render_success({ participation_request: serialize_participation_request(@participation_request.reload) })
        end

        def host_cancel
          event = @participation_request.coconique_event
          return unless require_event_host!(event)

          unless @participation_request.approved?
            return render_error(
              code: "PARTICIPATION_REQUEST_NOT_APPROVED",
              message: "参加確定済みのメンバーだけキャンセルできます。",
              status: :unprocessable_entity
            )
          end

          @participation_request.cancel_by_host!(
            reviewer: current_user,
            reason: params[:reason],
            user_message: params[:user_message].presence || params[:userMessage]
          )

          AuditLog.record!(
            user: current_user,
            action: "coconique.participation_request.canceled_by_host",
            request: request,
            target: @participation_request,
            metadata: { event_public_id: event.public_id }
          )

          render_success({ participation_request: serialize_participation_request(@participation_request.reload) })
        end

        private

        def set_participation_request
          @participation_request = find_participation_request!
        end

        def set_event_for_collection
          @event_for_collection = if params[:event_public_id].present? || params[:event_id].present? || params[:public_id].present?
            find_event!
          end
        end

        def require_event_approvable!(event)
          if event.canceled?
            return render_approval_blocked!("この募集はキャンセルされているため、承認できません。")
          end

          if event.finished?
            return render_approval_blocked!("この募集は終了しているため、承認できません。")
          end

          if event.closed?
            return render_approval_blocked!("この募集は停止されているため、承認できません。")
          end

          if event.starts_at.present? && event.starts_at <= Time.current
            return render_approval_blocked!("開催日時を過ぎているため、承認できません。")
          end

          if event.current_participants >= event.capacity
            return render_approval_blocked!("この募集は定員に達しています。")
          end

          true
        end



        def require_finished_event_for_attendance!(event)
          return true if event.finished?

          render_error(
            code: "EVENT_NOT_FINISHED",
            message: "参加実績は、終了済みの予定だけ記録できます。",
            status: :unprocessable_entity
          )

          false
        end

        def require_approved_participation_request!(participation_request)
          return true if participation_request.approved?

          render_error(
            code: "PARTICIPATION_REQUEST_NOT_APPROVED",
            message: "承認済みの参加者だけ参加実績を記録できます。",
            status: :unprocessable_entity
          )

          false
        end

        def normalized_attendance_status
          value = params[:attendance_status].presence || params[:attendanceStatus].presence || "unconfirmed"
          return value.to_s if CoconiqueParticipationRequest.attendance_statuses.key?(value.to_s)

          render_error(
            code: "INVALID_ATTENDANCE_STATUS",
            message: "参加実績の状態が正しくありません。",
            status: :unprocessable_entity
          )

          nil
        end

        def normalized_attendance_note
          note = params[:attendance_note].presence || params[:attendanceNote].presence
          note.to_s.strip.presence
        end

        def normalized_cancel_reason_category
          value = params[:reason_category].presence || params[:reasonCategory].presence || params[:category].presence || "other"
          value.to_s
        end

        def normalized_cancel_message
          params[:message].presence || params[:host_message].presence || params[:hostMessage].presence
        end

        def create_approval_chat_message!(participation_request)
          event = participation_request.coconique_event
          display_name = participation_request.user.user_profile&.display_name.presence || participation_request.user.email.to_s.split("@").first

          event.coconique_event_messages.create!(
            user: current_user,
            kind: :system,
            body: "#{display_name}さんが参加メンバーになりました。"
          )
        rescue StandardError => e
          Rails.logger.warn("[CoconiqueEventMessage] failed to create approval message: #{e.class} #{e.message}")
          nil
        end

        def render_approval_blocked!(message)
          render_error(
            code: "PARTICIPATION_REQUEST_NOT_APPROVABLE",
            message: message,
            status: :unprocessable_entity
          )

          false
        end

        def normalized_message
          message = params[:message].to_s.strip
          return "参加したいです。よろしくお願いします。" if message.blank?

          message
        end

        def render_existing_current_request!(participation_request)
          case participation_request.status
          when "draft"
            participation_request.update!(
              status: :pending,
              message: normalized_message,
              reviewed_by: nil,
              reviewed_at: nil,
              withdrawn_at: nil
            )

            render_success(
              {
                participation_request: serialize_participation_request(participation_request.reload)
              }
            )
          when "pending"
            render_success(
              {
                participation_request: serialize_participation_request(participation_request)
              }
            )
          when "approved"
            render_error(
              code: "PARTICIPATION_REQUEST_ALREADY_APPROVED",
              message: "この募集はすでに参加承認されています。",
              status: :unprocessable_entity
            )
          when "rejected"
            render_error(
              code: "PARTICIPATION_REQUEST_REJECTED",
              message: "この募集は今回は見送りになっています。再申請が必要な場合はサポートにご相談ください。",
              status: :unprocessable_entity
            )
          else
            render_error(
              code: "PARTICIPATION_REQUEST_NOT_AVAILABLE",
              message: "この申請は現在更新できません。",
              status: :unprocessable_entity
            )
          end
        end
      end
    end
  end
end
