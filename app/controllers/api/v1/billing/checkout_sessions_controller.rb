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

          checkout_mode = checkout_mode_for(product)
          developer_collaborator_code = params[:developer_collaborator_code].to_s.strip
          developer_collaborator_code_given = developer_collaborator_code.present?
          unless developer_collaborator_code_allowed?(developer_collaborator_code, product)
            return render_error(
              code: "INVALID_DEVELOPER_COLLABORATOR_CODE",
              message: "開発協力者コードを確認してください。",
              status: :unprocessable_entity
            )
          end

          force_fake_checkout = developer_collaborator_code_given
          use_fake_checkout = fake_checkout_enabled? || force_fake_checkout

          if !use_fake_checkout && Stripe.api_key.blank?
            return render_error(
              code: "STRIPE_SECRET_KEY_MISSING",
              message: "Stripe Secret Keyが未設定です。STRIPE_SECRET_KEYを設定してください。",
              status: :unprocessable_entity
            )
          end

          if !use_fake_checkout && checkout_mode == "subscription" && stripe_price_id_for(product).blank?
            return render_error(
              code: "STRIPE_PRICE_ID_MISSING",
              message: "Founder βプランのStripe Price IDが未設定です。STRIPE_PRICE_FOUNDER_MONTHLYを設定してください。",
              status: :unprocessable_entity
            )
          end

          stripe_customer = use_fake_checkout ? ensure_fake_stripe_customer! : StripeCustomer.ensure_for!(user: current_user)

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
            checkout_mode: checkout_mode,
            amount_total: product.amount_jpy,
            currency: "jpy",
            credits: product.credits,
            success_url: success_url,
            cancel_url: cancel_url,
            metadata: {
              app_key: app_key,
              product_code: product.code,
              product_kind: CoconiqueBilling.product_kind(product),
              checkout_mode: checkout_mode,
              stripe_price_id: stripe_price_id_for(product),
              stripe_coupon_id: checkout_mode == "subscription" ? founder_intro_coupon_id : nil,
              developer_collaborator_checkout: force_fake_checkout,
              developer_collaborator_code_digest: force_fake_checkout ? developer_collaborator_code_digest(developer_collaborator_code) : nil
            }.compact
          )

          checkout_session_payload = if use_fake_checkout
            create_fake_checkout_session!(payment, product)
          else
            begin
              create_stripe_checkout_session!(payment, product)
            rescue Stripe::StripeError => e
              return render_stripe_checkout_error(payment, e)
            end
          end

          AuditLog.record!(
            user: current_user,
            action: use_fake_checkout ? "billing.checkout_session.fake_created" : "billing.checkout_session.created",
            request: request,
            target: payment,
            metadata: {
              stripe_checkout_session_id: payment.stripe_checkout_session_id,
              product_code: product.code,
              product_kind: CoconiqueBilling.product_kind(product),
              checkout_mode: checkout_mode,
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

        def sync
          session_id = params.require(:session_id).to_s.strip
          app_key = params.fetch(:app_key, ENV.fetch("CURRENT_APP_KEY", "sample_app"))

          unless CoconiqueBilling.coconique_app_key?(app_key)
            return render_error(
              code: "UNSUPPORTED_BILLING_APP",
              message: "このアプリの決済同期には対応していません。",
              status: :unprocessable_entity
            )
          end

          CoconiqueBilling.ensure_products!

          payment = current_user.payment_checkout_sessions.find_by(
            stripe_checkout_session_id: session_id
          )

          if payment.blank?
            return render_error(
              code: "CHECKOUT_SESSION_NOT_FOUND",
              message: "Checkout Sessionが見つかりませんでした。ログイン中のアカウントで開始した決済か確認してください。",
              status: :not_found
            )
          end

          sync_status = "already_synced"

          if ActiveModel::Type::Boolean.new.cast(payment.metadata["fake_checkout"])
            sync_status = "fake_checkout"
          else
            if Stripe.api_key.blank?
              return render_error(
                code: "STRIPE_SECRET_KEY_MISSING",
                message: "Stripe Secret Keyが未設定のため、Checkout Sessionを確認できません。",
                status: :unprocessable_entity
              )
            end

            begin
              sync_status = sync_checkout_session_from_stripe!(payment)
            rescue Stripe::StripeError => e
              return render_stripe_checkout_error(payment, e)
            end
          end

          current_user.reload
          render_success(
            {
              checkout_session: checkout_session_json(payment.reload),
              credit_balance: credit_balance_json(app_key),
              sync_status: sync_status
            }
          )
        end

        def fake_complete
          payment = current_user.payment_checkout_sessions.find(params[:id])

          unless fake_checkout_completion_allowed?(payment)
            return render_error(
              code: "FAKE_CHECKOUT_DISABLED",
              message: "この環境では模擬決済完了処理は利用できません。",
              status: :forbidden
            )
          end

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
              checkout_mode: payment.checkout_mode,
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

        def sync_checkout_session_from_stripe!(payment)
          session = Stripe::Checkout::Session.retrieve(
            {
              id: payment.stripe_checkout_session_id,
              expand: ["invoice", "subscription", "payment_intent"]
            }
          )

          subscription_id = stripe_id(stripe_value(session, :subscription))
          invoice_id = stripe_id(stripe_value(session, :invoice))
          payment_intent_id = stripe_id(stripe_value(session, :payment_intent))

          payment.update!(
            status: stripe_value(session, :status).presence || payment.status,
            stripe_subscription_id: subscription_id.presence || payment.stripe_subscription_id,
            stripe_invoice_id: invoice_id.presence || payment.stripe_invoice_id,
            stripe_payment_intent_id: payment_intent_id.presence || payment.stripe_payment_intent_id,
            stripe_payment_status: stripe_value(session, :payment_status).presence || payment.stripe_payment_status,
            metadata: payment.metadata.merge(
              "stripe_checkout_session_synced_at" => Time.current.iso8601,
              "stripe_checkout_session_status" => stripe_value(session, :status),
              "stripe_payment_status" => stripe_value(session, :payment_status)
            ).compact
          )

          if payment.subscription_checkout?
            sync_subscription_checkout_from_stripe!(payment, session)
          else
            sync_payment_checkout_from_stripe!(payment, session)
          end
        end

        def sync_subscription_checkout_from_stripe!(payment, session)
          unless stripe_value(session, :status) == "complete"
            return "checkout_#{stripe_value(session, :status).presence || 'pending'}"
          end

          CoconiqueBilling.record_stripe_subscription_checkout_completed!(
            payment: payment,
            checkout_session: session
          )

          invoice = checkout_session_invoice(session)
          if stripe_invoice_paid?(invoice)
            CoconiqueBilling.apply_stripe_invoice_paid!(
              stripe_invoice: invoice,
              source: payment
            )
            return "invoice_paid_synced"
          end

          subscription = checkout_session_subscription(session)
          if subscription.present?
            CoconiqueBilling.sync_stripe_subscription_status!(
              stripe_subscription: subscription,
              source: payment
            )
            return "subscription_status_synced"
          end

          "checkout_completed_invoice_pending"
        end

        def sync_payment_checkout_from_stripe!(payment, session)
          return "checkout_#{stripe_value(session, :status).presence || 'pending'}" unless stripe_value(session, :status) == "complete"

          if stripe_value(session, :payment_status) == "paid"
            CoconiqueBilling.complete_checkout_session!(
              payment,
              stripe_payment_status: stripe_value(session, :payment_status),
              stripe_payment_intent: stripe_id(stripe_value(session, :payment_intent)),
              fake_checkout: false
            )
            return "payment_paid_synced"
          end

          "checkout_completed_payment_pending"
        end

        def checkout_session_invoice(session)
          invoice = stripe_value(session, :invoice)
          return nil if invoice.blank?
          return invoice unless invoice.is_a?(String)

          Stripe::Invoice.retrieve(invoice)
        end

        def checkout_session_subscription(session)
          subscription = stripe_value(session, :subscription)
          return nil if subscription.blank?
          return subscription unless subscription.is_a?(String)

          Stripe::Subscription.retrieve(subscription)
        end

        def stripe_invoice_paid?(invoice)
          return false if invoice.blank?

          stripe_value(invoice, :paid) == true ||
            stripe_value(invoice, :status).to_s == "paid" ||
            stripe_value(invoice, :amount_paid).to_i.positive?
        end

        def credit_balance_json(app_key)
          balance = CreditBalance.find_or_create_for!(
            user: current_user,
            app_key: app_key
          )

          {
            app_key: balance.app_key,
            balance: balance.balance,
            label: CoconiqueBilling.coconique_app_key?(app_key) ? "主催チケット" : "クレジット",
            monthly_grant: CoconiqueBilling.coconique_app_key?(app_key) ? CoconiqueBilling::MONTHLY_HOST_TICKET_GRANT : nil,
            subscription_status: current_user.coconique_subscription_status,
            subscription_plan: current_user.coconique_subscription_plan,
            current_period_started_at: current_user.coconique_subscription_current_period_started_at&.iso8601,
            current_period_ends_at: current_user.coconique_subscription_current_period_ends_at&.iso8601,
            additional_ticket_price_jpy: CoconiqueBilling.coconique_app_key?(app_key) ? CoconiqueBilling::ADDITIONAL_HOST_TICKET_JPY : nil,
            additional_ticket_expires_in_days: CoconiqueBilling.coconique_app_key?(app_key) ? CoconiqueBilling::ADDITIONAL_HOST_TICKET_EXPIRES_IN_DAYS : nil,
            additional_ticket_purchase_available: CoconiqueBilling.coconique_app_key?(app_key) ? current_user.coconique_additional_host_ticket_purchase_available? : nil,
            additional_ticket_purchase_limit_per_period: CoconiqueBilling.coconique_app_key?(app_key) ? CoconiqueBilling::MAX_ADDITIONAL_HOST_TICKET_PURCHASES_PER_PERIOD : nil,
            additional_ticket_purchases_this_period: CoconiqueBilling.coconique_app_key?(app_key) ? CoconiqueBilling.additional_host_ticket_purchases_count(current_user) : nil
          }
        end

        def stripe_id(value)
          return nil if value.blank?
          return value if value.is_a?(String)

          stripe_value(value, :id)
        end

        def stripe_value(object, key)
          return nil if object.blank?
          return object[key] if object.respond_to?(:key?) && object.key?(key)
          return object[key.to_s] if object.respond_to?(:key?) && object.key?(key.to_s)
          return object.public_send(key) if object.respond_to?(key)

          nil
        end

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
            product_code: product.code,
            product_kind: CoconiqueBilling.product_kind(product),
            checkout_mode: payment.checkout_mode
          }

          session_params = {
            customer: payment.stripe_customer.stripe_customer_id,
            mode: payment.checkout_mode,
            client_reference_id: payment.id.to_s,
            success_url: payment.success_url,
            cancel_url: payment.cancel_url,
            line_items: [line_item_for(product)],
            metadata: metadata,
            automatic_tax: { enabled: false }
          }

          if payment.checkout_mode == "subscription"
            session_params[:discounts] = [{ coupon: founder_intro_coupon_id }] if founder_intro_coupon_id.present? && current_user.coconique_founder_beta_joined_at.blank?
            session_params[:subscription_data] = {
              metadata: metadata.merge(
                stripe_price_id: stripe_price_id_for(product),
                intro_coupon_applied: session_params[:discounts].present?
              ).compact
            }
          else
            session_params[:payment_intent_data] = {
              metadata: metadata
            }
          end

          session = Stripe::Checkout::Session.create(session_params)

          payment.update!(
            stripe_checkout_session_id: session.id,
            status: session.status || "open",
            stripe_subscription_id: session.respond_to?(:subscription) ? session.subscription : nil,
            expires_at: Time.zone.at(session.expires_at),
            metadata: payment.metadata.merge(
              "stripe_checkout_session_id" => session.id,
              "stripe_subscription_id" => session.respond_to?(:subscription) ? session.subscription : nil
            ).compact
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

        def line_item_for(product)
          price_id = stripe_price_id_for(product)
          return { quantity: 1, price: price_id } if price_id.present?

          price_data = {
            currency: "jpy",
            unit_amount: product.amount_jpy,
            product_data: {
              name: product.name,
              description: product.description
            }
          }
          price_data[:recurring] = { interval: "month" } if CoconiqueBilling.founder_beta_product?(product)

          {
            quantity: 1,
            price_data: price_data
          }
        end

        def checkout_mode_for(product)
          CoconiqueBilling.coconique_app_key?(product.app_key) && CoconiqueBilling.founder_beta_product?(product) ? "subscription" : "payment"
        end

        def stripe_price_id_for(product)
          if CoconiqueBilling.coconique_app_key?(product.app_key) && CoconiqueBilling.founder_beta_product?(product)
            stripe_config_value("STRIPE_PRICE_FOUNDER_MONTHLY", "STRIPE_PRICE_COCONIQUE_FOUNDER_MONTHLY")
          elsif CoconiqueBilling.coconique_app_key?(product.app_key) && CoconiqueBilling.host_ticket_product?(product)
            stripe_config_value("STRIPE_PRICE_HOST_TICKET", "STRIPE_PRICE_COCONIQUE_HOST_TICKET")
          end
        end

        def founder_intro_coupon_id
          stripe_config_value("STRIPE_COUPON_FIRST_MONTH_100", "STRIPE_COUPON_COCONIQUE_FIRST_MONTH_100")
        end

        def stripe_config_value(*keys)
          keys.lazy.map { |key| ENV[key].to_s.strip.presence }.find(&:present?)
        end

        def render_stripe_checkout_error(payment, error)
          payment.update!(
            status: "failed",
            metadata: payment.metadata.merge(
              "stripe_checkout_error_class" => error.class.name,
              "stripe_checkout_error_message" => error.message,
              "stripe_checkout_failed_at" => Time.current.iso8601
            )
          )

          error_code = error.respond_to?(:code) ? error.code : nil
          error_message = stripe_error_message(error)

          render_error(
            code: "STRIPE_CHECKOUT_SESSION_CREATE_FAILED",
            message: error_message,
            status: :unprocessable_entity,
            data: {
              stripe_error_class: error.class.name,
              stripe_error_code: error_code,
              payment_checkout_session_id: payment.id,
              hint: stripe_error_hint(error)
            }.compact
          )
        end

        def stripe_error_message(error)
          if error.is_a?(Stripe::InvalidRequestError) && error.message.to_s.include?("No such price")
            "StripeのPrice IDが見つかりません。STRIPE_PRICE_FOUNDER_MONTHLYが、現在のSTRIPE_SECRET_KEYと同じTest/Liveモード・同じStripeアカウントで作成されたprice_...になっているか確認してください。"
          elsif error.is_a?(Stripe::InvalidRequestError) && error.message.to_s.include?("No such coupon")
            "StripeのCoupon IDが見つかりません。STRIPE_COUPON_FIRST_MONTH_100が、現在のSTRIPE_SECRET_KEYと同じTest/Liveモード・同じStripeアカウントで作成されたcoupon IDになっているか確認してください。"
          else
            "Stripe Checkout Sessionの作成に失敗しました。Stripe設定を確認してください。"
          end
        end

        def stripe_error_hint(error)
          if error.is_a?(Stripe::InvalidRequestError) && error.message.to_s.include?("No such price")
            "sk_test_...を使う場合はTest modeのprice_...、sk_live_...を使う場合はLive modeのprice_...を設定してください。Product ID(prod_...)やLookup keyではなくPrice ID(price_...)が必要です。"
          elsif error.is_a?(Stripe::InvalidRequestError) && error.message.to_s.include?("No such coupon")
            "Test modeとLive modeでCouponは別物です。今使っているSecret Keyと同じモードで作成したCoupon IDを設定してください。"
          end
        end

        def checkout_session_json(payment)
          {
            id: payment.id,
            stripe_checkout_session_id: payment.stripe_checkout_session_id,
            stripe_subscription_id: payment.stripe_subscription_id,
            url: nil,
            status: payment.status,
            checkout_mode: payment.checkout_mode,
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
            checkout_mode: payment.checkout_mode,
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

        def developer_collaborator_code_allowed?(code, product)
          return true if code.blank?
          return false unless CoconiqueBilling.coconique_app_key?(product.app_key) && CoconiqueBilling.founder_beta_product?(product)

          valid_developer_collaborator_code?(code)
        end

        def valid_developer_collaborator_code?(code)
          normalized = normalize_developer_collaborator_code(code)
          return false if normalized.blank?

          configured_codes = ENV.fetch(
            "COCONIQUE_DEVELOPER_COLLABORATOR_CODES",
            Rails.env.production? ? "" : "開発協力メンバー"
          )
          configured_codes.split(",").map { |item| normalize_developer_collaborator_code(item) }.include?(normalized)
        end

        def normalize_developer_collaborator_code(code)
          code.to_s.strip.upcase.gsub(/[\s\-]/, "")
        end

        def developer_collaborator_code_digest(code)
          OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, normalize_developer_collaborator_code(code))
        end

        def fake_checkout_completion_allowed?(payment)
          fake_checkout_enabled? ||
            ActiveModel::Type::Boolean.new.cast(ENV["COCONIQUE_ALLOW_FAKE_CHECKOUT_COMPLETE"]) ||
            ActiveModel::Type::Boolean.new.cast(payment.metadata["developer_collaborator_checkout"])
        end

        def fake_checkout_enabled?
          raw_flag = ENV["COCONIQUE_USE_FAKE_STRIPE_CHECKOUT"]
          return ActiveModel::Type::Boolean.new.cast(raw_flag) unless raw_flag.nil?

          Rails.env.test? || Stripe.api_key.blank?
        end
      end
    end
  end
end
