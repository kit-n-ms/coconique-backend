class CreateCreditProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :credit_products do |t|
      t.string :app_key, null: false
      t.string :code, null: false
      t.string :name, null: false
      t.text :description
      t.integer :amount_jpy, null: false
      t.integer :credits, null: false
      t.boolean :active, null: false, default: true
      t.integer :display_order, null: false, default: 0

      t.timestamps
    end

    add_index :credit_products, [:app_key, :code], unique: true
    add_index :credit_products, [:app_key, :active, :display_order]
  end
end