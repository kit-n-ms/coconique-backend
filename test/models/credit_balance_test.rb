require "test_helper"

class CreditBalanceTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(
      email: "balance-#{SecureRandom.hex(6)}@example.test",
      password: "password123456",
      password_confirmation: "password123456",
      email_verified_at: Time.current
    )

    @balance = CreditBalance.find_or_create_for!(user: @user, app_key: "sample_app")

    @product = CreditProduct.create!(
      app_key: "sample_app",
      code: "deposit-test-#{SecureRandom.hex(4)}",
      name: "Test deposit",
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

    @source = PaymentCheckoutSession.create!(
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
      metadata: { app_key: "sample_app" }
    )
  end

  test "add_credit increments balance and creates transaction" do
    assert_difference -> { CreditTransaction.count }, 1 do
      @balance.add_credit!(amount: 1000, source: @source, description: "テスト購入", metadata: { test: true })
    end

    assert_equal 1000, @balance.reload.balance
    transaction = CreditTransaction.last
    assert_equal "purchase", transaction.transaction_type
    assert_equal 1000, transaction.amount
    assert_equal 1000, transaction.balance_after
  end

  test "add_credit rejects non positive amount" do
    assert_raises(ArgumentError) do
      @balance.add_credit!(amount: 0, source: @source, description: "invalid")
    end
  end
end
