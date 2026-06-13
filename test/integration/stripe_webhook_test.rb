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
