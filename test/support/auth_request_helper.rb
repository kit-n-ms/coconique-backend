require "digest"

module AuthRequestHelper
  TEST_PASSWORD = "password123456"

  def csrf_cookie_name
    ENV.fetch("CSRF_COOKIE_NAME", "km_auth_starter_csrf")
  end

  def request_csrf!
    get "/api/v1/auth/csrf"
    assert_response :success
    cookies[csrf_cookie_name] || response.cookies[csrf_cookie_name]
  end

  def csrf_headers
    token = cookies[csrf_cookie_name] || response.cookies[csrf_cookie_name]
    { "X-CSRF-Token" => token.to_s }
  end

  def json_headers(extra = {})
    { "Content-Type" => "application/json" }.merge(extra)
  end

  def create_test_user!(email: "user-#{SecureRandom.hex(6)}@example.test", password: TEST_PASSWORD, verified: true, admin: false, coconique_safety_registered: true)
    now = Time.current
    attributes = {
      email: email,
      password: password,
      password_confirmation: password,
      email_verified_at: verified ? now : nil,
      role: admin ? :admin : :general
    }

    if coconique_safety_registered && verified
      attributes.merge!(
        phone_verification_status: :verified,
        phone_verified_at: now,
        phone_number_digest: Digest::SHA256.hexdigest("+819012345678"),
        identity_verification_status: :verified,
        identity_provider: "test",
        identity_verification_id: "test_identity_#{SecureRandom.hex(8)}",
        identity_verified_at: now,
        age_verified: true,
        age_over_18: true,
        card_registered_at: now,
        coconique_subscription_plan: "founder_beta",
        coconique_subscription_status: :active,
        coconique_subscription_started_at: now,
        coconique_subscription_current_period_started_at: now,
        coconique_subscription_current_period_ends_at: 1.month.from_now,
        coconique_founder_beta_joined_at: now,
        safety_registered_at: now
      )
    end

    user = User.create!(attributes)

    if coconique_safety_registered && verified
      CoconiqueBilling.grant_monthly_host_tickets!(
        user: user,
        source: user,
        force: true,
        metadata: { test_setup: true }
      )
    end

    user
  end

  def login_as!(user, password: TEST_PASSWORD)
    request_csrf!
    post "/api/v1/auth/login",
      params: { email: user.email, password: password }.to_json,
      headers: json_headers(csrf_headers)
    assert_response :success
    user
  end
end
