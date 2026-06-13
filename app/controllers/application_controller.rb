class ApplicationController < ActionController::API
  include ActionController::Cookies

  before_action :verify_allowed_origin!
  before_action :verify_csrf_token!

  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
  rescue_from ActionController::TooManyRequests, with: :render_too_many_requests

  private

  def current_user
    current_auth_session&.user
  end

  def current_auth_session
    return @current_auth_session if defined?(@current_auth_session)

    token = cookies.signed[auth_cookie_name]
    return @current_auth_session = nil if token.blank?

    digest = AuthSession.digest(token)

    @current_auth_session =
      AuthSession
        .includes(user: :user_profile)
        .active
        .find_by(session_token_digest: digest)
  end

  def require_login!
    return true if current_user.present?

    render_error(
      code: "UNAUTHORIZED",
      message: "認証が必要です。",
      status: :unauthorized
    )

    false
  end

  def sign_in!(user)
    session, session_token, csrf_token = AuthSession.create_for!(
      user: user,
      request: request
    )

    cookies.signed[auth_cookie_name] = auth_cookie_options(session.expires_at).merge(
      value: session_token
    )

    set_csrf_cookie!(
      token: csrf_token,
      expires_at: session.expires_at
    )

    user.update!(last_login_at: Time.current)

    AuditLog.record!(
      user: user,
      action: "auth.login",
      request: request,
      target: session
    )

    session
  end

  def sign_out!
    if current_auth_session.present?
      AuditLog.record!(
        user: current_user,
        action: "auth.logout",
        request: request,
        target: current_auth_session
      )
    end

    current_auth_session&.revoke!
    delete_auth_cookie!
    delete_csrf_cookie!
  end

  def issue_anonymous_csrf_cookie!
    token = AuthSession.generate_token

    set_csrf_cookie!(
      token: token,
      expires_at: 1.hour.from_now
    )

    token
  end

  def issue_session_csrf_cookie!
    return issue_anonymous_csrf_cookie! if current_auth_session.blank?

    token = current_auth_session.rotate_csrf_token!

    set_csrf_cookie!(
      token: token,
      expires_at: current_auth_session.expires_at
    )

    token
  end

  def render_success(data = {}, status: :ok)
    render json: {
      ok: true,
      data: data
    }, status: status
  end

  def render_error(code:, message:, status:, data: nil)
    payload = {
      ok: false,
      error: {
        code: code,
        message: message
      }
    }
    payload[:data] = data if data.present?

    render json: payload, status: status
  end

  def render_bad_request(_exception = nil)
    render_error(
      code: "BAD_REQUEST",
      message: "リクエスト内容を確認してください。",
      status: :bad_request
    )
  end

  def render_not_found(_exception = nil)
    render_error(
      code: "NOT_FOUND",
      message: "対象が見つかりません。",
      status: :not_found
    )
  end

  def render_record_invalid(_exception = nil)
    render_error(
      code: "VALIDATION_FAILED",
      message: "入力内容を確認してください。",
      status: :unprocessable_entity
    )
  end

  def render_rate_limited
    render_error(
      code: "RATE_LIMITED",
      message: "リクエストが集中しています。少し時間をおいて再度お試しください。",
      status: :too_many_requests
    )
  end

  def render_too_many_requests(_exception = nil)
    render_rate_limited
  end

  def development_debug(payload)
    return {} unless Rails.env.development?

    {
      debug: payload
    }
  end

  def verify_csrf_token!
    return if safe_request?

    unless valid_csrf_token?
      return render_error(
        code: "INVALID_CSRF_TOKEN",
        message: "リクエストの検証に失敗しました。ページを再読み込みして再度お試しください。",
        status: :forbidden
      )
    end
  end

  def valid_csrf_token?
    if current_auth_session.present?
      valid_session_csrf_token?
    else
      valid_anonymous_csrf_token?
    end
  end

  def valid_session_csrf_token?
    header_token = csrf_header_token

    return false if header_token.blank?
    return false if current_auth_session.csrf_token_digest.blank?

    secure_digest_equal?(
      current_auth_session.csrf_token_digest,
      AuthSession.digest(header_token)
    )
  end

  def valid_anonymous_csrf_token?
    cookie_token = cookies[csrf_cookie_name]
    header_token = csrf_header_token

    return false if cookie_token.blank?
    return false if header_token.blank?

    secure_digest_equal?(
      AuthSession.digest(cookie_token),
      AuthSession.digest(header_token)
    )
  end

  def csrf_header_token
    request.headers["X-CSRF-Token"].to_s
  end

  def secure_digest_equal?(a, b)
    ActiveSupport::SecurityUtils.secure_compare(a.to_s, b.to_s)
  rescue ArgumentError
    false
  end

  def safe_request?
    request.get? || request.head? || request.options?
  end

  def auth_cookie_name
    ENV.fetch("AUTH_COOKIE_NAME", "km_auth_starter_session")
  end

  def csrf_cookie_name
    ENV.fetch("CSRF_COOKIE_NAME", "km_auth_starter_csrf")
  end

  def auth_cookie_options(expires_at)
    options = {
      httponly: true,
      secure: auth_cookie_secure?,
      same_site: auth_cookie_same_site,
      expires: expires_at,
      path: "/"
    }

    options[:domain] = auth_cookie_domain if auth_cookie_domain.present?

    options
  end

  def csrf_cookie_options(expires_at)
    options = {
      httponly: false,
      secure: auth_cookie_secure?,
      same_site: auth_cookie_same_site,
      expires: expires_at,
      path: "/"
    }

    options[:domain] = auth_cookie_domain if auth_cookie_domain.present?

    options
  end

  def set_csrf_cookie!(token:, expires_at:)
    cookies[csrf_cookie_name] = csrf_cookie_options(expires_at).merge(
      value: token
    )
  end

  def delete_auth_cookie!
    options = {
      path: "/",
      secure: auth_cookie_secure?,
      same_site: auth_cookie_same_site
    }

    options[:domain] = auth_cookie_domain if auth_cookie_domain.present?

    cookies.delete(auth_cookie_name, options)
  end

  def delete_csrf_cookie!
    options = {
      path: "/",
      secure: auth_cookie_secure?,
      same_site: auth_cookie_same_site
    }

    options[:domain] = auth_cookie_domain if auth_cookie_domain.present?

    cookies.delete(csrf_cookie_name, options)
  end

  def auth_cookie_secure?
    ENV.fetch(
      "AUTH_COOKIE_SECURE",
      Rails.env.production? ? "true" : "false"
    ) == "true"
  end

  def auth_cookie_same_site
    ENV.fetch("AUTH_COOKIE_SAME_SITE", "lax").to_sym
  end

  def auth_cookie_domain
    ENV["AUTH_COOKIE_DOMAIN"].presence
  end

  def allowed_origins
    ENV.fetch(
      "CORS_ALLOWED_ORIGINS",
      "http://localhost:5173,http://127.0.0.1:5173"
    ).split(",").map(&:strip)
  end

  def verify_allowed_origin!
    return if safe_request?

    origin = request.headers["Origin"]

    return if origin.blank? && !require_origin_for_unsafe_requests?
    return if origin.present? && allowed_origins.include?(origin)

    render_error(
      code: "INVALID_ORIGIN",
      message: "許可されていないリクエスト元です。",
      status: :forbidden
    )
  end

  def require_origin_for_unsafe_requests?
    ENV.fetch(
      "REQUIRE_ORIGIN_FOR_UNSAFE_REQUESTS",
      Rails.env.production? ? "true" : "false"
    ) == "true"
  end
end