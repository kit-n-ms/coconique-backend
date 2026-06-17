module Api
  module V1
    module Coconique
      class EventsController < BaseController
        before_action :set_event, only: [:show, :update, :publish, :close, :reopen, :cancel, :finish]
        before_action :require_visible_event!, only: [:show]
        before_action :require_hosted_event!, only: [:update, :publish, :close, :reopen, :cancel, :finish]

        def index
          events = events_without_enryo_scope(CoconiqueEvent.ordered_for_dashboard)
          events = events.where(category_key: params[:category_key]) if params[:category_key].present?
          events = events.where(status: params[:status]) if params[:status].present? && member_visible_status?(params[:status])
          events = events.where(same_gender_only: true) if truthy_param?(params[:sameGenderOnly]) || truthy_param?(params[:same_gender_only])
          events = events.where(same_generation_only: true) if truthy_param?(params[:sameGenerationOnly]) || truthy_param?(params[:same_generation_only])

          area_prefecture = params[:areaPrefecture].presence || params[:area_prefecture].presence
          area_city = params[:areaCity].presence || params[:area_city].presence
          events = events.where(area_prefecture: area_prefecture) if area_prefecture.present?
          events = events.where(area_city: area_city) if area_city.present?

          if params[:q].present?
            query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s)}%"
            events = events.where(
              "title ILIKE :query OR area ILIKE :query OR summary ILIKE :query",
              query: query
            )
          end

          limit = params.fetch(:limit, 30).to_i.clamp(1, 100)

          render_success(
            {
              events: events.limit(limit).map { |event| serialize_event_card(event) }
            }
          )
        end

        def show
          render_success(
            {
              event: serialize_event(@event)
            }
          )
        end

        def create
          event = current_user.hosted_coconique_events.build(attributes_for_create)
          event.status = :draft

          if publish_requested?
            return unless require_publishable_event!(event)
            return unless require_coconique_safety_registration!(action_kind: "publish_event", event: event)
            return unless require_host_ticket_available!(event: event)
          end

          CoconiqueEvent.transaction do
            event.save!
            create_status_log!(
              event: event,
              action: "coconique.event.created_draft",
              from_status: nil,
              to_status: event.status
            )
            if publish_requested?
              return unless consume_host_ticket_for_event!(event)

              previous_status = event.status
              event.publish!
              create_status_log!(
                event: event,
                action: "coconique.event.published",
                from_status: previous_status,
                to_status: event.status
              )
            end
          end

          AuditLog.record!(
            user: current_user,
            action: publish_requested? ? "coconique.event.created_and_published" : "coconique.event.created_draft",
            request: request,
            target: event
          )

          render_success(
            {
              event: serialize_event(event.reload)
            },
            status: :created
          )
        end

        def update
          return unless require_editable_event!(@event)

          @event.update!(event_attributes_from_params.except(:host_display_name))

          AuditLog.record!(
            user: current_user,
            action: "coconique.event.updated",
            request: request,
            target: @event
          )

          render_success(
            {
              event: serialize_event(@event.reload)
            }
          )
        end

        def publish
          return unless require_status_changeable_event!(@event)
          return unless require_publishable_event!(@event)
          return unless require_coconique_safety_registration!(action_kind: "publish_event", event: @event)
          return unless require_host_ticket_available!(event: @event)
          return unless consume_host_ticket_for_event!(@event)

          previous_status = @event.status
          @event.publish!
          record_status_change!("coconique.event.published", @event, from_status: previous_status)

          render_success({ event: serialize_event(@event.reload) })
        end

        def close
          return unless require_status_changeable_event!(@event)

          previous_status = @event.status
          @event.close!
          record_status_change!("coconique.event.closed", @event, from_status: previous_status)

          render_success({ event: serialize_event(@event.reload) })
        end

        def reopen
          return unless require_status_changeable_event!(@event)

          previous_status = @event.status
          @event.reopen!
          record_status_change!("coconique.event.reopened", @event, from_status: previous_status)

          render_success({ event: serialize_event(@event.reload) })
        end

        def cancel
          return unless require_status_changeable_event!(@event)

          previous_status = @event.status
          reason = params[:reason].to_s
          @event.cancel!(reason: reason, cancellation_notice_kind: :host_cancel)
          record_status_change!("coconique.event.canceled", @event, from_status: previous_status, reason: reason)

          render_success({ event: serialize_event(@event.reload) })
        end

        def finish
          return unless require_status_changeable_event!(@event)

          previous_status = @event.status
          @event.finish!
          if @event.canceled? && !@event.approved_participants?
            record_status_change!(
              "coconique.event.auto_canceled_without_approved_participants",
              @event,
              from_status: previous_status,
              reason: @event.cancellation_reason
            )
          else
            record_status_change!("coconique.event.finished", @event, from_status: previous_status)
          end

          render_success({ event: serialize_event(@event.reload) })
        end

        private

        def set_event
          @event = find_event!
        end

        def require_visible_event!
          return true if @event.hosted_by?(current_user) || current_user&.admin?

          existing_request = @event.participation_request_for(current_user)

          unless event_matches_member_visibility?(@event)
            return true if existing_request&.approved?

            return render_error(
              code: "COCONIQUE_EVENT_MEMBER_CONDITION_NOT_MATCHED",
              message: "この募集は募集条件に当てはまるメンバーにのみ表示されています。",
              status: :forbidden
            )
          end

          if enryo_between?(@event.host) || event_has_enryo_participant?(@event)
            return true if existing_request&.approved?

            return render_error(
              code: "COCONIQUE_USER_BLOCKED",
              message: "この募集は現在表示できません。",
              status: :forbidden
            )
          end

          require_publicly_available_event!(@event)
        end

        def require_hosted_event!
          require_event_host!(@event)
        end

        def truthy_param?(value)
          ActiveModel::Type::Boolean.new.cast(value)
        end

        def member_visible_status?(status)
          %w[recruiting confirmed].include?(status.to_s)
        end

        def attributes_for_create
          attrs = event_attributes_from_params
          return attrs if publish_requested?

          apply_draft_defaults(attrs)
        end

        def apply_draft_defaults(attrs)
          start_time = parse_time(attrs[:starts_at]) || 7.days.from_now.change(sec: 0)
          end_time = parse_time(attrs[:ends_at])
          end_time = start_time + 2.hours if end_time.blank? || end_time <= start_time

          recruitment_ends_at = parse_time(attrs[:recruitment_ends_at])
          recruitment_ends_at = nil if recruitment_ends_at.present? && (recruitment_ends_at >= start_time || recruitment_ends_at < Time.current)

          capacity = attrs[:capacity].presence.to_i
          capacity = 4 if capacity <= 0
          min_participants = attrs[:min_participants].presence.to_i
          min_participants = 2 if min_participants <= 0
          min_participants = capacity if min_participants > capacity

          attrs.merge(
            title: attrs[:title].presence || "無題の予定",
            category_key: attrs[:category_key].presence || "walk",
            area: attrs[:area].presence || "未設定",
            venue_name: attrs[:venue_name].presence || nil,
            starts_at: start_time,
            ends_at: end_time,
            recruitment_ends_at: recruitment_ends_at,
            meeting_place: attrs[:meeting_place].presence || "未設定",
            summary: attrs[:summary].presence || "",
            capacity: capacity,
            min_participants: min_participants
          )
        end

        def parse_time(value)
          return nil if value.blank?

          Time.zone.parse(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def require_editable_event!(event)
          return true unless event.canceled? || event.finished?

          render_error(
            code: "EVENT_LOCKED",
            message: "キャンセルまたは終了済みの予定は編集できません。",
            status: :unprocessable_entity
          )

          false
        end

        def require_status_changeable_event!(event)
          return true unless event.canceled? || event.finished?

          render_error(
            code: "EVENT_STATUS_LOCKED",
            message: "キャンセルまたは終了済みの予定はステータスを変更できません。",
            status: :unprocessable_entity
          )

          false
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
          errors << "予定地を入力してください" if event.respond_to?(:venue_name) && event.venue_name.blank?
          errors << "集合場所を入力してください" if event.meeting_place.blank? || event.meeting_place == "未設定"
          errors << "開始日時を未来にしてください" if event.starts_at.blank? || event.starts_at <= Time.current
          errors << "終了日時は開始日時より後にしてください" if event.starts_at.present? && event.ends_at.present? && event.ends_at <= event.starts_at
          errors << "募集締切を入力してください" if event.recruitment_ends_at.blank?
          errors << "募集締切は現在時刻より後にしてください" if event.recruitment_ends_at.present? && event.recruitment_ends_at <= Time.current
          errors << "募集締切は開始日時より前にしてください" if event.recruitment_ends_at.present? && event.starts_at.present? && event.recruitment_ends_at >= event.starts_at
          errors << "最少開催人数は定員以下にしてください" if event.min_participants.present? && event.capacity.present? && event.min_participants > event.capacity
          errors
        end

        def publish_requested?
          ActiveModel::Type::Boolean.new.cast(params[:publish]) || params[:status].to_s == "recruiting"
        end

        def record_status_change!(action, event, from_status: nil, reason: nil)
          create_status_log!(
            event: event,
            action: action,
            from_status: from_status,
            to_status: event.status,
            reason: reason
          )

          AuditLog.record!(
            user: current_user,
            action: action,
            request: request,
            target: event
          )
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
