module Api
  module V1
    module Admin
      class CoconiqueSafetyCheckSessionsController < BaseController
        def index
          scope = CoconiqueSafetyCheckSession
            .includes(:user, :coconique_event, :coconique_participation_request, coconique_emergency_contact_notifications: :coconique_emergency_contact)
            .order(due_at: :desc, id: :desc)

          scope = scope.where(status: params[:status]) if params[:status].present? && CoconiqueSafetyCheckSession.statuses.key?(params[:status])
          scope = scope.where(role: params[:role]) if params[:role].present? && CoconiqueSafetyCheckSession.roles.key?(params[:role])

          sessions, pagination = paginated(scope)

          render_success(
            {
              safety_check_sessions: sessions.map { |session| admin_safety_check_session_json(session) },
              pagination: pagination
            }
          )
        end

        def show
          session = CoconiqueSafetyCheckSession
            .includes(:user, :coconique_event, :coconique_participation_request, coconique_emergency_contact_notifications: :coconique_emergency_contact)
            .find_by!(public_id: params[:id])

          render_success({ safety_check_session: admin_safety_check_session_json(session, detail: true) })
        end

        private

        def admin_safety_check_session_json(session, detail: false)
          event = session.coconique_event
          user = session.user
          profile = user.user_profile

          payload = {
            id: session.public_id,
            status: session.status,
            role: session.role,
            due_at: session.due_at,
            next_reminder_at: session.next_reminder_at,
            reminders_sent_count: session.reminders_sent_count,
            extended_count: session.extended_count,
            answered_at: session.answered_at,
            escalated_at: session.escalated_at,
            help_note: session.help_note,
            event: {
              id: event.public_id,
              title: event.title,
              starts_at: event.starts_at,
              ends_at: event.ends_at,
              status: event.status
            },
            user: {
              id: user.id,
              email: user.email,
              display_name: profile&.display_name
            },
            created_at: session.created_at,
            updated_at: session.updated_at
          }

          return payload unless detail

          payload.merge(
            metadata: session.metadata,
            notifications: session.coconique_emergency_contact_notifications.order(created_at: :desc).map do |notification|
              {
                id: notification.public_id,
                kind: notification.kind,
                status: notification.status,
                sent_at: notification.sent_at,
                error_message: notification.error_message,
                contact_email: notification.coconique_emergency_contact.email,
                contact_name: notification.coconique_emergency_contact.name,
                created_at: notification.created_at
              }
            end
          )
        end
      end
    end
  end
end
