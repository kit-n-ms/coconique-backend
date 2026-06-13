module Api
  module V1
    module Billing
      class BalancesController < ApplicationController
        before_action :require_login!

        def show
          app_key = params.fetch(:app_key, ENV.fetch("CURRENT_APP_KEY", "sample_app"))
          if CoconiqueBilling.coconique_app_key?(app_key)
            CoconiqueBilling.ensure_products!
            current_user.sync_coconique_host_tickets! if current_user.coconique_billing_active?
          end

          balance = CreditBalance.find_or_create_for!(
            user: current_user,
            app_key: app_key
          )

          render_success(
            {
              credit_balance: {
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
            }
          )
        end
      end
    end
  end
end
