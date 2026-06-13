namespace :auth do
  desc "Clean up expired auth sessions and tokens"
  task cleanup_expired: :environment do
    now = Time.current

    deleted_sessions = AuthSession.where("expires_at < ?", now).delete_all
    deleted_email_verifications = EmailVerification.where("expires_at < ?", now).where.not(used_at: nil).delete_all
    deleted_password_resets = PasswordReset.where("expires_at < ?", now).where.not(used_at: nil).delete_all

    puts "Deleted expired auth_sessions: #{deleted_sessions}"
    puts "Deleted expired used email_verifications: #{deleted_email_verifications}"
    puts "Deleted expired used password_resets: #{deleted_password_resets}"
  end

  desc "List unverified users older than 7 days"
  task list_unverified_users: :environment do
    users = User
      .where(email_verified_at: nil)
      .where("created_at < ?", 7.days.ago)
      .order(:created_at)

    users.find_each do |user|
      puts "#{user.id}, #{user.email}, created_at=#{user.created_at}"
    end

    puts "Total: #{users.count}"
  end

  desc "Delete unverified users older than 14 days"
  task cleanup_unverified_users: :environment do
    users = User
      .where(email_verified_at: nil)
      .where("created_at < ?", 14.days.ago)

    count = users.count
    users.destroy_all

    puts "Deleted unverified users: #{count}"
  end
end
