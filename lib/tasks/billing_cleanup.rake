namespace :billing do
  desc "Mark expired checkout sessions as expired"
  task cleanup_expired_checkout_sessions: :environment do
    sessions = PaymentCheckoutSession
      .where.not(expires_at: nil)
      .where.not(status: "completed")
      .where("expires_at < ?", Time.current)

    count = 0

    sessions.find_each do |session|
      session.update!(status: "expired")
      count += 1
    end

    puts "Expired checkout sessions updated: #{count}"
  end

  desc "Show recent Stripe webhook errors"
  task webhook_errors: :environment do
    events = StripeWebhookEvent
      .where.not(processing_error: [nil, ""])
      .order(created_at: :desc)
      .limit(20)

    events.each do |event|
      puts [
        event.id,
        event.stripe_event_id,
        event.event_type,
        event.processing_error,
        event.created_at
      ].join(" | ")
    end

    puts "Total shown: #{events.size}"
  end
end
