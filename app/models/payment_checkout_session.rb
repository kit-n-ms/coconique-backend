class PaymentCheckoutSession < ApplicationRecord
  belongs_to :user
  belongs_to :credit_product
  belongs_to :stripe_customer

  validates :status, presence: true
  validates :amount_total, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :credits, numericality: { greater_than: 0 }

  def completed?
    status == "completed"
  end
end