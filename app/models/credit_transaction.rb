class CreditTransaction < ApplicationRecord
  ZERO_AMOUNT_TRANSACTION_TYPES = %w[consume_reserved forfeit_reserved subscription_canceled admin_note].freeze

  belongs_to :user
  belongs_to :credit_balance

  validates :app_key, presence: true
  validates :transaction_type, presence: true
  validates :amount, numericality: true
  validates :balance_after, numericality: { greater_than_or_equal_to: 0 }
  validate :amount_must_not_be_zero_unless_lifecycle_record

  private

  def amount_must_not_be_zero_unless_lifecycle_record
    return unless amount.to_i.zero?
    return if ZERO_AMOUNT_TRANSACTION_TYPES.include?(transaction_type.to_s)

    errors.add(:amount, "must not be zero")
  end
end
