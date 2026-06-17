namespace :coconique do
  namespace :identity do
    desc "Check Coconique identity provider environment variables"
    task doctor: :environment do
      provider = Coconique::IdentityVerifications::ProviderFactory.primary_provider_key
      fallback = Coconique::IdentityVerifications::ProviderFactory.fallback_provider_key
      puts "Coconique identity provider doctor"
      puts "----------------------------------"
      puts "primary:  #{provider}"
      puts "fallback: #{fallback}"
      puts "fake forced: #{ActiveModel::Type::Boolean.new.cast(ENV.fetch("COCONIQUE_USE_FAKE_IDENTITY", "false"))}"

      case provider
      when "didit"
        checks = {
          "DIDIT_API_BASE_URL" => ENV.fetch("DIDIT_API_BASE_URL", "https://verification.didit.me"),
          "DIDIT_API_KEY" => ENV["DIDIT_API_KEY"],
          "DIDIT_WORKFLOW_ID_STANDARD" => ENV["DIDIT_WORKFLOW_ID_STANDARD"],
          "DIDIT_WEBHOOK_SECRET" => ENV["DIDIT_WEBHOOK_SECRET"],
          "DIDIT_MY_NUMBER_CARD_ENABLED" => ENV.fetch("DIDIT_MY_NUMBER_CARD_ENABLED", "false"),
          "DIDIT_SSL_ALLOW_CRL_FAILURE" => ENV.fetch("DIDIT_SSL_ALLOW_CRL_FAILURE", "false"),
          "COCONIQUE_IDENTITY_PUBLIC_RETURN_URL" => ENV["COCONIQUE_IDENTITY_PUBLIC_RETURN_URL"]
        }
        checks.each do |key, value|
          display = value.present? ? "OK" : "MISSING"
          display = value if key.end_with?("ENABLED") || key.end_with?("URL")
          puts "#{key}: #{display}"
        end
        puts "configured?: #{Coconique::IdentityVerifications::DiditProvider.configured?}"
        puts "my_number_enabled?: #{Coconique::IdentityVerifications::DiditProvider.my_number_enabled?}"
        if ActiveModel::Type::Boolean.new.cast(ENV.fetch("DIDIT_SSL_ALLOW_CRL_FAILURE", "false"))
          puts "WARN DIDIT_SSL_ALLOW_CRL_FAILURE is enabled. Use only for local development if OpenSSL fails with unable to get certificate CRL."
        end
      when "quick_trust"
        puts "Quick Trust primary. Current adapter is stub/live-spec waiting mode."
        puts "QUICK_TRUST_STUB_MODE: #{ENV.fetch("QUICK_TRUST_STUB_MODE", "true")}"
        puts "QUICK_TRUST_LIVE_ENABLED: #{ENV.fetch("QUICK_TRUST_LIVE_ENABLED", "false")}"
      when "stripe_identity"
        puts "Stripe Identity primary. STRIPE_SECRET_KEY: #{ENV["STRIPE_SECRET_KEY"].present? ? "OK" : "MISSING"}"
      else
        puts "Using development/fake identity provider."
      end
    end
  end
end
