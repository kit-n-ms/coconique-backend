class CreateCoconiqueReports < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_reports do |t|
      t.string :public_id, null: false
      t.references :reporter, null: false, foreign_key: { to_table: :users }
      t.references :reported_user, foreign_key: { to_table: :users }
      t.references :coconique_event, foreign_key: true
      t.references :coconique_event_message, foreign_key: true, index: { name: "idx_coconique_reports_on_message" }
      t.references :coconique_safety_check_session, foreign_key: true, index: { name: "idx_coconique_reports_on_safety_session" }
      t.integer :target_type, null: false, default: 0
      t.string :target_public_id
      t.integer :reason, null: false, default: 0
      t.text :detail
      t.integer :status, null: false, default: 0
      t.integer :severity, null: false, default: 10
      t.integer :report_phase, null: false, default: 0
      t.string :event_status_at_report
      t.string :reporter_role
      t.jsonb :snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_reports, :public_id, unique: true
    add_index :coconique_reports, [:status, :severity, :created_at], name: "idx_coconique_reports_admin_list"
    add_index :coconique_reports, [:reporter_id, :created_at], name: "idx_coconique_reports_reporter_created"
    add_index :coconique_reports, [:reported_user_id, :created_at], name: "idx_coconique_reports_reported_user_created"
    add_index :coconique_reports, [:target_type, :target_public_id], name: "idx_coconique_reports_target"
  end
end
