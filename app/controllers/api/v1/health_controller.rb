module Api
  module V1
    class HealthController < ApplicationController
      def index
        render_success(
          {
            app: "km_auth_starter_api",
            status: "ok",
            time: Time.current
          }
        )
      end
    end
  end
end
