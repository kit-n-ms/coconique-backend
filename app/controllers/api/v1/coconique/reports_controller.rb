module Api
  module V1
    module Coconique
      class ReportsController < BaseController
        def create
          report = build_report!
          report.save!
          create_evidences!(report)

          AuditLog.record!(
            user: current_user,
            action: "coconique.report.created",
            request: request,
            target: report,
            metadata: {
              target_type: report.target_type,
              target_public_id: report.target_public_id,
              reason: report.reason,
              severity: report.severity
            }
          )

          render_success({ report: serialize_report_receipt(report) }, status: :created)
        end

        private

        def build_report!
          target_context = resolve_target_context!
          event = target_context[:event]
          report_phase = event.present? ? phase_for_event(event) : :unknown_phase

          CoconiqueReport.new(
            reporter: current_user,
            reported_user: target_context[:reported_user],
            coconique_event: event,
            coconique_event_message: target_context[:message],
            coconique_safety_check_session: target_context[:safety_check_session],
            target_type: target_context[:target_type],
            target_public_id: target_context[:target_public_id],
            reason: normalized_reason,
            detail: params[:detail],
            severity: severity_for_reason(normalized_reason),
            report_phase: report_phase,
            event_status_at_report: event&.status,
            reporter_role: event.present? ? reporter_role_for(event) : "member",
            snapshot: base_snapshot(target_context)
          )
        end

        def resolve_target_context!
          target_type = params[:targetType].presence || params[:target_type].presence || params[:kind].presence

          case target_type.to_s
          when "event"
            event = find_event_by_public_id!(params[:eventId] || params[:event_id] || params[:targetId] || params[:target_id])
            {
              target_type: :event,
              target_public_id: event.public_id,
              event: event,
              reported_user: event.host,
              message: nil,
              safety_check_session: nil
            }
          when "user"
            user = User.find(params[:userId] || params[:user_id] || params[:reportedUserId] || params[:reported_user_id] || params[:targetId] || params[:target_id])
            event = optional_event
            {
              target_type: :user,
              target_public_id: user.id.to_s,
              event: event,
              reported_user: user,
              message: nil,
              safety_check_session: nil
            }
          when "message"
            message = CoconiqueEventMessage.includes(:user, :coconique_event).find_by!(public_id: params[:messageId] || params[:message_id] || params[:targetId] || params[:target_id])
            ensure_can_report_message!(message)
            {
              target_type: :message,
              target_public_id: message.public_id,
              event: message.coconique_event,
              reported_user: message.user,
              message: message,
              safety_check_session: nil
            }
          when "safety_check"
            session = current_user.coconique_safety_check_sessions.includes(:coconique_event).find_by!(public_id: params[:safetyCheckSessionId] || params[:safety_check_session_id] || params[:targetId] || params[:target_id])
            {
              target_type: :safety_check,
              target_public_id: session.public_id,
              event: session.coconique_event,
              reported_user: session.coconique_event&.host,
              message: nil,
              safety_check_session: session
            }
          else
            raise ActionController::ParameterMissing, :targetType
          end
        end

        def normalized_reason
          reason = params[:reason].to_s
          return reason if CoconiqueReport.reasons.key?(reason)

          "other"
        end

        def severity_for_reason(reason)
          case reason.to_s
          when "danger_or_anxiety"
            :urgent
          when "harassment", "external_contact", "solicitation", "gambling_inducement", "impersonation_or_false_info"
            :high
          when "content_mismatch", "no_show_or_late", "romantic_or_pickup"
            :normal
          else
            :low
          end
        end

        def optional_event
          event_id = params[:eventId] || params[:event_id]
          return nil if event_id.blank?

          find_event_by_public_id!(event_id)
        end

        def find_event_by_public_id!(public_id)
          CoconiqueEvent.find_by!(public_id: public_id)
        end

        def ensure_can_report_message!(message)
          event = message.coconique_event
          return true if current_user.admin? || event.hosted_by?(current_user)
          return true if event.coconique_participation_requests.approved.exists?(user_id: current_user.id)

          raise ActiveRecord::RecordNotFound
        end

        def reporter_role_for(event)
          return "admin" if current_user.admin?
          return "host" if event.hosted_by?(current_user)
          return "participant" if event.coconique_participation_requests.approved.exists?(user_id: current_user.id)
          return "applicant" if event.coconique_participation_requests.where(user_id: current_user.id).exists?

          "viewer"
        end

        def phase_for_event(event)
          return :unknown_phase if event.starts_at.blank? || event.ends_at.blank?
          return :before_event if Time.current < event.starts_at
          return :during_event if Time.current <= event.ends_at

          # 参加者チャットは終了後30日間を通常連絡期間として残す。
          return :after_event if event.ends_at + 30.days >= Time.current

          :after_room_closed
        end

        def base_snapshot(context)
          event = context[:event]
          message = context[:message]
          user = context[:reported_user]
          session = context[:safety_check_session]

          {
            reported_at: Time.current.iso8601,
            event: event && event_snapshot(event),
            reported_user: user && user_snapshot(user),
            message: message && message_snapshot(message),
            safety_check_session: session && safety_check_snapshot(session),
            chat_log: event && chat_log_snapshot(event),
            reporter: user_snapshot(current_user)
          }.compact
        end

        def create_evidences!(report)
          snapshot = report.snapshot || {}
          if snapshot["event"].present? || snapshot[:event].present?
            report.coconique_report_evidences.create!(evidence_type: :event_snapshot, metadata: snapshot["event"] || snapshot[:event])
          end
          if snapshot["message"].present? || snapshot[:message].present?
            message_snapshot_data = snapshot["message"] || snapshot[:message]
            report.coconique_report_evidences.create!(evidence_type: :message_snapshot, body: message_snapshot_data[:body] || message_snapshot_data["body"], metadata: message_snapshot_data)
          end
          if snapshot["reported_user"].present? || snapshot[:reported_user].present?
            report.coconique_report_evidences.create!(evidence_type: :user_snapshot, metadata: snapshot["reported_user"] || snapshot[:reported_user])
          end
          if snapshot["safety_check_session"].present? || snapshot[:safety_check_session].present?
            report.coconique_report_evidences.create!(evidence_type: :safety_check_snapshot, metadata: snapshot["safety_check_session"] || snapshot[:safety_check_session])
          end
          if snapshot["chat_log"].present? || snapshot[:chat_log].present?
            chat_log_data = snapshot["chat_log"] || snapshot[:chat_log]
            report.coconique_report_evidences.create!(
              evidence_type: :chat_log_snapshot,
              body: Array(chat_log_data[:messages] || chat_log_data["messages"]).map { |message| "[#{message[:created_at] || message["created_at"]}] #{message[:user_display_name] || message["user_display_name"]}: #{message[:body] || message["body"]}" }.join("\n"),
              metadata: chat_log_data
            )
          end
        end

        def event_snapshot(event)
          {
            public_id: event.public_id,
            title: event.title,
            status: event.status,
            category_key: event.category_key,
            area: event.area,
            starts_at: event.starts_at&.iso8601,
            ends_at: event.ends_at&.iso8601,
            host_id: event.host_id,
            host_display_name: event.host_display_name,
            summary: event.summary,
            image_urls: event.image_urls
          }
        end

        def user_snapshot(user)
          profile = user.user_profile
          {
            id: user.id,
            email_sha256: OpenSSL::Digest::SHA256.hexdigest(user.email.to_s.downcase),
            display_name: profile&.display_name || user.email.to_s.split("@").first,
            status: user.status,
            role: user.role,
            avatar_url: profile&.avatar_url,
            created_at: user.created_at&.iso8601
          }
        end

        def message_snapshot(message)
          {
            public_id: message.public_id,
            body: message.body,
            kind: message.kind,
            image_urls: message.image_urls,
            user_id: message.user_id,
            created_at: message.created_at&.iso8601,
            edited_at: message.edited_at&.iso8601
          }
        end

        def chat_log_snapshot(event)
          messages = event.coconique_event_messages.includes(user: :user_profile).order(created_at: :asc).last(80)

          {
            captured_at: Time.current.iso8601,
            message_count: messages.size,
            truncated: event.coconique_event_messages.count > messages.size,
            messages: messages.map do |message|
              profile = message.user&.user_profile
              {
                public_id: message.public_id,
                body: message.body,
                kind: message.kind,
                image_urls: message.image_urls,
                user_id: message.user_id,
                user_display_name: profile&.display_name || message.user&.email.to_s.split("@").first,
                created_at: message.created_at&.iso8601,
                edited_at: message.edited_at&.iso8601
              }
            end
          }
        end

        def safety_check_snapshot(session)
          {
            public_id: session.public_id,
            status: session.status,
            response_kind: session.response_kind,
            role: session.role,
            due_at: session.due_at&.iso8601,
            answered_at: session.answered_at&.iso8601,
            escalated_at: session.escalated_at&.iso8601,
            help_note: session.help_note
          }
        end

        def serialize_report_receipt(report)
          {
            "id" => report.public_id,
            "targetType" => report.target_type,
            "reason" => report.reason,
            "status" => report.status,
            "severity" => report.severity,
            "createdAt" => report.created_at&.iso8601
          }
        end
      end
    end
  end
end
