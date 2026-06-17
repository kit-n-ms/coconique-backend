namespace :coconique do
  namespace :stripe do
    def coconique_stripe_env_value(*keys)
      keys.lazy.map { |key| ENV[key].to_s.strip.presence }.find(&:present?)
    end

    def coconique_mask(value)
      value = value.to_s.strip
      return "(blank)" if value.blank?
      return "set" if value.length <= 12

      "#{value[0, 7]}...#{value[-4, 4]}"
    end

    desc "Check Coconique Stripe configuration without calling Stripe API"
    task doctor: :environment do
      required = %w[
        STRIPE_SECRET_KEY
        STRIPE_PUBLISHABLE_KEY
        STRIPE_WEBHOOK_SECRET
        STRIPE_PRICE_FOUNDER_MONTHLY
        STRIPE_COUPON_FIRST_MONTH_100
        STRIPE_PRICE_HOST_TICKET
      ]

      recommended = {
        "CURRENT_APP_KEY" => "coconique",
        "COCONIQUE_BILLING_PROVIDER" => "stripe",
        "STRIPE_TAX_ENABLED" => "false",
        "COCONIQUE_USE_FAKE_STRIPE_CHECKOUT" => "false"
      }

      url_vars = %w[
        STRIPE_SUCCESS_URL
        STRIPE_CANCEL_URL
        COCONIQUE_DEVELOPER_COLLABORATOR_CODES
      ]

      puts "== Coconique Stripe doctor =="
      puts "Rails.env: #{Rails.env}"
      puts

      missing = []
      required.each do |key|
        value = ENV[key].to_s.strip
        if value.blank?
          missing << key
          puts "NG #{key}: missing"
        else
          puts "OK #{key}: #{coconique_mask(value)}"
        end
      end

      puts
      recommended.each do |key, expected|
        actual = ENV.fetch(key, "").to_s.strip
        mark = actual == expected ? "OK" : "WARN"
        shown = actual.presence || "(blank)"
        puts "#{mark} #{key}: #{shown}#{actual == expected ? "" : " / expected #{expected}"}"
      end

      puts
      url_vars.each do |key|
        value = ENV.fetch(key, "").to_s.strip
        mark = value.present? ? "OK" : "WARN"
        puts "#{mark} #{key}: #{value.presence || "(blank)"}"
      end

      success_url = ENV.fetch("STRIPE_SUCCESS_URL", "").to_s.strip
      if success_url.present? && !success_url.include?("{CHECKOUT_SESSION_ID}")
        puts "WARN STRIPE_SUCCESS_URL should include {CHECKOUT_SESSION_ID} for post-checkout verification."
      end

      puts
      founder_price = coconique_stripe_env_value("STRIPE_PRICE_FOUNDER_MONTHLY", "STRIPE_PRICE_COCONIQUE_FOUNDER_MONTHLY")
      host_ticket_price = coconique_stripe_env_value("STRIPE_PRICE_HOST_TICKET", "STRIPE_PRICE_COCONIQUE_HOST_TICKET")
      coupon = coconique_stripe_env_value("STRIPE_COUPON_FIRST_MONTH_100", "STRIPE_COUPON_COCONIQUE_FIRST_MONTH_100")

      puts founder_price.to_s.start_with?("price_") ? "OK STRIPE_PRICE_FOUNDER_MONTHLY format: price_..." : "WARN STRIPE_PRICE_FOUNDER_MONTHLY format: Price ID should start with price_"
      puts host_ticket_price.to_s.start_with?("price_") ? "OK STRIPE_PRICE_HOST_TICKET format: price_..." : "WARN STRIPE_PRICE_HOST_TICKET format: Price ID should start with price_"
      puts coupon.present? ? "OK STRIPE_COUPON_FIRST_MONTH_100: #{coconique_mask(coupon)}" : "WARN STRIPE_COUPON_FIRST_MONTH_100: blank"

      puts
      if missing.any?
        abort "Missing required Stripe env vars: #{missing.join(", ")}"
      end

      puts "Stripe env looks ready for Coconique. This task does not call Stripe API."
      puts "To verify that Price/Coupon IDs exist in the current Stripe account/mode, run: bin/rails coconique:stripe:verify_remote"
    end

    desc "Verify Coconique Stripe Price/Coupon IDs by calling Stripe API"
    task verify_remote: :environment do
      secret_key = ENV["STRIPE_SECRET_KEY"].to_s.strip
      abort "STRIPE_SECRET_KEY is missing" if secret_key.blank?

      Stripe.api_key = secret_key

      founder_price_id = coconique_stripe_env_value("STRIPE_PRICE_FOUNDER_MONTHLY", "STRIPE_PRICE_COCONIQUE_FOUNDER_MONTHLY")
      host_ticket_price_id = coconique_stripe_env_value("STRIPE_PRICE_HOST_TICKET", "STRIPE_PRICE_COCONIQUE_HOST_TICKET")
      coupon_id = coconique_stripe_env_value("STRIPE_COUPON_FIRST_MONTH_100", "STRIPE_COUPON_COCONIQUE_FIRST_MONTH_100")

      abort "STRIPE_PRICE_FOUNDER_MONTHLY is missing" if founder_price_id.blank?
      abort "STRIPE_PRICE_HOST_TICKET is missing" if host_ticket_price_id.blank?
      abort "STRIPE_COUPON_FIRST_MONTH_100 is missing" if coupon_id.blank?

      puts "== Coconique Stripe remote verification =="
      puts "Secret key mode: #{secret_key.start_with?("sk_live_") ? "live" : "test/unknown"}"
      puts

      begin
        founder_price = Stripe::Price.retrieve(founder_price_id)
        puts "OK Founder monthly price: #{founder_price.id} amount=#{founder_price.unit_amount} #{founder_price.currency} recurring=#{founder_price.recurring&.interval} livemode=#{founder_price.livemode}"
      rescue Stripe::StripeError => e
        puts "NG Founder monthly price: #{founder_price_id}"
        puts "   #{e.class}: #{e.message}"
      end

      begin
        host_ticket_price = Stripe::Price.retrieve(host_ticket_price_id)
        puts "OK Host ticket price: #{host_ticket_price.id} amount=#{host_ticket_price.unit_amount} #{host_ticket_price.currency} recurring=#{host_ticket_price.recurring&.interval || "none"} livemode=#{host_ticket_price.livemode}"
      rescue Stripe::StripeError => e
        puts "NG Host ticket price: #{host_ticket_price_id}"
        puts "   #{e.class}: #{e.message}"
      end

      begin
        coupon = Stripe::Coupon.retrieve(coupon_id)
        puts "OK First month coupon: #{coupon.id} amount_off=#{coupon.amount_off} #{coupon.currency} percent_off=#{coupon.percent_off || "none"} duration=#{coupon.duration} livemode=#{coupon.livemode}"
      rescue Stripe::StripeError => e
        puts "NG First month coupon: #{coupon_id}"
        puts "   #{e.class}: #{e.message}"
      end

      puts
      puts "Expected: Founder price 430 jpy monthly, host ticket price 1000 jpy one-time, coupon 330 jpy off once."
      puts "If any item is NG, recreate/copy the ID from the same Test/Live mode and same Stripe account as STRIPE_SECRET_KEY."
    end
  end
end
