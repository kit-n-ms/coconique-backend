module Api
  module V1
    module Coconique
      class NotificationsController < BaseController
        before_action :set_notification, only: [:update, :destroy]

        def index
          notifications = CoconiqueNotification.sync_for_user!(current_user)
          render_success({
            notifications: notifications.map { |notification| serialize_notification(notification) },
            unread_count: CoconiqueNotification.unread.where(user: current_user).count
          })
        end

        def update
          @notification.mark_read! if truthy_param?(params[:read]) || params[:read].nil?
          render_success({ notification: serialize_notification(@notification.reload) })
        end

        def destroy
          @notification.mark_deleted!
          render_success({ ok: true })
        end

        def read_all
          CoconiqueNotification.sync_for_user!(current_user)
          CoconiqueNotification.unread.where(user: current_user).update_all(read_at: Time.current, updated_at: Time.current)
          render_success({ unread_count: 0 })
        end

        private

        def set_notification
          @notification = current_user.coconique_notifications.visible.find_by!(public_id: params[:id])
        end

        def truthy_param?(value)
          ActiveModel::Type::Boolean.new.cast(value)
        end

        def serialize_notification(notification)
          {
            "id" => notification.public_id,
            "kind" => notification.kind,
            "title" => notification.title,
            "body" => notification.body,
            "linkPath" => notification.link_path,
            "metadata" => notification.metadata || {},
            "readAt" => notification.read_at&.iso8601,
            "deletedAt" => notification.deleted_at&.iso8601,
            "occurredAt" => notification.occurred_at&.iso8601,
            "createdAt" => notification.created_at&.iso8601
          }
        end
      end
    end
  end
end
