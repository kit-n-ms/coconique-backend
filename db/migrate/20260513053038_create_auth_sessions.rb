class CreateAuthSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :auth_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :session_token_digest, null: false
      t.datetime :expires_at, null: false
      t.string :ip_address
      t.text :user_agent
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :auth_sessions, :session_token_digest, unique: true
    add_index :auth_sessions, :expires_at
    add_index :auth_sessions, [:user_id, :revoked_at]
  end
end