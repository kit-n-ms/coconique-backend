class CreateCoconiquePhoneVerificationAttempts < ActiveRecord::Migration[8.0]
  def change
    create_table :coconique_phone_verification_attempts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :phone_number_digest, null: false
      t.string :code_digest, null: false
      t.string :sent_to_masked, null: false
      t.string :provider, null: false, default: "fake_sms"
      t.integer :status, null: false, default: 0
      t.integer :attempts_count, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :confirmed_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_phone_verification_attempts, :public_id, unique: true
    add_index :coconique_phone_verification_attempts, [:user_id, :status]
    add_index :coconique_phone_verification_attempts, :phone_number_digest
  end
end
