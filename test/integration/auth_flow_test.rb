require "test_helper"

class AuthFlowTest < ActionDispatch::IntegrationTest
  include JsonResponseHelper
  include AuthRequestHelper

  test "signup creates user and me returns current user" do
    request_csrf!
    email = "signup-#{SecureRandom.hex(6)}@example.test"

    post "/api/v1/auth/signup",
      params: { email: email, password: TEST_PASSWORD, password_confirmation: TEST_PASSWORD }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    assert_equal true, json_body["ok"]
    assert_equal email, json_body.dig("data", "user", "email")

    get "/api/v1/auth/me"
    assert_response :success
    assert_equal email, json_body.dig("data", "user", "email")
  end

  test "login and logout flow" do
    user = create_test_user!
    login_as!(user)

    get "/api/v1/auth/me"
    assert_response :success
    assert_equal user.email, json_body.dig("data", "user", "email")

    delete "/api/v1/auth/logout", headers: json_headers(csrf_headers)
    assert_response :success

    get "/api/v1/auth/me"
    assert_response :unauthorized
  end

  test "invalid login does not authenticate" do
    user = create_test_user!
    request_csrf!

    post "/api/v1/auth/login",
      params: { email: user.email, password: "wrong-password" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :unauthorized
  end
end
