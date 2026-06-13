module Api
  module V1
    module Auth
      class PasswordResetsController < ApplicationController
        rate_limit(
          to: 5,
          within: 10.minutes,
          only: :create,
          by: -> {
            email = params[:email].to_s.strip.downcase
            "#{request.remote_ip}:#{email}"
          },
          with: -> { render_rate_limited },
          name: "password_reset_create"
        )

        rate_limit(
          to: 10,
          within: 10.minutes,
          only: :confirm,
          by: -> { request.remote_ip },
          with: -> { render_rate_limited },
          name: "password_reset_confirm"
        )

        def create
          email = params.require(:email).to_s.strip.downcase
          user = User.active.find_by(email: email)

          if user.present?
            reset, token = PasswordReset.create_for!(
              user: user
            )

            AuthMailer.password_reset(
              user,
              token
            ).deliver_later

            AuditLog.record!(
              user: user,
              action: "password_reset.created",
              request: request,
              target: reset
            )
          else
            AuditLog.record!(
              user: nil,
              action: "password_reset.requested_for_unknown_email",
              request: request,
              metadata: {
                email_sha256: OpenSSL::Digest::SHA256.hexdigest(email)
              }
            )
          end

          render_success(
            {
              message: "パスワード再設定手続きが可能な場合、案内を送信しました。"
            }
          )
        end

        def confirm
          token = params.require(:token)
          password = params.require(:password)
          password_confirmation = params.require(:password_confirmation)

          digest = PasswordReset.digest(token)

          reset = PasswordReset.usable.find_by(
            token_digest: digest
          )

          unless reset
            return render_error(
              code: "INVALID_OR_EXPIRED_TOKEN",
              message: "再設定リンクが無効、または期限切れです。",
              status: :unprocessable_entity
            )
          end

          reset.confirm!(
            password: password,
            password_confirmation: password_confirmation
          )

          AuditLog.record!(
            user: reset.user,
            action: "password_reset.confirmed",
            request: request,
            target: reset
          )

          render_success(
            {
              message: "パスワードを更新しました。再度ログインしてください。"
            }
          )
        end
      end
    end
  end
end