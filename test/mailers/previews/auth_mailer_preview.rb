# Preview all emails at http://localhost:3000/rails/mailers/auth_mailer
class AuthMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/auth_mailer/email_verification
  def email_verification
    AuthMailer.email_verification
  end

  # Preview this email at http://localhost:3000/rails/mailers/auth_mailer/password_reset
  def password_reset
    AuthMailer.password_reset
  end
end
