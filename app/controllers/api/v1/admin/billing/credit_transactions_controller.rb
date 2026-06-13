module Api
  module V1
    module Admin
      module Billing
        class CreditTransactionsController < Api::V1::Admin::BaseController
          def index
            scope = CreditTransaction.includes(:user, :credit_balance).order(created_at: :desc)

            scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
            scope = scope.where(app_key: params[:app_key]) if params[:app_key].present?
            scope = scope.where(transaction_type: params[:transaction_type]) if params[:transaction_type].present?
            scope = scope.where(source_type: params[:source_type]) if params[:source_type].present?

            transactions, pagination = paginated(scope)

            render_success(
              {
                credit_transactions: transactions.map { |transaction| credit_transaction_json(transaction) },
                pagination: pagination
              }
            )
          end

          private

          def credit_transaction_json(transaction)
            {
              id: transaction.id,
              user_id: transaction.user_id,
              user_email: transaction.user&.email,
              credit_balance_id: transaction.credit_balance_id,
              app_key: transaction.app_key,
              transaction_type: transaction.transaction_type,
              amount: transaction.amount,
              balance_after: transaction.balance_after,
              source_type: transaction.source_type,
              source_id: transaction.source_id,
              description: transaction.description,
              metadata: transaction.metadata,
              created_at: transaction.created_at,
              updated_at: transaction.updated_at
            }
          end
        end
      end
    end
  end
end
