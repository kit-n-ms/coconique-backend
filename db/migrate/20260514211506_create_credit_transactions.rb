class CreateCreditTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :credit_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :credit_balance, null: false, foreign_key: true

      t.string :app_key, null: false
      t.string :transaction_type, null: false
      t.integer :amount, null: false
      t.integer :balance_after, null: false

      t.string :source_type
      t.string :source_id
      t.string :description
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :credit_transactions, [:user_id, :app_key, :created_at]
    add_index :credit_transactions, [:source_type, :source_id]
    add_index :credit_transactions, :transaction_type
  end
end