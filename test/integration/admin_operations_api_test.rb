require "test_helper"

class AdminOperationsApiTest < ActionDispatch::IntegrationTest
  include JsonResponseHelper
  include AuthRequestHelper

  setup do
    @admin = create_test_user!(email: "admin-#{SecureRandom.hex(4)}@example.test", admin: true)
    @general = create_test_user!(email: "general-#{SecureRandom.hex(4)}@example.test")
    @app_key = ENV.fetch("CURRENT_APP_KEY", "sample_app")

    @credit_balance = CreditBalance.find_or_create_for!(user: @general, app_key: @app_key)
    @credit_balance.add_credit!(
      amount: 100,
      source: @general,
      description: "test credit",
      metadata: { test: true }
    )

    @suppression = EmailSuppression.suppress!(
      email: "bounce@example.test",
      reason: EmailSuppression::REASON_BOUNCED,
      source: EmailWebhookEvent::PROVIDER_RESEND,
      source_event_id: "evt_test_bounced",
      metadata: { test: true }
    )
  end

  test "general user cannot access admin API" do
    login_as!(@general)

    get "/api/v1/admin/users"
    assert_response :forbidden
  end

  test "admin can list users" do
    login_as!(@admin)

    get "/api/v1/admin/users"
    assert_response :success
    assert_equal true, json_body["ok"]
    assert json_body.dig("data", "users").is_a?(Array)
  end

  test "admin can list credit transactions" do
    login_as!(@admin)

    get "/api/v1/admin/billing/credit_transactions?app_key=#{@app_key}"
    assert_response :success
    assert_equal true, json_body["ok"]
    assert json_body.dig("data", "credit_transactions").is_a?(Array)
  end

  test "admin can list email suppressions and delete one" do
    login_as!(@admin)

    get "/api/v1/admin/email_suppressions?email=bounce@example.test"
    assert_response :success
    assert_equal true, json_body["ok"]
    assert_equal "bounce@example.test", json_body.dig("data", "email_suppressions", 0, "email")

    delete "/api/v1/admin/email_suppressions/#{@suppression.id}", headers: json_headers(csrf_headers)
    assert_response :success
    assert_equal false, EmailSuppression.suppressed?("bounce@example.test")
  end
end
