class AddStripeSubscriptionFieldsToCoconiqueBilling < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :coconique_stripe_subscription_id, :string unless column_exists?(:users, :coconique_stripe_subscription_id)
    add_column :users, :coconique_stripe_price_id, :string unless column_exists?(:users, :coconique_stripe_price_id)
    add_column :users, :coconique_subscription_latest_invoice_id, :string unless column_exists?(:users, :coconique_subscription_latest_invoice_id)
    add_column :users, :coconique_subscription_cancel_at_period_end, :boolean, null: false, default: false unless column_exists?(:users, :coconique_subscription_cancel_at_period_end)
    add_column :users, :coconique_subscription_cancel_at, :datetime unless column_exists?(:users, :coconique_subscription_cancel_at)
    add_column :users, :coconique_subscription_last_payment_at, :datetime unless column_exists?(:users, :coconique_subscription_last_payment_at)
    add_column :users, :coconique_subscription_past_due_at, :datetime unless column_exists?(:users, :coconique_subscription_past_due_at)

    add_column :payment_checkout_sessions, :checkout_mode, :string, null: false, default: "payment" unless column_exists?(:payment_checkout_sessions, :checkout_mode)
    add_column :payment_checkout_sessions, :stripe_subscription_id, :string unless column_exists?(:payment_checkout_sessions, :stripe_subscription_id)
    add_column :payment_checkout_sessions, :stripe_invoice_id, :string unless column_exists?(:payment_checkout_sessions, :stripe_invoice_id)
    add_column :payment_checkout_sessions, :stripe_payment_intent_id, :string unless column_exists?(:payment_checkout_sessions, :stripe_payment_intent_id)
    add_column :payment_checkout_sessions, :stripe_payment_status, :string unless column_exists?(:payment_checkout_sessions, :stripe_payment_status)

    add_index :users, :coconique_stripe_subscription_id, unique: true, where: "coconique_stripe_subscription_id IS NOT NULL", if_not_exists: true
    add_index :users, :coconique_subscription_latest_invoice_id, if_not_exists: true
    add_index :payment_checkout_sessions, :checkout_mode, if_not_exists: true
    add_index :payment_checkout_sessions, :stripe_subscription_id, if_not_exists: true
    add_index :payment_checkout_sessions, :stripe_invoice_id, if_not_exists: true
  end
end
