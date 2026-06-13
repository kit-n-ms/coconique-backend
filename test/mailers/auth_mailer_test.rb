require "test_helper"

class AuthMailerTest < ActionMailer::TestCase
  def setup
    @user = User.create!(
      email: "mailer-#{SecureRandom.hex(6)}@example.test",
      password: "password123456",
      password_confirmation: "password123456",
      email_verified_at: nil
    )
  end

  test "email_verification" do
    token = "email-verification-token-test"

    mail = AuthMailer.email_verification(@user, token)

    assert_equal [@user.email], mail.to
    assert mail.subject.present?

    body = decoded_body(mail)

    assert_includes body, token
  end

  test "password_reset" do
    token = "password-reset-token-test"

    mail = AuthMailer.password_reset(@user, token)

    assert_equal [@user.email], mail.to
    assert mail.subject.present?

    body = decoded_body(mail)

    assert_includes body, token
  end

  private

  def decoded_body(mail)
    bodies = []

    if mail.multipart?
      mail.parts.each do |part|
        bodies << part.body.decoded
      end
    else
      bodies << mail.body.decoded
    end

    bodies.join("\n")
  end
end