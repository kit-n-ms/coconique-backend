module Api
  module V1
    module Billing
      class CheckoutSessionsController < ApplicationController
        before_action :require_login!

        def create
          app_key = params.fetch(:app_key, ENV.fetch("CURRENT_APP_KEY", "sample_app"))
          CoconiqueBilling.ensure_products! if CoconiqueBilling.coconique_app_key?(app_key)

          product = CreditProduct.active.find_by!(
            app_key: app_key,
            code: params.require(:product_code)
          )

          if CoconiqueBilling.coconique_app_key?(app_key) && CoconiqueBilling.host_ticket_product?(product)
            begin
              CoconiqueBilling.ensure_additional_host_ticket_purchase_allowed!(current_user)
            rescue CoconiqueBilling::AdditionalHostTicketPurchaseUnavailable => e
              return render_error(
                code: "COCONIQUE_ADDITIONAL_HOST_TICKET_PURCHASE_UNAVAILABLE",
                message: e.message,
                status: :unprocessable_entity,
                data: {
                  host_ticket_balance: current_user.coconique_host_ticket_balance,
                  additional_host_ticket_price_jpy: CoconiqueBilling::ADDITIONAL_HOST_TICKET_JPY,
                  additional_host_ticket_expires_in_days: CoconiqueBilling::ADDITIONAL_HOST_TICKET_EXPIRES_IN_DAYS,
                  additional_host_ticket_purchase_limit_per_period: CoconiqueBilling::MAX_ADDITIONAL_HOST_TICKET_PURCHASES_PER_PERIOD,
                  additional_host_ticket_purchases_this_period: CoconiqueBilling.additional_host_ticket_purchases_count(current_user)
                }
              )
            end
          end

          stripe_customer = fake_checkout_enabled? ? ensure_fake_stripe_customer! : StripeCustomer.ensure_for!(user: current_user)

          success_url = safe_checkout_url(
            params[:success_url],
            ENV.fetch("STRIPE_SUCCESS_URL", "http://localhost:5173/billing/success?session_id={CHECKOUT_SESSION_ID}")
          )

          cancel_url = safe_checkout_url(
            params[:cancel_url],
            ENV.fetch("STRIPE_CANCEL_URL", "http://localhost:5173/billing/cancel")
          )

          payment = current_user.payment_checkout_sessions.create!(
            credit_product: product,
            stripe_customer: stripe_customer,
            status: "created",
            amount_total: product.amount_jpy,
            currency: "jpy",
            credits: product.credits,
            success_url: success_url,
            cancel_url: cancel_url,
            metadata: {
              app_key: app_key,
              product_code: product.code,
              product_kind: CoconiqueBilling.product_kind(product)
            }
          )

          checkout_session_payload = fake_checkout_enabled? ? create_fake_checkout_session!(payment, product) : create_stripe_checkout_session!(payment, product)

          AuditLog.record!(
            user: current_user,
            action: fake_checkout_enabled? ? "billing.checkout_session.fake_created" : "billing.checkout_session.created",
            request: request,
            target: payment,
            metadata: {
              stripe_checkout_session_id: payment.stripe_checkout_session_id,
              product_code: product.code,
              amount_jpy: product.amount_jpy,
              credits: product.credits
            }
          )

          render_success(
            {
              checkout_session: checkout_session_payload
            },
            status: :created
          )
        end

        def fake_complete
          unless fake_checkout_enabled? || ActiveModel::Type::Boolean.new.cast(ENV["COCONIQUE_ALLOW_FAKE_CHECKOUT_COMPLETE"])
            return render_error(
              code: "FAKE_CHECKOUT_DISABLED",
              message: "この環境では模擬決済完了処理は利用できません。",
              status: :forbidden
            )
          end

          payment = current_user.payment_checkout_sessions.find(params[:id])

          begin
            CoconiqueBilling.complete_checkout_session!(
              payment,
              stripe_payment_status: "paid",
              stripe_payment_intent: "fake_pi_#{SecureRandom.hex(8)}",
              fake_checkout: true
            )
          rescue CoconiqueBilling::AdditionalHostTicketPurchaseUnavailable => e
            return render_error(
              code: "COCONIQUE_ADDITIONAL_HOST_TICKET_PURCHASE_UNAVAILABLE",
              message: e.message,
              status: :unprocessable_entity
            )
          end

          AuditLog.record!(
            user: current_user,
            action: "billing.checkout_session.fake_completed",
            request: request,
            target: payment,
            metadata: {
              stripe_checkout_session_id: payment.stripe_checkout_session_id,
              amount_jpy: payment.amount_total,
              credits: payment.credits
            }
          )

          render_success(
            {
              checkout_session: checkout_session_json(payment.reload),
              next_url: checkout_return_url(payment.success_url, payment.stripe_checkout_session_id)
            }
          )
        end

        private

        def ensure_fake_stripe_customer!
          return current_user.stripe_customer if current_user.stripe_customer.present?

          current_user.create_stripe_customer!(
            stripe_customer_id: "fake_cus_#{SecureRandom.hex(12)}",
            livemode: false
          )
        end

        def create_stripe_checkout_session!(payment, product)
          metadata = {
            payment_checkout_session_id: payment.id,
            user_id: current_user.id,
            app_key: payment.metadata.fetch("app_key"),
            product_code: product.code
          }

          session = Stripe::Checkout::Session.create(
            customer: payment.stripe_customer.stripe_customer_id,
            mode: "payment",
            client_reference_id: payment.id.to_s,
            success_url: payment.success_url,
            cancel_url: payment.cancel_url,
            line_items: [
              {
                quantity: 1,
                price_data: {
                  currency: "jpy",
                  unit_amount: product.amount_jpy,
                  product_data: {
                    name: product.name,
                    description: product.description
                  }
                }
              }
            ],
            metadata: metadata,
            payment_intent_data: {
              metadata: metadata
            }
          )

          payment.update!(
            stripe_checkout_session_id: session.id,
            status: session.status || "open",
            expires_at: Time.at(session.expires_at)
          )

          checkout_session_json(payment.reload).merge(url: session.url)
        end

        def create_fake_checkout_session!(payment, _product)
          fake_session_id = "fake_cs_#{SecureRandom.hex(12)}"
          payment.update!(
            stripe_checkout_session_id: fake_session_id,
            status: "open",
            expires_at: 30.minutes.from_now,
            metadata: payment.metadata.merge("fake_checkout" => true)
          )

          checkout_session_json(payment.reload).merge(url: fake_checkout_url(payment))
        end

        def complete_payment_checkout_session!(payment, stripe_payment_status:, stripe_payment_intent:)
          CoconiqueBilling.complete_checkout_session!(
            payment,
            stripe_payment_status: stripe_payment_status,
            stripe_payment_intent: stripe_payment_intent,
            fake_checkout: fake_checkout_enabled?
          )
        end

        def checkout_session_json(payment)
          {
            id: payment.id,
            stripe_checkout_session_id: payment.stripe_checkout_session_id,
            url: nil,
            status: payment.status,
            amount_total: payment.amount_total,
            currency: payment.currency,
            credits: payment.credits,
            product_code: payment.credit_product&.code,
            product_name: payment.credit_product&.name,
            product_kind: payment.metadata["product_kind"] || CoconiqueBilling.product_kind(payment.credit_product),
            description: payment.credit_product&.description
          }
        end

        def fake_checkout_url(payment)
          frontend_origin = ENV.fetch("FRONTEND_APP_URL", "http://localhost:5173").sub(%r{/\z}, "")
          query = {
            session_id: payment.id,
            cancel_url: payment.cancel_url,
            amount_total: payment.amount_total,
            currency: payment.currency,
            credits: payment.credits,
            product_code: payment.credit_product&.code,
            product_name: payment.credit_product&.name,
            product_kind: payment.metadata["product_kind"] || CoconiqueBilling.product_kind(payment.credit_product)
          }.compact.to_query
          "#{frontend_origin}/billing/fake-checkout?#{query}"
        end

        def checkout_return_url(url, stripe_checkout_session_id)
          url.to_s.gsub("{CHECKOUT_SESSION_ID}", stripe_checkout_session_id.to_s)
        end

        def safe_checkout_url(value, fallback)
          raw = value.to_s.strip.presence || fallback
          uri = URI.parse(raw)
          return raw if uri.relative?
          return raw if %w[http https].include?(uri.scheme) && allowed_checkout_host?(uri.host)

          fallback
        rescue URI::InvalidURIError
          fallback
        end

        def allowed_checkout_host?(host)
          allowed_hosts = ENV.fetch("CHECKOUT_ALLOWED_HOSTS", "localhost,127.0.0.1").split(",").map(&:strip)
          allowed_hosts.include?(host.to_s)
        end

        def fake_checkout_enabled?
          Rails.env.development? || Rails.env.test? || Stripe.api_key.blank? || ActiveModel::Type::Boolean.new.cast(ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"])
        end
      end
    end
  end
end
