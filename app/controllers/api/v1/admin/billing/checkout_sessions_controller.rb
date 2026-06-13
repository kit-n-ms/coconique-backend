module Api
  module V1
    module Admin
      module Billing
        class CheckoutSessionsController < Api::V1::Admin::BaseController
          def index
            scope = PaymentCheckoutSession
              .includes(:user, :credit_product, :stripe_customer)
              .order(created_at: :desc)

            scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.where(stripe_checkout_session_id: params[:stripe_checkout_session_id]) if params[:stripe_checkout_session_id].present?
            scope = scope.joins(:credit_product).where(credit_products: { app_key: params[:app_key] }) if params[:app_key].present?

            sessions, pagination = paginated(scope)

            render_success(
              {
                checkout_sessions: sessions.map { |session| checkout_session_json(session) },
                pagination: pagination
              }
            )
          end

          def show
            session = PaymentCheckoutSession
              .includes(:user, :credit_product, :stripe_customer)
              .find(params[:id])

            render_success(
              {
                checkout_session: checkout_session_json(session, include_urls: true)
              }
            )
          end

          private

          def checkout_session_json(session, include_urls: false)
            data = {
              id: session.id,
              user_id: session.user_id,
              user_email: session.user&.email,
              credit_product_id: session.credit_product_id,
              credit_product_code: session.credit_product&.code,
              app_key: session.credit_product&.app_key,
              stripe_customer_id: session.stripe_customer_id,
              stripe_customer_ref: session.stripe_customer&.stripe_customer_id,
              stripe_checkout_session_id: session.stripe_checkout_session_id,
              status: session.status,
              amount_total: session.amount_total,
              currency: session.currency,
              credits: session.credits,
              metadata: session.metadata,
              completed_at: session.completed_at,
              expires_at: session.expires_at,
              created_at: session.created_at,
              updated_at: session.updated_at
            }

            if include_urls
              data[:success_url] = session.success_url
              data[:cancel_url] = session.cancel_url
            end

            data
          end
        end
      end
    end
  end
end
