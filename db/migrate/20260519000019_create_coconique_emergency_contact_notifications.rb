class CreateCoconiqueEmergencyContactNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_emergency_contact_notifications do |t|
      t.string :public_id, null: false
      t.references :coconique_safety_check_session, null: false, foreign_key: true, index: { name: "idx_coconique_contact_notifications_on_session" }
      t.references :coconique_emergency_contact, null: false, foreign_key: true, index: { name: "idx_coconique_contact_notifications_on_contact" }
      t.integer :kind, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.datetime :sent_at
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_emergency_contact_notifications, :public_id, unique: true
    add_index :coconique_emergency_contact_notifications, [:coconique_safety_check_session_id, :kind], name: "idx_coconique_contact_notifications_session_kind"
  end
end
