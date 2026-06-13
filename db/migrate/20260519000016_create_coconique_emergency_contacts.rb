class CreateCoconiqueEmergencyContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_emergency_contacts do |t|
      t.string :public_id, null: false
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.integer :status, null: false, default: 0
      t.string :approval_token_digest
      t.datetime :approval_token_expires_at
      t.datetime :last_invited_at
      t.datetime :approved_at
      t.datetime :rejected_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :coconique_emergency_contacts, :public_id, unique: true
    add_index :coconique_emergency_contacts, [:user_id, :email], unique: true
    add_index :coconique_emergency_contacts, :approval_token_digest, unique: true
    add_index :coconique_emergency_contacts, :status
  end
end
