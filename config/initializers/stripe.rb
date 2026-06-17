stripe_secret_key = ENV["STRIPE_SECRET_KEY"].to_s.strip
Stripe.api_key = stripe_secret_key if stripe_secret_key.present?
