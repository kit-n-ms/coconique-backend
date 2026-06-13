class CreateCreditBalances < ActiveRecord::Migration[8.0]
  def change
    create_table :credit_balances do |t|
      t.references :user, null: false, foreign_key: true
      t.string :app_key, null: false
      t.integer :balance, null: false, default: 0

      t.timestamps
    end

    add_index :credit_balances, [:user_id, :app_key], unique: true
  end
end