module Api
  module V1
    module Billing
      class CreditProductsController < ApplicationController
        before_action :require_login!

        def index
          app_key = params.fetch(:app_key, ENV.fetch("CURRENT_APP_KEY", "sample_app"))
          CoconiqueBilling.ensure_products! if CoconiqueBilling.coconique_app_key?(app_key)

          products = CreditProduct
            .active
            .where(app_key: app_key)
            .ordered

          render_success(
            {
              credit_products: products.map { |product| credit_product_json(product) }
            }
          )
        end

        private

        def credit_product_json(product)
          {
            id: product.id,
            app_key: product.app_key,
            code: product.code,
            name: product.name,
            description: product.description,
            amount_jpy: product.amount_jpy,
            credits: product.credits,
            active: product.active,
            product_kind: CoconiqueBilling.product_kind(product),
            monthly_ticket_grant: CoconiqueBilling.founder_beta_product?(product) ? CoconiqueBilling::MONTHLY_HOST_TICKET_GRANT : nil,
            recurring_amount_jpy: CoconiqueBilling.founder_beta_product?(product) ? CoconiqueBilling::FOUNDER_BETA_MONTHLY_JPY : nil,
            expires_in_days: CoconiqueBilling.host_ticket_product?(product) ? CoconiqueBilling::ADDITIONAL_HOST_TICKET_EXPIRES_IN_DAYS : nil
          }
        end
      end
    end
  end
end
