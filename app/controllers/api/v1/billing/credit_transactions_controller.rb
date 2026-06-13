module Api
  module V1
    module Billing
      class CreditTransactionsController < ApplicationController
        before_action :require_login!

        def index
          app_key = params.fetch(:app_key, ENV.fetch("CURRENT_APP_KEY", "sample_app"))

          transactions = current_user
            .credit_transactions
            .where(app_key: app_key)
            .order(created_at: :desc)
            .limit(50)

          render_success(
            {
              credit_transactions: transactions.map { |transaction| transaction_json(transaction) }
            }
          )
        end

        private

        def transaction_json(transaction)
          {
            id: transaction.id,
            app_key: transaction.app_key,
            transaction_type: transaction.transaction_type,
            amount: transaction.amount,
            balance_after: transaction.balance_after,
            description: transaction.description,
            created_at: transaction.created_at
          }
        end
      end
    end
  end
end
