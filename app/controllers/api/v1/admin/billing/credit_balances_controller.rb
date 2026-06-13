module Api
  module V1
    module Admin
      module Billing
        class CreditBalancesController < Api::V1::Admin::BaseController
          def index
            scope = CreditBalance.includes(:user).order(updated_at: :desc)

            scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
            scope = scope.where(app_key: params[:app_key]) if params[:app_key].present?

            balances, pagination = paginated(scope)

            render_success(
              {
                credit_balances: balances.map { |balance| credit_balance_json(balance) },
                pagination: pagination
              }
            )
          end

          private

          def credit_balance_json(balance)
            {
              id: balance.id,
              user_id: balance.user_id,
              user_email: balance.user&.email,
              app_key: balance.app_key,
              balance: balance.balance,
              created_at: balance.created_at,
              updated_at: balance.updated_at
            }
          end
        end
      end
    end
  end
end
