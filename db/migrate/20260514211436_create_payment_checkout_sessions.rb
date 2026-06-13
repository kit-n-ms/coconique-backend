class CreatePaymentCheckoutSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_checkout_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :credit_product, null: false, foreign_key: true
      t.references :stripe_customer, null: false, foreign_key: true

      t.string :stripe_checkout_session_id
      t.string :status, null: false, default: "created"

      t.integer :amount_total, null: false
      t.string :currency, null: false, default: "jpy"
      t.integer :credits, null: false

      t.text :success_url, null: false
      t.text :cancel_url, null: false
      t.jsonb :metadata, null: false, default: {}

      t.datetime :completed_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :payment_checkout_sessions, :stripe_checkout_session_id, unique: true
    add_index :payment_checkout_sessions, [:user_id, :status]
    add_index :payment_checkout_sessions, [:user_id, :created_at]
  end
end