module Api
  module V1
    module Coconique
      class FeedbacksController < BaseController
        def index
          eligible = eligible_participation_requests
          submitted = current_user.given_coconique_feedbacks.includes(:host, :coconique_event).ordered_recently.limit(30)

          render_success(
            {
              eligible_participations: eligible.map { |request| serialize_feedback_eligible_participation(request) },
              feedbacks: submitted.map { |feedback| serialize_feedback(feedback) }
            }
          )
        end

        def create
          request_record = find_feedback_participation_request!

          feedback = CoconiqueFeedback.new(
            user: current_user,
            coconique_participation_request: request_record,
            safety_answer: normalized_enum_value(CoconiqueFeedback.safety_answers, params[:safetyAnswer] || params[:safety_answer], "safe"),
            accuracy_answer: normalized_enum_value(CoconiqueFeedback.accuracy_answers, params[:accuracyAnswer] || params[:accuracy_answer], "matched"),
            join_again_answer: normalized_enum_value(CoconiqueFeedback.join_again_answers, params[:joinAgainAnswer] || params[:join_again_answer], "yes"),
            private_note: params[:privateNote] || params[:private_note],
            metadata: {
              source: params[:source].presence || "feedback_form",
              safety_check_session_id: params[:safetyCheckSessionId] || params[:safety_check_session_id]
            }.compact
          )

          if feedback.save
            render_success({ feedback: serialize_feedback(feedback) }, status: :created)
          else
            render_error(
              code: "COCONIQUE_FEEDBACK_INVALID",
              message: feedback.errors.full_messages.first || "安心フィードバックを送信できませんでした。",
              status: :unprocessable_entity
            )
          end
        end

        private

        def eligible_participation_requests
          scope = current_user
            .coconique_participation_requests
            .approved
            .includes(coconique_event: :host)
            .where.not(id: current_user.given_coconique_feedbacks.select(:coconique_participation_request_id))
            .order(created_at: :desc, id: :desc)

          scope.select { |request| feedback_eligible?(request) }.first(20)
        end

        def find_feedback_participation_request!
          if (public_id = params[:participationRequestId].presence || params[:participation_request_id].presence).present?
            return current_user.coconique_participation_requests.approved.find_by!(public_id: public_id)
          end

          if (session_id = params[:safetyCheckSessionId].presence || params[:safety_check_session_id].presence).present?
            session = current_user.coconique_safety_check_sessions.includes(:coconique_event).find_by!(public_id: session_id)
            request = session.coconique_participation_request
            return request if request.present? && request.user_id == current_user.id && request.approved?

            return current_user.coconique_participation_requests.approved.find_by!(coconique_event_id: session.coconique_event_id)
          end

          event_id = params[:eventId].presence || params[:event_id].presence
          raise ActiveRecord::RecordNotFound if event_id.blank?

          event = CoconiqueEvent.find_by!(public_id: event_id)
          current_user.coconique_participation_requests.approved.find_by!(coconique_event_id: event.id)
        end

        def feedback_eligible?(request)
          event = request.coconique_event
          return false if event.blank? || event.host_id.blank? || event.host_id == current_user.id
          return false if event.canceled?
          return false if request.coconique_feedback.present?
          return true if event.finished?

          event.ends_at.present? && event.ends_at <= Time.current
        end

        def normalized_enum_value(values, value, fallback)
          candidate = value.to_s
          values.key?(candidate) ? candidate : fallback
        end

        def serialize_feedback_eligible_participation(request)
          event = request.coconique_event
          {
            "id" => request.public_id,
            "eventId" => event.public_id,
            "event" => serialize_event_card(event),
            "host" => feedback_user_brief_json(event.host),
            "endedAt" => event.ends_at&.iso8601,
            "source" => "participation_request"
          }
        end

        def serialize_feedback(feedback)
          {
            "id" => feedback.public_id,
            "eventId" => feedback.coconique_event&.public_id,
            "participationRequestId" => feedback.coconique_participation_request&.public_id,
            "event" => feedback.coconique_event && serialize_event_card(feedback.coconique_event, include_user_context: false),
            "host" => feedback_user_brief_json(feedback.host),
            "safetyAnswer" => feedback.safety_answer,
            "accuracyAnswer" => feedback.accuracy_answer,
            "joinAgainAnswer" => feedback.join_again_answer,
            "privateNote" => feedback.private_note,
            "status" => feedback.status,
            "needsSupportFollowup" => feedback.needs_support_followup?,
            "softConcern" => feedback.soft_concern?,
            "createdAt" => feedback.created_at&.iso8601
          }
        end

        def feedback_user_brief_json(user)
          return nil if user.blank?

          profile = user.user_profile
          {
            "id" => user.id.to_s,
            "displayName" => profile&.display_name || user.email.to_s.split("@").first,
            "avatarUrl" => profile&.avatar_url,
            "profilePath" => "/app/members/#{user.id}"
          }
        end
      end
    end
  end
end
