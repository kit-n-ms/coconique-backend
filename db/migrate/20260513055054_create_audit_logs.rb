class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs do |t|
      t.references :user, null: true, foreign_key: true
      t.string :action, null: false
      t.string :target_type
      t.string :target_id
      t.jsonb :metadata, null: false, default: {}
      t.string :ip_address
      t.text :user_agent

      t.timestamps
    end

    add_index :audit_logs, :action
    add_index :audit_logs, [:user_id, :created_at]
    add_index :audit_logs, [:target_type, :target_id]
    add_index :audit_logs, :metadata, using: :gin
  end
end