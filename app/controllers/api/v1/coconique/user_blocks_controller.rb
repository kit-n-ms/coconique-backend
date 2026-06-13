module Api
  module V1
    module Coconique
      class UserBlocksController < BaseController
        def index
          blocks = CoconiqueUserBlock
            .active
            .where(blocker: current_user)
            .includes(blocked: :user_profile)
            .ordered_recently

          render_success(
            {
              user_blocks: blocks.map { |block| serialize_user_block(block) }
            }
          )
        end

        def create
          target_user = User.active.find(normalized_target_user_id)

          if target_user.id == current_user.id
            return render_error(
              code: "CANNOT_BLOCK_SELF",
              message: "自分自身を遠慮設定にはできません。",
              status: :unprocessable_entity
            )
          end

          report = find_optional_report
          block = nil

          CoconiqueUserBlock.transaction do
            block = CoconiqueUserBlock.active.find_or_initialize_by(
              blocker: current_user,
              blocked: target_user
            )

            block.assign_attributes(
              reason: normalized_reason,
              note: normalized_note,
              coconique_report: report || block.coconique_report,
              metadata: (block.metadata || {}).merge("source" => params[:source].to_s.presence || "member")
            )
            block.save!
          end

          AuditLog.record!(
            user: current_user,
            action: "coconique.user_block.created",
            request: request,
            target: block,
            metadata: { blocked_user_id: target_user.id, report_public_id: report&.public_id }
          )

          render_success(
            {
              user_block: serialize_user_block(block.reload),
              overlapping_events: overlapping_approved_events_with(target_user).map { |event| serialize_event_card(event) }
            },
            status: :created
          )
        end

        def destroy
          block = CoconiqueUserBlock.active.where(blocker: current_user).find_by!(public_id: params[:id])
          block.lift!(user: current_user)

          AuditLog.record!(
            user: current_user,
            action: "coconique.user_block.lifted",
            request: request,
            target: block,
            metadata: { blocked_user_id: block.blocked_id }
          )

          render_success({ user_block: serialize_user_block(block.reload) })
        end

        private

        def normalized_target_user_id
          params[:userId].presence || params[:user_id].presence || params[:blockedUserId].presence || params[:blocked_user_id].presence || params[:targetUserId].presence || params[:target_user_id]
        end

        def normalized_reason
          value = params[:reason].to_s.presence || "other"
          CoconiqueUserBlock::REASON_LABELS.key?(value) ? value : "other"
        end

        def normalized_note
          params[:note].to_s.strip.presence
        end

        def find_optional_report
          value = params[:reportId].presence || params[:report_id].presence
          return nil if value.blank?

          CoconiqueReport.find_by(public_id: value)
        end

        def overlapping_approved_events_with(user)
          event_ids_for_current_user = current_user.coconique_participation_requests.approved.select(:coconique_event_id)
          event_ids_for_target = user.coconique_participation_requests.approved.select(:coconique_event_id)
          CoconiqueEvent
            .where(id: event_ids_for_current_user)
            .where(id: event_ids_for_target)
            .order(starts_at: :asc, id: :asc)
            .limit(20)
        end

        def serialize_user_block(block)
          {
            "id" => block.public_id,
            "reason" => block.reason,
            "reasonLabel" => CoconiqueUserBlock::REASON_LABELS[block.reason] || CoconiqueUserBlock::REASON_LABELS["other"],
            "note" => block.note,
            "active" => block.active?,
            "createdAt" => block.created_at&.iso8601,
            "liftedAt" => block.lifted_at&.iso8601,
            "blockedUser" => serialize_participation_request_user(block.blocked)
          }
        end
      end
    end
  end
end
