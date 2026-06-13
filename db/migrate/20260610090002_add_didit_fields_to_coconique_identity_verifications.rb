class AddDiditFieldsToCoconiqueIdentityVerifications < ActiveRecord::Migration[8.0]
  def change
    add_column :coconique_identity_verification_sessions, :workflow_type, :string unless column_exists?(:coconique_identity_verification_sessions, :workflow_type)
    add_column :coconique_identity_verification_sessions, :document_type, :string unless column_exists?(:coconique_identity_verification_sessions, :document_type)
    add_column :coconique_identity_verification_sessions, :provider_status, :string unless column_exists?(:coconique_identity_verification_sessions, :provider_status)
    add_column :coconique_identity_verification_sessions, :deleted_at, :datetime unless column_exists?(:coconique_identity_verification_sessions, :deleted_at)

    add_column :users, :identity_workflow_type, :string unless column_exists?(:users, :identity_workflow_type)
    add_column :users, :identity_document_type, :string unless column_exists?(:users, :identity_document_type)
    add_column :users, :identity_external_session_deleted_at, :datetime unless column_exists?(:users, :identity_external_session_deleted_at)

    add_index :coconique_identity_verification_sessions, [:provider, :provider_session_id], name: "idx_coconique_identity_sessions_on_provider_session", if_not_exists: true
    add_index :coconique_identity_verification_sessions, :workflow_type, name: "idx_coconique_identity_sessions_on_workflow_type", if_not_exists: true
    add_index :users, :identity_provider, if_not_exists: true
    add_index :users, :identity_document_type, if_not_exists: true
  end
end
