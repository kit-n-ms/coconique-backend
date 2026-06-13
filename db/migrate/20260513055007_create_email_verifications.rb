class CreateEmailVerifications < ActiveRecord::Migration[8.0]
  def change
    create_table :email_verifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end

    add_index :email_verifications, :token_digest, unique: true
    add_index :email_verifications, [:user_id, :used_at]
    add_index :email_verifications, :expires_at
  end
end