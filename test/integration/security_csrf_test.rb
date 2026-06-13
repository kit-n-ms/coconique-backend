require "test_helper"

class SecurityCsrfTest < ActionDispatch::IntegrationTest
  include AuthRequestHelper

  setup do
    @old_allow_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @old_allow_forgery_protection
  end

  test "unsafe auth request without csrf token is rejected" do
    user = create_test_user!

    post "/api/v1/auth/login",
      params: { email: user.email, password: TEST_PASSWORD }.to_json,
      headers: json_headers

    assert_response :forbidden
  end

  test "csrf endpoint issues csrf cookie" do
    request_csrf!
    assert cookies[csrf_cookie_name].present? || response.cookies[csrf_cookie_name].present?
  end
end
