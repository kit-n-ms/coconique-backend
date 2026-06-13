class AddCsrfTokenDigestToAuthSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :auth_sessions, :csrf_token_digest, :string
    add_index :auth_sessions, :csrf_token_digest
  end
end