class AddCoconiqueSafetyRegistrationToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :beta_member_type, :integer, null: false, default: 0
    add_column :users, :phone_verification_status, :integer, null: false, default: 0
    add_column :users, :phone_number_digest, :string
    add_column :users, :phone_verified_at, :datetime
    add_column :users, :identity_verification_status, :integer, null: false, default: 0
    add_column :users, :identity_provider, :string
    add_column :users, :identity_verification_id, :string
    add_column :users, :identity_verified_at, :datetime
    add_column :users, :age_verified, :boolean, null: false, default: false
    add_column :users, :age_over_18, :boolean, null: false, default: false
    add_column :users, :operator_verification_status, :integer, null: false, default: 0
    add_column :users, :operator_verified_at, :datetime
    add_column :users, :promo_code_digest, :string
    add_column :users, :promo_code_verified_at, :datetime
    add_column :users, :card_registered_at, :datetime
    add_column :users, :billing_exempted_at, :datetime
    add_column :users, :safety_registered_at, :datetime

    add_index :users, :beta_member_type
    add_index :users, :phone_verification_status
    add_index :users, :phone_number_digest
    add_index :users, :identity_verification_status
    add_index :users, :operator_verification_status
    add_index :users, :promo_code_digest
  end
end
