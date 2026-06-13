class CreateCoconiqueSafetyCheckSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_safety_check_sessions do |t|
      t.string :public_id, null: false
      t.references :coconique_event, null: false, foreign_key: true
      t.references :coconique_participation_request, foreign_key: true, index: { name: "index_coconique_safety_sessions_on_request_id" }
      t.references :user, null: false, foreign_key: true
      t.integer :role, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.integer :response_kind
      t.datetime :due_at, null: false
      t.datetime :next_reminder_at, null: false
      t.integer :reminders_sent_count, null: false, default: 0
      t.integer :extended_count, null: false, default: 0
      t.datetime :answered_at
      t.datetime :escalated_at
      t.text :help_note
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_safety_check_sessions, :public_id, unique: true
    add_index :coconique_safety_check_sessions, [:coconique_event_id, :user_id, :role], unique: true, name: "idx_coconique_safety_sessions_unique_user_role"
    add_index :coconique_safety_check_sessions, [:user_id, :status, :due_at], name: "idx_coconique_safety_sessions_user_status_due"
    add_index :coconique_safety_check_sessions, [:status, :next_reminder_at], name: "idx_coconique_safety_sessions_status_next"
  end
end
