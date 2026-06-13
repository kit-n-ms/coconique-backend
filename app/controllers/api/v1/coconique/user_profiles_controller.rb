module Api
  module V1
    module Coconique
      class UserProfilesController < BaseController
        before_action :set_user

        def show
          render_success(
            {
              profile: serialize_member_profile(@user)
            }
          )
        end

        private

        def set_user
          @user = User.active.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error(
            code: "MEMBER_PROFILE_NOT_FOUND",
            message: "このメンバーの紹介ページは表示できません。",
            status: :not_found
          )
        end
      end
    end
  end
end
