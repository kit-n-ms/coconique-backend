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
end
