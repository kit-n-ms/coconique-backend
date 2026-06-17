require "test_helper"

class BillingApiTest < ActionDispatch::IntegrationTest
  include JsonResponseHelper
  include AuthRequestHelper

  setup do
    @user = create_test_user!
    @app_key = ENV.fetch("CURRENT_APP_KEY", "sample_app")

    CreditProduct.find_or_create_by!(app_key: @app_key, code: "deposit_1000") do |product|
      product.name = "デポジット 1,000円"
      product.description = "テスト用デポジット"
      product.amount_jpy = 1000
      product.credits = 1000
      product.active = true
      product.display_order = 1
    end

    login_as!(@user)
  end

  def post_checkout_session(params)
    post "/api/v1/billing/checkout_sessions",
      params: params.to_json,
      headers: json_headers(csrf_headers)
  end

  def with_stripe_checkout_session_create_stub(replacement)
    singleton_class = class << Stripe::Checkout::Session; self; end
    original_method = Stripe::Checkout::Session.method(:create)

    singleton_class.define_method(:create) do |*args, **kwargs|
      replacement.call(*args, **kwargs)
    end

    yield
  ensure
    singleton_class.define_method(:create) do |*args, **kwargs|
      original_method.call(*args, **kwargs)
    end
  end

  test "credit products can be fetched" do
    get "/api/v1/billing/credit_products?app_key=#{@app_key}"
    assert_response :success
    assert_equal true, json_body["ok"]
    assert json_body.dig("data", "credit_products").is_a?(Array)
  end

  test "credit balance starts from zero" do
    get "/api/v1/billing/balance?app_key=#{@app_key}"
    assert_response :success
    assert_equal 0, json_body.dig("data", "credit_balance", "balance")
  end

  test "credit transactions can be fetched" do
    get "/api/v1/billing/credit_transactions?app_key=#{@app_key}"
    assert_response :success
    assert_equal [], json_body.dig("data", "credit_transactions")
  end
  test "explicit fake checkout false uses Stripe configuration instead of development fallback" do
    CoconiqueBilling.ensure_products!
    old_flag = ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"]
    old_key = Stripe.api_key
    ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"] = "false"
    Stripe.api_key = nil

    post_checkout_session(
      app_key: CoconiqueBilling::APP_KEY,
      product_code: CoconiqueBilling::FOUNDER_BETA_PRODUCT_CODE
    )

    assert_response :unprocessable_entity
    assert_equal "STRIPE_SECRET_KEY_MISSING", json_body.dig("error", "code")
  ensure
    ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"] = old_flag
    Stripe.api_key = old_key
  end

  test "developer collaborator code forces fake checkout for founder plan" do
    CoconiqueBilling.ensure_products!
    old_flag = ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"]
    old_codes = ENV["COCONIQUE_DEVELOPER_COLLABORATOR_CODES"]
    old_key = Stripe.api_key
    ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"] = "false"
    ENV["COCONIQUE_DEVELOPER_COLLABORATOR_CODES"] = "開発協力メンバー"
    Stripe.api_key = nil

    post_checkout_session(
      app_key: CoconiqueBilling::APP_KEY,
      product_code: CoconiqueBilling::FOUNDER_BETA_PRODUCT_CODE,
      developer_collaborator_code: "開発協力メンバー"
    )

    assert_response :created
    checkout_session = json_body.dig("data", "checkout_session")
    assert_includes checkout_session["url"], "/billing/fake-checkout"

    payment = PaymentCheckoutSession.find(checkout_session["id"])
    assert_equal true, payment.metadata["developer_collaborator_checkout"]
  ensure
    ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"] = old_flag
    ENV["COCONIQUE_DEVELOPER_COLLABORATOR_CODES"] = old_codes
    Stripe.api_key = old_key
  end

  test "invalid developer collaborator code does not fall through to Stripe checkout" do
    CoconiqueBilling.ensure_products!
    old_flag = ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"]
    old_codes = ENV["COCONIQUE_DEVELOPER_COLLABORATOR_CODES"]
    ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"] = "false"
    ENV["COCONIQUE_DEVELOPER_COLLABORATOR_CODES"] = "開発協力メンバー"

    post_checkout_session(
      app_key: CoconiqueBilling::APP_KEY,
      product_code: CoconiqueBilling::FOUNDER_BETA_PRODUCT_CODE,
      developer_collaborator_code: "違うコード"
    )

    assert_response :unprocessable_entity
    assert_equal "INVALID_DEVELOPER_COLLABORATOR_CODE", json_body.dig("error", "code")
  ensure
    ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"] = old_flag
    ENV["COCONIQUE_DEVELOPER_COLLABORATOR_CODES"] = old_codes
  end

  test "Stripe invalid price error is returned as unprocessable entity instead of 500" do
    CoconiqueBilling.ensure_products!
    @user.create_stripe_customer!(stripe_customer_id: "cus_test_existing", livemode: false)

    old_flag = ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"]
    old_price = ENV["STRIPE_PRICE_FOUNDER_MONTHLY"]
    old_coupon = ENV["STRIPE_COUPON_FIRST_MONTH_100"]
    old_key = Stripe.api_key

    ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"] = "false"
    ENV["STRIPE_PRICE_FOUNDER_MONTHLY"] = " price_missing_123 "
    ENV["STRIPE_COUPON_FIRST_MONTH_100"] = "coupon_test"
    Stripe.api_key = "sk_test_dummy"

    with_stripe_checkout_session_create_stub(
      ->(*_args, **_kwargs) { raise Stripe::InvalidRequestError.new("No such price: 'price_missing_123'", "price") }
    ) do
      post_checkout_session(
        app_key: CoconiqueBilling::APP_KEY,
        product_code: CoconiqueBilling::FOUNDER_BETA_PRODUCT_CODE
      )
    end

    assert_response :unprocessable_entity
    assert_equal "STRIPE_CHECKOUT_SESSION_CREATE_FAILED", json_body.dig("error", "code")
    assert_includes json_body.dig("error", "message"), "Price ID"

    payment = @user.payment_checkout_sessions.order(created_at: :desc).first
    assert_equal "failed", payment.status
    assert_equal "price_missing_123", payment.metadata["stripe_price_id"]
  ensure
    ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"] = old_flag
    ENV["STRIPE_PRICE_FOUNDER_MONTHLY"] = old_price
    ENV["STRIPE_COUPON_FIRST_MONTH_100"] = old_coupon
    Stripe.api_key = old_key
  end

end
