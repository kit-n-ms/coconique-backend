module Api
  module V1
    module Auth
      class EmailVerificationsController < ApplicationController
        rate_limit(
          to: 3,
          within: 10.minutes,
          only: :create,
          by: -> { current_user&.id || request.remote_ip },
          with: -> { render_rate_limited },
          name: "email_verification_create"
        )

        rate_limit(
          to: 10,
          within: 10.minutes,
          only: :confirm,
          by: -> { request.remote_ip },
          with: -> { render_rate_limited },
          name: "email_verification_confirm"
        )

        before_action :require_login!, only: [:create]

        def create
          if current_user.email_verified?
            return render_success(
              {
                message: "メールアドレスはすでに認証済みです。"
              }
            )
          end

          verification, token = EmailVerification.create_for!(
            user: current_user
          )

          AuthMailer.email_verification(
            current_user,
            token
          ).deliver_later

          AuditLog.record!(
            user: current_user,
            action: "email_verification.created",
            request: request,
            target: verification
          )

          render_success(
            {
              message: "確認メールを送信しました。"
            },
            status: :created
          )
        end

        def confirm
          token = params.require(:token)
          digest = EmailVerification.digest(token)

          verification = EmailVerification.usable.find_by(
            token_digest: digest
          )

          unless verification
            return render_error(
              code: "INVALID_OR_EXPIRED_TOKEN",
              message: "認証リンクが無効、または期限切れです。",
              status: :unprocessable_entity
            )
          end

          verification.confirm!

          AuditLog.record!(
            user: verification.user,
            action: "email_verification.confirmed",
            request: request,
            target: verification
          )

          render_success(
            {
              message: "メールアドレスを認証しました。"
            }
          )
        end
      end
    end
  end
end