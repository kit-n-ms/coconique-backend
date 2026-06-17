module Api
  module V1
    module Billing
      class PortalSessionsController < ApplicationController
        before_action :require_login!

        def create
          app_key = params.fetch(:app_key, ENV.fetch("CURRENT_APP_KEY", "sample_app"))

          unless CoconiqueBilling.coconique_app_key?(app_key)
            return render_error(
              code: "UNSUPPORTED_BILLING_APP",
              message: "このアプリの決済設定には対応していません。",
              status: :unprocessable_entity
            )
          end

          if Stripe.api_key.blank?
            return render_error(
              code: "STRIPE_SECRET_KEY_MISSING",
              message: "Stripe Secret Keyが未設定です。STRIPE_SECRET_KEYを設定してください。",
              status: :unprocessable_entity
            )
          end

          stripe_customer = current_user.stripe_customer
          if stripe_customer.blank?
            return render_error(
              code: "STRIPE_CUSTOMER_NOT_FOUND",
              message: "クレジットカード設定を開くには、先に月額利用を開始してください。",
              status: :unprocessable_entity
            )
          end

          return_url = safe_portal_return_url(
            params[:return_url],
            ENV.fetch("STRIPE_BILLING_PORTAL_RETURN_URL", "http://localhost:5173/app/settings")
          )

          session = Stripe::BillingPortal::Session.create(
            customer: stripe_customer.stripe_customer_id,
            return_url: return_url
          )

          AuditLog.record!(
            user: current_user,
            action: "billing.portal_session.created",
            request: request,
            target: stripe_customer,
            metadata: { app_key: app_key }
          )

          render_success(
            {
              portal_session: {
                url: session.url,
                return_url: return_url
              }
            },
            status: :created
          )
        rescue Stripe::StripeError => e
          render_error(
            code: "STRIPE_BILLING_PORTAL_CREATE_FAILED",
            message: "Stripeのカード設定画面を開けませんでした。時間をおいて再度お試しください。",
            status: :unprocessable_entity,
            data: {
              stripe_error_class: e.class.name,
              stripe_error_code: e.respond_to?(:code) ? e.code : nil
            }.compact
          )
        end

        private

        def safe_portal_return_url(value, fallback)
          raw = value.to_s.strip.presence || fallback
          uri = URI.parse(raw)
          return raw if uri.relative?
          return raw if %w[http https].include?(uri.scheme) && allowed_portal_host?(uri.host)

          fallback
        rescue URI::InvalidURIError
          fallback
        end

        def allowed_portal_host?(host)
          allowed_hosts = ENV.fetch("CHECKOUT_ALLOWED_HOSTS", "localhost,127.0.0.1").split(",").map(&:strip)
          allowed_hosts.include?(host.to_s)
        end
      end
    end
  end
end
