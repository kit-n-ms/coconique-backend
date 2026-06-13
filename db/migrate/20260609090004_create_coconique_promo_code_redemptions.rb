class CreateCoconiquePromoCodeRedemptions < ActiveRecord::Migration[8.0]
  def change
    create_table :coconique_promo_code_redemptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :code_digest, null: false
      t.string :code_label
      t.integer :status, null: false, default: 0
      t.datetime :redeemed_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_promo_code_redemptions, :public_id, unique: true
    add_index :coconique_promo_code_redemptions, [:user_id, :code_digest], unique: true, name: "idx_coconique_promo_redemptions_user_code"
    add_index :coconique_promo_code_redemptions, :code_digest
  end
end
