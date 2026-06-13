module Api
  module V1
    class AppMembershipsController < ApplicationController
      before_action :require_login!

      def index
        memberships = current_user.app_memberships.order(created_at: :asc)

        if params[:app_key].present?
          memberships = memberships.where(app_key: params[:app_key])
        end

        render_success(
          {
            app_memberships: memberships.map { |membership| app_membership_json(membership) }
          }
        )
      end

      def create
        app_key = params.require(:app_key)

        membership = current_user.app_memberships.find_or_initialize_by(
          app_key: app_key
        )

        if membership.new_record?
          membership.status = :active
          membership.started_at = Time.current
          membership.save!

          AuditLog.record!(
            user: current_user,
            action: "app_membership.created",
            request: request,
            target: membership,
            metadata: {
              app_key: app_key
            }
          )
        end

        render_success(
          {
            app_membership: app_membership_json(membership)
          },
          status: membership.previously_new_record? ? :created : :ok
        )
      end

      private

      def app_membership_json(membership)
        {
          id: membership.id,
          app_key: membership.app_key,
          status: membership.status,
          started_at: membership.started_at,
          created_at: membership.created_at
        }
      end
    end
  end
end
