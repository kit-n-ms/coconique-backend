namespace :coconique do
  namespace :staging do
    Check = Struct.new(:name, :ok, :severity, :message, keyword_init: true)

    def staging_bool(key, default = "false")
      ActiveModel::Type::Boolean.new.cast(ENV.fetch(key, default))
    end

    def staging_env(key)
      ENV.fetch(key, "").to_s.strip
    end

    def staging_mask(value)
      value = value.to_s.strip
      return "(blank)" if value.blank?
      return "set" if value.length <= 12

      "#{value[0, 7]}...#{value[-4, 4]}"
    end

    def staging_check(name, ok, message, severity: :error)
      Check.new(name: name, ok: ok, severity: severity, message: message)
    end

    def staging_host_from_url(value)
      return nil if value.blank?

      URI.parse(value).host
    rescue URI::InvalidURIError
      nil
    end

    def expected_cookie_domain_from_host(host)
      host = host.to_s.strip
      return nil if host.blank?

      parts = host.split(".")

      if parts.length >= 4 && parts[1] == "stg"
        return ".#{parts[1..].join(".")}"
      end

      return ".#{parts[-2..].join(".")}" if parts.length >= 3

      nil
    end

    desc "Check Coconique staging environment before Stripe/Didit real integration tests"
    task doctor: :environment do
      app_env = staging_env("APP_ENV")
      frontend_origin = staging_env("FRONTEND_ORIGIN")
      cors_allowed_origins = staging_env("CORS_ALLOWED_ORIGINS")
      vite_public_origin = staging_env("VITE_COCONIQUE_PUBLIC_APP_ORIGIN")
      identity_return_url = staging_env("COCONIQUE_IDENTITY_PUBLIC_RETURN_URL")
      portal_return_url = staging_env("STRIPE_BILLING_PORTAL_RETURN_URL")
      checkout_allowed_hosts = staging_env("CHECKOUT_ALLOWED_HOSTS")
      frontend_host = staging_host_from_url(frontend_origin)
      expected_cookie_domain = staging_env("EXPECTED_COOKIE_DOMAIN").presence || expected_cookie_domain_from_host(frontend_host)

      checks = []
      checks << staging_check("CURRENT_APP_KEY", staging_env("CURRENT_APP_KEY") == "coconique", "CURRENT_APP_KEY=#{staging_env("CURRENT_APP_KEY").presence || "(blank)"} / expected coconique")
      checks << staging_check("Rails env", Rails.env.production?, "Rails.env=#{Rails.env}. Render staging should use RAILS_ENV=production because config/environments/staging.rb is not provided.")
      checks << staging_check("APP_ENV", app_env == "staging", "APP_ENV=#{app_env.presence || "(blank)"} / expected staging")
      checks << staging_check("FRONTEND_ORIGIN", frontend_origin.start_with?("https://"), "FRONTEND_ORIGIN=#{frontend_origin.presence || "(blank)"} / expected https staging web origin")
      checks << staging_check("CORS_ALLOWED_ORIGINS", frontend_origin.present? && cors_allowed_origins.split(",").map(&:strip).include?(frontend_origin), "CORS_ALLOWED_ORIGINS should include #{frontend_origin.presence || "the staging web origin"}")
      checks << staging_check("cookie names", staging_env("AUTH_COOKIE_NAME") == "coconique_session" && staging_env("CSRF_COOKIE_NAME") == "coconique_csrf", "AUTH_COOKIE_NAME=#{staging_env("AUTH_COOKIE_NAME").presence || "(blank)"}, CSRF_COOKIE_NAME=#{staging_env("CSRF_COOKIE_NAME").presence || "(blank)"}")
      checks << staging_check("cookie domain", expected_cookie_domain.present? && staging_env("AUTH_COOKIE_DOMAIN") == expected_cookie_domain, "AUTH_COOKIE_DOMAIN=#{staging_env("AUTH_COOKIE_DOMAIN").presence || "(blank)"} / expected #{expected_cookie_domain || "shared parent domain"}. Required because app and api are separate subdomains and the Web reads the CSRF cookie.")
      checks << staging_check("secure cookies", staging_env("AUTH_COOKIE_SECURE") == "true", "AUTH_COOKIE_SECURE=#{staging_env("AUTH_COOKIE_SECURE").presence || "(blank)"} / expected true")
      checks << staging_check("unsafe origin guard", staging_env("REQUIRE_ORIGIN_FOR_UNSAFE_REQUESTS") == "true", "REQUIRE_ORIGIN_FOR_UNSAFE_REQUESTS=#{staging_env("REQUIRE_ORIGIN_FOR_UNSAFE_REQUESTS").presence || "(blank)"} / expected true")
      checks << staging_check("fake Stripe disabled", !staging_bool("COCONIQUE_USE_FAKE_STRIPE_CHECKOUT", "true"), "COCONIQUE_USE_FAKE_STRIPE_CHECKOUT=#{staging_env("COCONIQUE_USE_FAKE_STRIPE_CHECKOUT").presence || "(blank)"} / expected false")
      checks << staging_check("fake identity disabled", !staging_bool("COCONIQUE_USE_FAKE_IDENTITY", "false") && !staging_bool("COCONIQUE_ALLOW_FAKE_IDENTITY", "false"), "COCONIQUE_USE_FAKE_IDENTITY=#{staging_env("COCONIQUE_USE_FAKE_IDENTITY").presence || "(blank)"}, COCONIQUE_ALLOW_FAKE_IDENTITY=#{staging_env("COCONIQUE_ALLOW_FAKE_IDENTITY").presence || "(blank)"} / expected false,false")
      checks << staging_check("SMS not required", staging_env("COCONIQUE_SMS_PROVIDER").blank? || staging_env("COCONIQUE_SMS_PROVIDER") == "fake", "COCONIQUE_SMS_PROVIDER=#{staging_env("COCONIQUE_SMS_PROVIDER").presence || "(blank)"}. SMS is dormant for initial release.", severity: :warn)

      checks << staging_check("Stripe billing provider", staging_env("COCONIQUE_BILLING_PROVIDER") == "stripe", "COCONIQUE_BILLING_PROVIDER=#{staging_env("COCONIQUE_BILLING_PROVIDER").presence || "(blank)"} / expected stripe")
      checks << staging_check("Stripe test keys", staging_env("STRIPE_SECRET_KEY").start_with?("sk_test_") && staging_env("STRIPE_PUBLISHABLE_KEY").start_with?("pk_test_"), "STRIPE_SECRET_KEY=#{staging_mask(staging_env("STRIPE_SECRET_KEY"))}, STRIPE_PUBLISHABLE_KEY=#{staging_mask(staging_env("STRIPE_PUBLISHABLE_KEY"))} / staging should use Test mode")
      checks << staging_check("Stripe IDs", staging_env("STRIPE_PRICE_FOUNDER_MONTHLY").start_with?("price_") && staging_env("STRIPE_PRICE_HOST_TICKET").start_with?("price_") && staging_env("STRIPE_COUPON_FIRST_MONTH_100").present?, "Price/Coupon IDs must come from the same Stripe Test mode account as STRIPE_SECRET_KEY")
      checks << staging_check("Stripe webhook secret", staging_env("STRIPE_WEBHOOK_SECRET").start_with?("whsec_"), "STRIPE_WEBHOOK_SECRET=#{staging_mask(staging_env("STRIPE_WEBHOOK_SECRET"))} / expected whsec_...")
      checks << staging_check("Stripe Tax OFF", staging_env("STRIPE_TAX_ENABLED") == "false", "STRIPE_TAX_ENABLED=#{staging_env("STRIPE_TAX_ENABLED").presence || "(blank)"} / expected false")
      checks << staging_check("Billing Portal return", portal_return_url.start_with?("https://") && (frontend_host.blank? || staging_host_from_url(portal_return_url) == frontend_host), "STRIPE_BILLING_PORTAL_RETURN_URL=#{portal_return_url.presence || "(blank)"} / expected staging web origin")

      checks << staging_check("Checkout allowed hosts", frontend_host.present? && checkout_allowed_hosts.split(",").map(&:strip).include?(frontend_host), "CHECKOUT_ALLOWED_HOSTS should include #{frontend_host || "the staging web host"}")

      checks << staging_check("Didit primary", staging_env("COCONIQUE_IDENTITY_PROVIDER_PRIMARY") == "didit", "COCONIQUE_IDENTITY_PROVIDER_PRIMARY=#{staging_env("COCONIQUE_IDENTITY_PROVIDER_PRIMARY").presence || "(blank)"} / expected didit")
      checks << staging_check("Didit credentials", staging_env("DIDIT_API_KEY").present? && staging_env("DIDIT_WORKFLOW_ID_STANDARD").present? && staging_env("DIDIT_WEBHOOK_SECRET").present?, "DIDIT_API_KEY / DIDIT_WORKFLOW_ID_STANDARD / DIDIT_WEBHOOK_SECRET must be set")
      checks << staging_check("Didit return URL", identity_return_url.start_with?("https://") && identity_return_url.end_with?("/identity/return"), "COCONIQUE_IDENTITY_PUBLIC_RETURN_URL=#{identity_return_url.presence || "(blank)"} / expected https://staging-web/identity/return")
      checks << staging_check("My Number OFF", staging_env("DIDIT_MY_NUMBER_CARD_ENABLED") == "false", "DIDIT_MY_NUMBER_CARD_ENABLED=#{staging_env("DIDIT_MY_NUMBER_CARD_ENABLED").presence || "(blank)"} / expected false")
      checks << staging_check("Didit CRL workaround OFF", staging_env("DIDIT_SSL_ALLOW_CRL_FAILURE") == "false", "DIDIT_SSL_ALLOW_CRL_FAILURE=#{staging_env("DIDIT_SSL_ALLOW_CRL_FAILURE").presence || "(blank)"} / staging should not use local SSL workaround")

      secret = staging_env("COCONIQUE_REENTRY_SIGNAL_SECRET")
      checks << staging_check("Reentry signal secret", secret.length >= 32 && !secret.include?("change-me"), "COCONIQUE_REENTRY_SIGNAL_SECRET must be a long fixed random secret. Current length=#{secret.length}")
      checks << staging_check("Stripe card fingerprint capture", staging_bool("COCONIQUE_CAPTURE_STRIPE_CARD_FINGERPRINT", "true"), "COCONIQUE_CAPTURE_STRIPE_CARD_FINGERPRINT=#{staging_env("COCONIQUE_CAPTURE_STRIPE_CARD_FINGERPRINT").presence || "(blank)"} / expected true", severity: :warn)

      puts "== Coconique staging doctor =="
      puts "Rails.env: #{Rails.env}"
      puts "Checked at: #{Time.current.iso8601}"
      puts

      checks.each do |check|
        mark = if check.ok
          "OK"
        elsif check.severity == :warn
          "WARN"
        else
          "NG"
        end
        puts "#{mark} #{check.name}: #{check.message}"
      end

      errors = checks.reject(&:ok).select { |check| check.severity != :warn }
      warnings = checks.reject(&:ok).select { |check| check.severity == :warn }

      puts
      puts "Errors: #{errors.size}, Warnings: #{warnings.size}"
      puts "Next: bin/rails coconique:stripe:verify_remote" if errors.empty?
      puts "Next: bin/rails coconique:identity:doctor" if errors.empty?

      abort "coconique:staging:doctor failed" if errors.any?
    end

    desc "Print staging manual test order for Stripe and Didit"
    task checklist: :environment do
      puts <<~TEXT
        == Coconique staging real integration test order ==

        1. Deploy API and Web with staging env vars.
        2. Run:
           bin/rails db:migrate
           bin/rails coconique:doctor
           bin/rails coconique:staging:doctor
           bin/rails coconique:stripe:doctor
           bin/rails coconique:stripe:verify_remote
           bin/rails coconique:identity:doctor
        3. Confirm Cloudflare Access behavior:
           - app.stg.coconique.jp is protected.
           - api.stg.coconique.jp is protected for browser/API access.
           - /webhooks/stripe and /webhooks/didit are bypassed and protected by provider signatures.
           - OPTIONS preflight is not blocked.
        4. Open staging Web in a private browser window.
        5. Create a new general user.
        6. Complete Stripe Checkout with a Stripe test card.
        7. Confirm Stripe webhook reaches /webhooks/stripe and host tickets become 5.
        8. Open Billing Portal from settings and confirm card management page opens.
        9. Start Didit verification from safety registration.
        10. Complete Japanese driver license/passport/residence-card + live capture flow.
        11. Confirm /webhooks/didit receives the event, or sync reflects identityVerified=true.
        12. Confirm canApplyOrPublish=true.
        13. Create and publish an event with venueName.
        14. Confirm unverified/unpaid user receives blurred/protected details and API does not leak restricted fields.
        15. Submit participation request, approve, check chat and safety check paths.
        16. Test cancel, report, withdrawal, BAN, and reentry signal blocklist paths.
      TEXT
    end
  end
end
