module Api
  module V1
    module Admin
      class CoconiqueUserRestrictionsController < BaseController
        def index
          active_only = params[:active].to_s == "true"
          user_id = params[:user_id] || params[:userId]

          scope = CoconiqueUserRestriction.includes(:user, :coconique_report, :created_by_admin, :lifted_by_admin)

          if active_only
            # 凍結一覧・BAN一覧は「履歴」ではなく、各ユーザーの現在有効な最新ステータスだけを表示する。
            # 旧実装では active=true がフロントから送られなかった場合や、過去の制限履歴が残っている場合に
            # BAN解除後もBAN一覧に出続けることがあったため、最新の有効制限に絞る。
            active_scope = CoconiqueUserRestriction.active
            active_scope = active_scope.where(user_id: user_id) if user_id.present?
            latest_active_ids = active_scope.group(:user_id).maximum(:id).values
            scope = scope.where(id: latest_active_ids)
          else
            scope = scope.where(user_id: user_id) if user_id.present?
          end

          scope = scope.where(status: params[:status]) if params[:status].present? && CoconiqueUserRestriction.statuses.key?(params[:status])
          scope = scope.ordered_recently

          restrictions, pagination = paginated(scope)

          render_success({ restrictions: restrictions.map { |restriction| serialize_restriction(restriction) }, pagination: pagination })
        end

        def create
          user_id = params[:userId].presence || params[:user_id].presence
          return render_error(code: "USER_REQUIRED", message: "対象ユーザーを指定してください。", status: :unprocessable_entity) if user_id.blank?

          user = User.find(user_id)
          restriction_status = params.require(:status)

          unless CoconiqueUserRestriction.statuses.key?(restriction_status)
            return render_error(code: "INVALID_RESTRICTION_STATUS", message: "指定された制限ステータスは使用できません。", status: :unprocessable_entity)
          end

          if user.id == current_user.id && restriction_status != "restricted"
            return render_error(code: "CANNOT_RESTRICT_SELF", message: "自分自身を凍結・BANすることはできません。", status: :unprocessable_entity)
          end

          report = CoconiqueReport.find_by(public_id: params[:reportId] || params[:report_id])
          restriction = nil

          CoconiqueUserRestriction.transaction do
            restriction = CoconiqueUserRestriction.create!(
              user: user,
              coconique_report: report,
              created_by_admin: current_user,
              status: restriction_status,
              reason: params[:reason].presence || "運営確認による制限",
              note: params[:note],
              starts_at: parse_time_param(params[:startsAt] || params[:starts_at]) || Time.current,
              ends_at: parse_time_param(params[:endsAt] || params[:ends_at]),
              metadata: { report_public_id: report&.public_id }
            )

            lift_previous_active_restrictions!(user: user, new_restriction: restriction)

            if report.present?
              report.coconique_report_actions.create!(
                admin_user: current_user,
                action_type: action_type_for_restriction(restriction),
                note: params[:note].presence || params[:reason],
                metadata: { restriction_public_id: restriction.public_id }
              )
            end
          end

          AuditLog.record!(user: current_user, action: "admin.coconique_user_restriction.created", request: request, target: restriction, metadata: { user_id: user.id, status: restriction.status })

          render_success({ restriction: serialize_restriction(restriction.reload) }, status: :created)
        end

        def lift
          restriction = CoconiqueUserRestriction.find_by!(public_id: params[:id])
          restriction.lift!(admin_user: current_user, note: params[:note])

          restriction.coconique_report&.coconique_report_actions&.create!(
            admin_user: current_user,
            action_type: :note,
            note: "ユーザー制限を解除しました。#{params[:note].presence}",
            metadata: { restriction_public_id: restriction.public_id }
          )

          AuditLog.record!(user: current_user, action: "admin.coconique_user_restriction.lifted", request: request, target: restriction, metadata: { user_id: restriction.user_id, status: restriction.status })

          render_success({ restriction: serialize_restriction(restriction.reload) })
        end

        private


        def lift_previous_active_restrictions!(user:, new_restriction:)
          user.coconique_user_restrictions.active.where.not(id: new_restriction.id).find_each do |restriction|
            restriction.lift!(
              admin_user: current_user,
              note: "新しい制限（#{new_restriction.status}）を適用したため、以前の有効制限を終了しました。"
            )

            restriction.coconique_report&.coconique_report_actions&.create!(
              admin_user: current_user,
              action_type: :note,
              note: "新しい制限（#{new_restriction.status}）を適用したため、以前のユーザー制限を終了しました。",
              metadata: { restriction_public_id: restriction.public_id, superseded_by_restriction_public_id: new_restriction.public_id }
            )
          end
        end

        def parse_time_param(value)
          return nil if value.blank?

          Time.zone.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def action_type_for_restriction(restriction)
          return :ban if restriction.banned?
          return :suspend if restriction.suspended?

          :restrict
        end

        def serialize_restriction(restriction)
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
            "updatedAt" => restriction.updated_at&.iso8601,
            "user" => admin_user_brief_json(restriction.user),
            "report" => restriction.coconique_report && {
              "id" => restriction.coconique_report.public_id,
              "reason" => restriction.coconique_report.reason,
              "status" => restriction.coconique_report.status,
              "severity" => restriction.coconique_report.severity
            },
            "createdByAdmin" => admin_user_brief_json(restriction.created_by_admin),
            "liftedByAdmin" => admin_user_brief_json(restriction.lifted_by_admin)
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
