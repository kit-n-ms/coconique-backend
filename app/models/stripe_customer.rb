class StripeCustomer < ApplicationRecord
  belongs_to :user

  validates :stripe_customer_id, presence: true, uniqueness: true

  def self.ensure_for!(user:)
    return user.stripe_customer if user.stripe_customer.present?

    raise "STRIPE_SECRET_KEY is missing" if Stripe.api_key.blank?

    customer = Stripe::Customer.create(
      email: user.email,
      metadata: {
        user_id: user.id
      }
    )

    create!(
      user: user,
      stripe_customer_id: customer.id,
      livemode: customer.livemode || false
    )
  end
end