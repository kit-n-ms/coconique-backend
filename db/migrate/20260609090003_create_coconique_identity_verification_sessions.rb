class CreateCoconiqueIdentityVerificationSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :coconique_identity_verification_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :provider, null: false, default: "stripe_identity"
      t.string :provider_session_id
      t.integer :status, null: false, default: 0
      t.string :url
      t.string :return_url
      t.datetime :expires_at
      t.datetime :verified_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_identity_verification_sessions, :public_id, unique: true
    add_index :coconique_identity_verification_sessions, :provider_session_id
    add_index :coconique_identity_verification_sessions, [:user_id, :status]
  end
end
