class CreditBalance < ApplicationRecord
  class InsufficientBalance < StandardError; end

  belongs_to :user
  has_many :credit_transactions, dependent: :destroy

  validates :app_key, presence: true
  validates :balance, numericality: { greater_than_or_equal_to: 0 }

  def self.find_or_create_for!(user:, app_key:)
    find_or_create_by!(user: user, app_key: app_key) do |balance|
      balance.balance = 0
    end
  end

  def add_credit!(amount:, source:, description:, metadata: {}, transaction_type: "purchase")
    raise ArgumentError, "amount must be positive" unless amount.positive?

    transaction do
      lock!

      next_balance = balance + amount

      update!(balance: next_balance)

      create_transaction_record!(
        amount: amount,
        balance_after: next_balance,
        transaction_type: transaction_type,
        source: source,
        description: description,
        metadata: metadata
      )
    end
  end

  def consume_credit!(amount:, source:, description:, metadata: {}, transaction_type: "usage")
    raise ArgumentError, "amount must be positive" unless amount.positive?

    transaction do
      lock!

      next_balance = balance - amount
      raise InsufficientBalance, "not enough balance" if next_balance.negative?

      update!(balance: next_balance)

      create_transaction_record!(
        amount: -amount,
        balance_after: next_balance,
        transaction_type: transaction_type,
        source: source,
        description: description,
        metadata: metadata
      )
    end
  end

  def record_lifecycle!(source:, transaction_type:, description:, metadata: {})
    transaction do
      lock!

      create_transaction_record!(
        amount: 0,
        balance_after: balance,
        transaction_type: transaction_type,
        source: source,
        description: description,
        metadata: metadata
      )
    end
  end

  private

  def create_transaction_record!(amount:, balance_after:, transaction_type:, source:, description:, metadata: {})
    credit_transactions.create!(
      user: user,
      app_key: app_key,
      transaction_type: transaction_type,
      amount: amount,
      balance_after: balance_after,
      source_type: source&.class&.name,
      source_id: source&.id&.to_s,
      description: description,
      metadata: metadata || {}
    )
  end
end
