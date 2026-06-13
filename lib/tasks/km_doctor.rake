# lib/tasks/km_doctor.rake

namespace :km do
  desc "Check runtime configuration for local/staging/production"
  task doctor: :environment do
    result = KmDoctor.new.run
    puts result[:lines].join("\n")
    abort "km:doctor failed" unless result[:ok]
  end
end

class KmDoctor
  Check = Struct.new(:name, :ok, :message, keyword_init: true)

  def run
    checks = [
      check_database,
      check_queue_database,
      check_solid_queue_tables,
      check_mail_provider,
      check_resend_webhook,
      check_stripe,
      check_frontend,
      check_cookies,
      check_product_identity
    ]

    lines = []
    lines << "KM Auth Starter Doctor"
    lines << "Rails.env: #{Rails.env}"
    lines << ""

    checks.each do |check|
      mark = check.ok ? "✅" : "❌"
      lines << "#{mark} #{check.name}: #{check.message}"
    end

    lines << ""
    lines << "Expected mail runtime: MAIL_PROVIDER=#{ENV.fetch("MAIL_PROVIDER", Rails.env.production? ? "resend" : "file")}, delivery_method=#{ActionMailer::Base.delivery_method}"

    {
      ok: checks.all?(&:ok),
      lines: lines
    }
  end

  private

  def check_database
    ActiveRecord::Base.connection.select_value("SELECT 1")
    ok("database", "primary database is reachable")
  rescue StandardError => e
    ng("database", e)
  end

  def check_queue_database
    SolidQueue::Job.connection.select_value("SELECT 1")
    ok("queue_database", "Solid Queue database is reachable")
  rescue StandardError => e
    ng("queue_database", e)
  end

  def check_solid_queue_tables
    tables = %w[solid_queue_jobs solid_queue_ready_executions solid_queue_failed_executions]
    missing = tables.reject { |table| SolidQueue::Job.connection.data_source_exists?(table) }

    return ok("solid_queue_tables", "required tables exist") if missing.empty?

    Check.new(name: "solid_queue_tables", ok: false, message: "missing: #{missing.join(", ")}")
  rescue StandardError => e
    ng("solid_queue_tables", e)
  end

  def check_mail_provider
    provider = ENV.fetch("MAIL_PROVIDER", Rails.env.production? ? "resend" : "file")
    delivery_method = ActionMailer::Base.delivery_method.to_s

    case provider
    when "resend"
      missing = []
      missing << "RESEND_API_KEY" if ENV["RESEND_API_KEY"].blank?
      missing << "MAIL_FROM" if ENV["MAIL_FROM"].blank?
      missing << "delivery_method=resend_custom" unless delivery_method == "resend_custom"

      return ok("mail_provider", "resend / resend_custom") if missing.empty?

      Check.new(name: "mail_provider", ok: false, message: "missing or invalid: #{missing.join(", ")}")
    when "file"
      return ok("mail_provider", "file delivery") if delivery_method == "file"

      Check.new(name: "mail_provider", ok: false, message: "MAIL_PROVIDER=file but delivery_method=#{delivery_method}")
    when "test"
      return ok("mail_provider", "test delivery") if delivery_method == "test"

      Check.new(name: "mail_provider", ok: false, message: "MAIL_PROVIDER=test but delivery_method=#{delivery_method}")
    when "postmark"
      missing = []
      missing << "POSTMARK_API_TOKEN" if ENV["POSTMARK_API_TOKEN"].blank?
      missing << "MAIL_FROM" if ENV["MAIL_FROM"].blank?
      missing << "delivery_method=postmark" unless delivery_method == "postmark"
      return ok("mail_provider", "postmark") if missing.empty?

      Check.new(name: "mail_provider", ok: false, message: "missing or invalid: #{missing.join(", ")}")
    else
      Check.new(name: "mail_provider", ok: false, message: "unknown MAIL_PROVIDER=#{provider}")
    end
  end

  def check_resend_webhook
    provider = ENV.fetch("MAIL_PROVIDER", Rails.env.production? ? "resend" : "file")

    if provider == "resend" && ENV["RESEND_WEBHOOK_SECRET"].blank?
      return Check.new(name: "resend_webhook", ok: false, message: "RESEND_WEBHOOK_SECRET is missing")
    end

    ok("resend_webhook", provider == "resend" ? "configured" : "not required for MAIL_PROVIDER=#{provider}")
  end

  def check_stripe
    missing = []
    missing << "STRIPE_SECRET_KEY" if ENV["STRIPE_SECRET_KEY"].blank?
    missing << "STRIPE_WEBHOOK_SECRET" if ENV["STRIPE_WEBHOOK_SECRET"].blank?
    missing << "STRIPE_SUCCESS_URL" if ENV["STRIPE_SUCCESS_URL"].blank?
    missing << "STRIPE_CANCEL_URL" if ENV["STRIPE_CANCEL_URL"].blank?

    return ok("stripe", "configured") if missing.empty?

    required = Rails.env.production? || ENV["REQUIRE_STRIPE_CONFIG"] == "true"
    Check.new(name: "stripe", ok: !required, message: "missing: #{missing.join(", ")}#{required ? "" : " (allowed outside production)"}")
  end

  def check_frontend
    missing = []
    missing << "FRONTEND_ORIGIN or CORS_ALLOWED_ORIGINS" if ENV["FRONTEND_ORIGIN"].blank? && ENV["CORS_ALLOWED_ORIGINS"].blank?
    missing << "FRONTEND_EMAIL_VERIFICATION_URL" if ENV["FRONTEND_EMAIL_VERIFICATION_URL"].blank?
    missing << "FRONTEND_PASSWORD_RESET_URL" if ENV["FRONTEND_PASSWORD_RESET_URL"].blank?

    return ok("frontend", "configured") if missing.empty?

    Check.new(name: "frontend", ok: false, message: "missing: #{missing.join(", ")}")
  end

  def check_cookies
    missing = []
    missing << "AUTH_COOKIE_NAME" if ENV["AUTH_COOKIE_NAME"].blank?
    missing << "CSRF_COOKIE_NAME" if ENV["CSRF_COOKIE_NAME"].blank?

    if Rails.env.production? && ENV.fetch("AUTH_COOKIE_SECURE", "true") != "true"
      missing << "AUTH_COOKIE_SECURE=true"
    end

    return ok("cookies", "configured") if missing.empty?

    Check.new(name: "cookies", ok: false, message: "missing or invalid: #{missing.join(", ")}")
  end

  def check_product_identity
    missing = []
    missing << "CURRENT_APP_KEY" if ENV["CURRENT_APP_KEY"].blank?
    missing << "CURRENT_TERMS_VERSION" if ENV["CURRENT_TERMS_VERSION"].blank?
    missing << "CURRENT_PRIVACY_VERSION" if ENV["CURRENT_PRIVACY_VERSION"].blank?

    return ok("product_identity", "#{ENV.fetch("CURRENT_APP_KEY", "unknown")}") if missing.empty?

    Check.new(name: "product_identity", ok: false, message: "missing: #{missing.join(", ")}")
  end

  def ok(name, message)
    Check.new(name: name, ok: true, message: message)
  end

  def ng(name, error)
    Check.new(name: name, ok: false, message: "#{error.class}: #{error.message}")
  end
end
