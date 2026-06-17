require "test_helper"

class StripeWebhookTest < ActionDispatch::IntegrationTest
  include StripeWebhookTestHelper

  setup do
    @app_key = ENV.fetch("CURRENT_APP_KEY", "sample_app")
    @user = User.create!(
      email: "stripe-#{SecureRandom.hex(6)}@example.test",
      password: "password123456",
      password_confirmation: "password123456",
      email_verified_at: Time.current
    )

    @product = CreditProduct.create!(
      app_key: @app_key,
      code: "deposit-webhook-#{SecureRandom.hex(4)}",
      name: "Webhook deposit",
      description: "Webhook test",
      amount_jpy: 1000,
      credits: 1000,
      active: true,
      display_order: 1
    )

    @stripe_customer = StripeCustomer.create!(
      user: @user,
      stripe_customer_id: "cus_test_#{SecureRandom.hex(8)}",
      livemode: false
    )

    @payment = PaymentCheckoutSession.create!(
      user: @user,
      credit_product: @product,
      stripe_customer: @stripe_customer,
      stripe_checkout_session_id: "cs_test_#{SecureRandom.hex(8)}",
      status: "open",
      amount_total: 1000,
      currency: "jpy",
      credits: 1000,
      success_url: "http://localhost:5173/billing/success",
      cancel_url: "http://localhost:5173/billing/cancel",
      metadata: { app_key: @app_key, product_code: @product.code }
    )
  end

  test "checkout.session.completed adds credit once" do
    session = FakeStripeSession.new(
      id: @payment.stripe_checkout_session_id,
      payment_status: "paid",
      payment_intent: "pi_test_#{SecureRandom.hex(8)}"
    )

    event = FakeStripeEvent.new(
      id: "evt_test_#{SecureRandom.hex(8)}",
      type: "checkout.session.completed",
      object: session
    )

    stub_stripe_event(event) do
      post "/webhooks/stripe",
        params: "{}",
        headers: {
          "Stripe-Signature" => "test"
        }
    end

    assert_response :success

    balance = CreditBalance.find_by!(user: @user, app_key: @app_key)
    assert_equal 1000, balance.balance
    assert_equal 1, CreditTransaction.where(user: @user, app_key: @app_key).count

    stub_stripe_event(event) do
      post "/webhooks/stripe",
        params: "{}",
        headers: {
          "Stripe-Signature" => "test"
        }
    end

    assert_response :success

    assert_equal 1000, balance.reload.balance
    assert_equal 1, CreditTransaction.where(user: @user, app_key: @app_key).count
  end



  test "subscription checkout waits for invoice.paid before monthly host tickets" do
    CoconiqueBilling.ensure_products!
    product = CreditProduct.find_by!(app_key: CoconiqueBilling::APP_KEY, code: CoconiqueBilling::FOUNDER_BETA_PRODUCT_CODE)
    user = User.create!(
      email: "stripe-subscription-#{SecureRandom.hex(6)}@example.test",
      password: "password123456",
      password_confirmation: "password123456",
      email_verified_at: Time.current
    )
    stripe_customer = StripeCustomer.create!(
      user: user,
      stripe_customer_id: "cus_sub_#{SecureRandom.hex(8)}",
      livemode: false
    )
    payment = PaymentCheckoutSession.create!(
      user: user,
      credit_product: product,
      stripe_customer: stripe_customer,
      stripe_checkout_session_id: "cs_sub_#{SecureRandom.hex(8)}",
      status: "open",
      checkout_mode: "subscription",
      amount_total: CoconiqueBilling::FOUNDER_BETA_FIRST_MONTH_JPY,
      currency: "jpy",
      credits: CoconiqueBilling::MONTHLY_HOST_TICKET_GRANT,
      success_url: "http://localhost:5173/billing/success",
      cancel_url: "http://localhost:5173/billing/cancel",
      metadata: {
        app_key: CoconiqueBilling::APP_KEY,
        product_code: product.code,
        product_kind: "founder_beta_subscription",
        checkout_mode: "subscription",
        stripe_price_id: "price_founder_test"
      }
    )

    subscription_id = "sub_test_#{SecureRandom.hex(8)}"
    checkout_session = FakeStripeSession.new(
      id: payment.stripe_checkout_session_id,
      payment_status: "paid",
      subscription: subscription_id,
      customer: stripe_customer.stripe_customer_id,
      invoice: "in_test_#{SecureRandom.hex(8)}"
    )

    stub_stripe_event(FakeStripeEvent.new(id: "evt_cs_#{SecureRandom.hex(8)}", type: "checkout.session.completed", object: checkout_session)) do
      post "/webhooks/stripe", params: "{}", headers: { "Stripe-Signature" => "test" }
    end

    assert_response :success
    assert_equal subscription_id, user.reload.coconique_stripe_subscription_id
    assert_equal "incomplete", user.coconique_subscription_status
    assert_nil CreditBalance.find_by(user: user, app_key: CoconiqueBilling::APP_KEY)

    period_start = Time.zone.parse("2026-06-12 00:00:00").to_i
    period_end = Time.zone.parse("2026-07-12 00:00:00").to_i
    invoice = FakeStripeInvoice.new(
      id: "in_paid_#{SecureRandom.hex(8)}",
      customer: stripe_customer.stripe_customer_id,
      subscription: subscription_id,
      payment_intent: "pi_test_#{SecureRandom.hex(8)}",
      amount_paid: 100,
      currency: "jpy",
      billing_reason: "subscription_create",
      period_start: period_start,
      period_end: period_end,
      metadata: {
        app_key: CoconiqueBilling::APP_KEY,
        product_code: product.code,
        payment_checkout_session_id: payment.id,
        user_id: user.id
      },
      lines: FakeStripeLines.new(
        data: [
          FakeStripeLine.new(
            price: FakeStripePrice.new(id: "price_founder_test", recurring: { interval: "month" }),
            period: { start: period_start, end: period_end }
          )
        ]
      )
    )

    stub_stripe_event(FakeStripeEvent.new(id: "evt_invoice_#{SecureRandom.hex(8)}", type: "invoice.paid", object: invoice)) do
      post "/webhooks/stripe", params: "{}", headers: { "Stripe-Signature" => "test" }
    end

    assert_response :success
    balance = CreditBalance.find_by!(user: user, app_key: CoconiqueBilling::APP_KEY)
    assert_equal CoconiqueBilling::MONTHLY_HOST_TICKET_GRANT, balance.balance
    assert_equal invoice.id, user.reload.coconique_subscription_latest_invoice_id
    assert_equal Time.zone.at(period_end).to_i, user.coconique_subscription_current_period_ends_at.to_i

    subscription = FakeStripeSubscription.new(
      id: subscription_id,
      customer: stripe_customer.stripe_customer_id,
      status: "active",
      current_period_start: period_start,
      current_period_end: period_end,
      cancel_at_period_end: false
    )

    stub_stripe_event(FakeStripeEvent.new(id: "evt_sub_#{SecureRandom.hex(8)}", type: "customer.subscription.updated", object: subscription)) do
      post "/webhooks/stripe", params: "{}", headers: { "Stripe-Signature" => "test" }
    end

    assert_response :success
    assert_equal "active", user.reload.coconique_subscription_status
    assert user.coconique_billing_active?
  end

  test "paid subscription evidence repairs incomplete local status" do
    user = User.create!(
      email: "stripe-repair-#{SecureRandom.hex(6)}@example.test",
      password: "password123456",
      password_confirmation: "password123456",
      email_verified_at: Time.current,
      card_registered_at: Time.current,
      coconique_subscription_plan: "founder_beta",
      coconique_subscription_status: :incomplete,
      coconique_subscription_started_at: 1.hour.ago,
      coconique_subscription_current_period_started_at: 1.hour.ago,
      coconique_subscription_current_period_ends_at: 1.month.from_now,
      coconique_subscription_last_payment_at: 1.hour.ago
    )

    assert user.coconique_billing_active?
    CoconiqueBilling.repair_paid_subscription_state!(user)
    assert_equal "active", user.reload.coconique_subscription_status
  end

  test "signature verification error returns bad request" do
    error = Stripe::SignatureVerificationError.new("bad signature", "sig")

    stub_stripe_construct_event_error(error) do
      post "/webhooks/stripe",
        params: "{}",
        headers: {
          "Stripe-Signature" => "bad"
        }
    end

    assert_response :bad_request
  end
end
