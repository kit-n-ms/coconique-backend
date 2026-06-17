require "cgi"

class AuthMailer < ApplicationMailer
  def email_verification(user, token, to_email: nil, subject: "メールアドレス確認のお願い")
    @user = user
    @token = token
    @url = build_url(
      ENV.fetch(
        "FRONTEND_EMAIL_VERIFICATION_URL",
        "http://localhost:5173/auth/email-verifications/confirm"
      ),
      token
    )

    mail(
      to: to_email.presence || @user.email,
      subject: subject
    )
  end

  def password_reset(user, token)
    @user = user
    @token = token
    @url = build_url(
      ENV.fetch(
        "FRONTEND_PASSWORD_RESET_URL",
        "http://localhost:5173/auth/password-resets/confirm"
      ),
      token
    )

    mail(
      to: @user.email,
      subject: "パスワード再設定のご案内"
    )
  end

  private

  def build_url(base_url, token)
    separator = base_url.include?("?") ? "&" : "?"
    "#{base_url}#{separator}token=#{CGI.escape(token)}"
  end
end