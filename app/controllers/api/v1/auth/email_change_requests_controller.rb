module Api
  module V1
    module Auth
      class EmailChangeRequestsController < ApplicationController
        rate_limit(
          to: 3,
          within: 10.minutes,
          only: :create,
          by: -> { current_user&.id || request.remote_ip },
          with: -> { render_rate_limited },
          name: "email_change_request_create"
        )

        before_action :require_login!

        def create
          new_email = params.require(:email).to_s.strip.downcase

          if new_email.blank? || !new_email.match?(URI::MailTo::EMAIL_REGEXP)
            return render_error(
              code: "INVALID_EMAIL",
              message: "メールアドレスを確認してください。",
              status: :unprocessable_entity,
              data: { fields: { email: ["メールアドレスを確認してください。"] } }
            )
          end

          if new_email == current_user.email
            return render_error(
              code: "EMAIL_UNCHANGED",
              message: "現在のメールアドレスとは別のメールアドレスを入力してください。",
              status: :unprocessable_entity,
              data: { fields: { email: ["現在のメールアドレスとは別のメールアドレスを入力してください。"] } }
            )
          end

          if User.where(email: new_email).where.not(id: current_user.id).exists?
            return render_error(
              code: "EMAIL_ALREADY_TAKEN",
              message: "このメールアドレスはすでに使用されています。",
              status: :unprocessable_entity,
              data: { fields: { email: ["このメールアドレスはすでに使用されています。"] } }
            )
          end

          verification, token = EmailVerification.create_for!(
            user: current_user,
            purpose: EmailVerification::PURPOSE_EMAIL_CHANGE,
            pending_email: new_email
          )

          AuthMailer.email_verification(
            current_user,
            token,
            to_email: new_email,
            subject: "メールアドレス変更確認のお願い"
          ).deliver_later

          AuditLog.record!(
            user: current_user,
            action: "email_change.requested",
            request: request,
            target: verification,
            metadata: {
              pending_email_sha256: OpenSSL::Digest::SHA256.hexdigest(new_email)
            }
          )

          render_success(
            {
              message: "変更先メールアドレスへ確認メールを送信しました。メール内のリンクを開くと変更が完了します。"
            },
            status: :created
          )
        end
      end
    end
  end
end
