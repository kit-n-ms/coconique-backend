namespace :coconique do
  namespace :admin do
    desc "Grant admin role to a user by EMAIL=..."
    task grant: :environment do
      email = ENV.fetch("EMAIL", "").to_s.strip.downcase
      abort "Usage: bin/rails coconique:admin:grant EMAIL=you@example.com" if email.blank?

      user = User.find_by!(email: email)
      user.update!(role: :admin)

      puts "Granted admin role to #{user.email} (id=#{user.id}). Please log out and log in again in the browser."
    end

    desc "Revoke admin role from a user by EMAIL=..."
    task revoke: :environment do
      email = ENV.fetch("EMAIL", "").to_s.strip.downcase
      abort "Usage: bin/rails coconique:admin:revoke EMAIL=you@example.com" if email.blank?

      user = User.find_by!(email: email)
      user.update!(role: :general)

      puts "Revoked admin role from #{user.email} (id=#{user.id})."
    end
  end
end
