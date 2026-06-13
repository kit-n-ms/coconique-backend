module Api
  module V1
    module Admin
      class CoconiqueReportsController < BaseController
        def index
          scope = CoconiqueReport
            .includes(:reporter, :reported_user, :coconique_event)
            .ordered_for_admin

          scope = scope.where(status: params[:status]) if params[:status].present? && CoconiqueReport.statuses.key?(params[:status])
          scope = scope.where(severity: params[:severity]) if params[:severity].present? && CoconiqueReport.severities.key?(params[:severity])
          scope = scope.where(target_type: params[:target_type] || params[:targetType]) if (params[:target_type] || params[:targetType]).present? && CoconiqueReport.target_types.key?(params[:target_type] || params[:targetType])

          reports, pagination = paginated(scope)

          render_success({ reports: reports.map { |report| serialize_report_summary(report) }, pagination: pagination })
        end

        def show
          report = CoconiqueReport
            .includes(
              :reporter,
              :reported_user,
              :coconique_event,
              :coconique_event_message,
              :coconique_safety_check_session,
              :coconique_report_evidences,
              coconique_report_actions: :admin_user,
              coconique_user_restrictions: [:user, :created_by_admin, :lifted_by_admin],
              coconique_user_blocks: [:blocker, :blocked, :lifted_by]
            )
            .find_by!(public_id: params[:id])

          render_success({ report: serialize_report_detail(report) })
        end

        def add_action
          report = CoconiqueReport.find_by!(public_id: params[:id])
          action_type = params[:actionType].presence || params[:action_type].presence || "note"
          action_type = "note" unless CoconiqueReportAction.action_types.key?(action_type)

          action = report.coconique_report_actions.create!(
            admin_user: current_user,
            action_type: action_type,
            note: params[:note],
            metadata: { source: "admin" }
          )

          AuditLog.record!(user: current_user, action: "admin.coconique_report.action_created", request: request, target: report, metadata: { report_action_id: action.id, action_type: action.action_type })

          render_success({ report: serialize_report_detail(report.reload) }, status: :created)
        end

        def status
          report = CoconiqueReport.find_by!(public_id: params[:id])
          next_status = params.require(:status)

          unless CoconiqueReport.statuses.key?(next_status)
            return render_error(code: "INVALID_REPORT_STATUS", message: "指定された通報ステータスは使用できません。", status: :unprocessable_entity)
          end

          report.close_with_status!(next_status: next_status, admin_user: current_user, note: params[:note])

          AuditLog.record!(user: current_user, action: "admin.coconique_report.status_updated", request: request, target: report, metadata: { status: next_status })

          render_success({ report: serialize_report_detail(report.reload) })
        end

        private

        def serialize_report_summary(report)
          {
            "id" => report.public_id,
            "createdAt" => report.created_at&.iso8601,
            "targetType" => report.target_type,
            "targetPublicId" => report.target_public_id,
            "reason" => report.reason,
            "status" => report.status,
            "severity" => report.severity,
            "reportPhase" => report.report_phase,
            "eventStatusAtReport" => report.event_status_at_report,
            "reporterRole" => report.reporter_role,
            "reporter" => admin_user_brief_json(report.reporter),
            "reportedUser" => admin_user_brief_json(report.reported_user),
            "event" => admin_event_brief_json(report.coconique_event)
          }
        end

        def serialize_report_detail(report)
          serialize_report_summary(report).merge(
            "detail" => report.detail,
            "snapshot" => report.snapshot || {},
            "message" => admin_message_json(report.coconique_event_message),
            "safetyCheckSession" => admin_safety_session_json(report.coconique_safety_check_session),
            "reportedUserActiveRestriction" => admin_restriction_json(active_restriction_for(report.reported_user)),
            "evidences" => report.coconique_report_evidences.order(:id).map { |evidence| admin_evidence_json(evidence) },
            "actions" => report.coconique_report_actions.order(created_at: :desc, id: :desc).map { |action| admin_action_json(action) },
            "restrictions" => report.coconique_user_restrictions.order(created_at: :desc, id: :desc).map { |restriction| admin_restriction_json(restriction) },
            "userBlocks" => report.coconique_user_blocks.order(created_at: :desc, id: :desc).map { |block| admin_user_block_json(block) }
          )
        end

        def active_restriction_for(user)
          return nil if user.blank?

          user.coconique_user_restrictions.active.order(created_at: :desc, id: :desc).first
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

        def admin_event_brief_json(event)
          return nil if event.blank?
          {
            "id" => event.public_id,
            "title" => event.title,
            "status" => event.status,
            "area" => event.area,
            "startsAt" => event.starts_at&.iso8601,
            "endsAt" => event.ends_at&.iso8601
          }
        end

        def admin_message_json(message)
          return nil if message.blank?
          {
            "id" => message.public_id,
            "body" => message.body,
            "kind" => message.kind,
            "imageUrls" => message.image_urls,
            "createdAt" => message.created_at&.iso8601,
            "user" => admin_user_brief_json(message.user)
          }
        end

        def admin_safety_session_json(session)
          return nil if session.blank?
          {
            "id" => session.public_id,
            "status" => session.status,
            "responseKind" => session.response_kind,
            "role" => session.role,
            "dueAt" => session.due_at&.iso8601,
            "answeredAt" => session.answered_at&.iso8601,
            "escalatedAt" => session.escalated_at&.iso8601,
            "helpNote" => session.help_note
          }
        end

        def admin_evidence_json(evidence)
          {
            "id" => evidence.public_id,
            "type" => evidence.evidence_type,
            "body" => evidence.body,
            "metadata" => evidence.metadata || {},
            "createdAt" => evidence.created_at&.iso8601
          }
        end

        def admin_action_json(action)
          {
            "id" => action.public_id,
            "actionType" => action.action_type,
            "previousStatus" => action.previous_status,
            "nextStatus" => action.next_status,
            "note" => action.note,
            "metadata" => action.metadata || {},
            "createdAt" => action.created_at&.iso8601,
            "adminUser" => admin_user_brief_json(action.admin_user)
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
            "liftedBy" => admin_user_brief_json(block.lifted_by)
          }
        end

        def admin_restriction_json(restriction)
          return nil if restriction.blank?

          {
            "id" => restriction.public_id,
            "status" => restriction.status,
            "reason" => restriction.reason,
            "note" => restriction.note,
            "startsAt" => restriction.starts_at&.iso8601,
            "endsAt" => restriction.ends_at&.iso8601,
            "liftedAt" => restriction.lifted_at&.iso8601,
            "active" => restriction.active_now?,
            "user" => admin_user_brief_json(restriction.user),
            "createdByAdmin" => admin_user_brief_json(restriction.created_by_admin),
            "liftedByAdmin" => admin_user_brief_json(restriction.lifted_by_admin)
          }
        end
      end
    end
  end
end
