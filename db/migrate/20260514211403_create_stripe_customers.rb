class CreateStripeCustomers < ActiveRecord::Migration[8.0]
  def change
    create_table :stripe_customers do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :stripe_customer_id, null: false
      t.boolean :livemode, null: false, default: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :stripe_customers, :stripe_customer_id, unique: true
  end
end