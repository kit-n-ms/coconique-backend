module Api
  module V1
    module Coconique
      class SafetyCheckSessionsController < BaseController
        before_action :set_session, only: [:show, :respond]

        def index
          cancel_inactive_pending_sessions!

          scope = current_user.coconique_safety_check_sessions
            .includes(:coconique_event, :coconique_participation_request)
            .ordered_recently

          scope = scope.needs_response if params[:status].to_s == "pending"
          scope = scope.limit(params.fetch(:limit, 30).to_i.clamp(1, 100))

          render_success({ safety_check_sessions: scope.map { |session| serialize_safety_check_session(session) } })
        end

        def show
          render_success({ safety_check_session: serialize_safety_check_session(@session) })
        end

        def respond
          case params[:responseKind].presence || params[:response_kind].presence
          when "safe"
            @session.answer_safe!
          when "extended"
            @session.answer_extended!(minutes: extension_minutes)
          when "help"
            @session.answer_help!(note: params[:helpNote].presence || params[:help_note].presence)
            create_help_report_for_session!(@session)
          else
            return render_error(
              code: "INVALID_SAFETY_CHECK_RESPONSE",
              message: "帰宅確認の回答を選択してください。",
              status: :unprocessable_entity
            )
          end

          AuditLog.record!(
            user: current_user,
            action: "coconique.safety_check_session.responded",
            request: request,
            target: @session,
            metadata: { response_kind: @session.response_kind, status: @session.status }
          )

          render_success({ safety_check_session: serialize_safety_check_session(@session) })
        end

        private


        def create_help_report_for_session!(session)
          return if CoconiqueReport.exists?(coconique_safety_check_session: session, reporter: current_user, target_type: CoconiqueReport.target_types[:safety_check])

          event = session.coconique_event
          report = CoconiqueReport.create!(
            reporter: current_user,
            reported_user: event&.host,
            coconique_event: event,
            coconique_safety_check_session: session,
            target_type: :safety_check,
            target_public_id: session.public_id,
            reason: :danger_or_anxiety,
            detail: session.help_note.presence || "帰宅確認で「困っています / 相談したい」が選択されました。",
            severity: :urgent,
            report_phase: :after_event,
            event_status_at_report: event&.status,
            reporter_role: session.role,
            snapshot: {
              reported_at: Time.current.iso8601,
              safety_check_session: {
                public_id: session.public_id,
                status: session.status,
                response_kind: session.response_kind,
                role: session.role,
                due_at: session.due_at&.iso8601,
                answered_at: session.answered_at&.iso8601,
                help_note: session.help_note
              },
              event: event && {
                public_id: event.public_id,
                title: event.title,
                status: event.status,
                starts_at: event.starts_at&.iso8601,
                ends_at: event.ends_at&.iso8601
              }
            }.compact
          )

          report.coconique_report_evidences.create!(
            evidence_type: :safety_check_snapshot,
            metadata: report.snapshot["safety_check_session"] || report.snapshot[:safety_check_session] || {}
          )
        rescue StandardError => e
          Rails.logger.warn("[CoconiqueReport] failed to create help report: #{e.class} #{e.message}")
          nil
        end

        def cancel_inactive_pending_sessions!
          current_user.coconique_safety_check_sessions.needs_response.includes(:coconique_event).find_each do |session|
            session.cancel_if_inactive_setting!
          end
        end

        def set_session
          @session = current_user.coconique_safety_check_sessions.find_by!(public_id: params[:id])
        end

        def extension_minutes
          value = params[:extensionMinutes] || params[:extension_minutes]
          return CoconiqueSafetyCheckSession::DEFAULT_EXTENSION_MINUTES if value.blank?

          value.to_i
        end
      end
    end
  end
end
