class HealthController < ActionController::API
  def up
    render json: {
      ok: true,
      status: "ok",
      app: app_name,
      environment: Rails.env,
      time: Time.current.iso8601
    }
  end

  def healthz
    checks = {
      database: check_database,
      queue_database: check_queue_database
    }

    render_check_response(checks, required: checks.keys)
  end

  def readiness
    checks = {
      database: check_database,
      queue_database: check_queue_database,
      solid_queue_tables: check_solid_queue_tables,
      mail_provider: check_mail_provider,
      stripe_config: check_stripe_config,
      resend_webhook_config: check_resend_webhook_config,
      frontend_config: check_frontend_config,
      cookie_config: check_cookie_config
    }

    required = [
      :database,
      :queue_database,
      :solid_queue_tables,
      :mail_provider,
      :frontend_config,
      :cookie_config
    ]

    render_check_response(checks, required: required)
  end

  private

  def render_check_response(checks, required:)
    ok = required.all? { |key| checks.dig(key, :ok) == true }

    render json: {
      ok: ok,
      status: ok ? "ready" : "not_ready",
      app: app_name,
      environment: Rails.env,
      time: Time.current.iso8601,
      checks: checks
    }, status: ok ? :ok : :service_unavailable
  end

  def app_name
    ENV.fetch("APP_NAME", "km_auth_starter_api")
  end

  def check_database
    ActiveRecord::Base.connection.select_value("SELECT 1")
    { ok: true }
  rescue StandardError => e
    { ok: false, error: safe_error(e) }
  end

  def check_queue_database
    return { ok: false, error: "SolidQueue::Job is not loaded" } unless defined?(SolidQueue::Job)

    SolidQueue::Job.connection.select_value("SELECT 1")
    { ok: true }
  rescue StandardError => e
    { ok: false, error: safe_error(e) }
  end

  def check_solid_queue_tables
    return { ok: false, error: "SolidQueue::Job is not loaded" } unless defined?(SolidQueue::Job)

    required_tables = %w[
      solid_queue_jobs
      solid_queue_ready_executions
      solid_queue_failed_executions
    ]

    missing = required_tables.reject do |table_name|
      SolidQueue::Job.connection.data_source_exists?(table_name)
    end

    { ok: missing.empty?, missing: missing }
  rescue StandardError => e
    { ok: false, error: safe_error(e) }
  end

  def check_mail_provider
    provider = ENV.fetch("MAIL_PROVIDER", Rails.env.production? ? "resend" : "file")
    delivery_method = ActionMailer::Base.delivery_method.to_s

    missing = []
    expected_delivery_method = nil

    case provider
    when "resend"
      expected_delivery_method = "resend_custom"
      missing << "RESEND_API_KEY" if ENV["RESEND_API_KEY"].blank?
      missing << "MAIL_FROM" if ENV["MAIL_FROM"].blank?
    when "postmark"
      expected_delivery_method = "postmark"
      missing << "POSTMARK_API_TOKEN" if ENV["POSTMARK_API_TOKEN"].blank?
      missing << "MAIL_FROM" if ENV["MAIL_FROM"].blank?
    when "file"
      expected_delivery_method = "file"
    when "test"
      expected_delivery_method = "test"
    else
      return { ok: false, provider: provider, delivery_method: delivery_method, error: "Unknown MAIL_PROVIDER" }
    end

    method_ok = delivery_method == expected_delivery_method

    {
      ok: missing.empty? && method_ok,
      provider: provider,
      delivery_method: delivery_method,
      expected_delivery_method: expected_delivery_method,
      missing: missing
    }
  end

  def check_stripe_config
    missing = []
    missing << "STRIPE_SECRET_KEY" if ENV["STRIPE_SECRET_KEY"].blank?
    missing << "STRIPE_WEBHOOK_SECRET" if ENV["STRIPE_WEBHOOK_SECRET"].blank?
    missing << "STRIPE_SUCCESS_URL" if ENV["STRIPE_SUCCESS_URL"].blank?
    missing << "STRIPE_CANCEL_URL" if ENV["STRIPE_CANCEL_URL"].blank?

    {
      ok: missing.empty?,
      missing: missing,
      required_for: "billing"
    }
  end

  def check_resend_webhook_config
    provider = ENV.fetch("MAIL_PROVIDER", Rails.env.production? ? "resend" : "file")
    missing = []
    missing << "RESEND_WEBHOOK_SECRET" if provider == "resend" && ENV["RESEND_WEBHOOK_SECRET"].blank?

    {
      ok: missing.empty?,
      missing: missing,
      required_for: "resend_webhook"
    }
  end

  def check_frontend_config
    missing = []
    missing << "FRONTEND_ORIGIN" if ENV["FRONTEND_ORIGIN"].blank? && ENV["CORS_ALLOWED_ORIGINS"].blank?
    missing << "FRONTEND_EMAIL_VERIFICATION_URL" if ENV["FRONTEND_EMAIL_VERIFICATION_URL"].blank?
    missing << "FRONTEND_PASSWORD_RESET_URL" if ENV["FRONTEND_PASSWORD_RESET_URL"].blank?

    { ok: missing.empty?, missing: missing }
  end

  def check_cookie_config
    missing = []
    missing << "AUTH_COOKIE_NAME" if ENV["AUTH_COOKIE_NAME"].blank?
    missing << "CSRF_COOKIE_NAME" if ENV["CSRF_COOKIE_NAME"].blank?

    {
      ok: missing.empty?,
      missing: missing,
      secure: ENV.fetch("AUTH_COOKIE_SECURE", Rails.env.production? ? "true" : "false"),
      same_site: ENV.fetch("AUTH_COOKIE_SAME_SITE", "lax")
    }
  end

  def safe_error(error)
    "#{error.class}: #{error.message}"
  end
end
