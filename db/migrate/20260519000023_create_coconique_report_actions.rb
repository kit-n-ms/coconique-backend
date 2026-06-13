class CreateCoconiqueReportActions < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_report_actions do |t|
      t.string :public_id, null: false
      t.references :coconique_report, null: false, foreign_key: true, index: { name: "idx_coconique_report_actions_on_report" }
      t.references :admin_user, foreign_key: { to_table: :users }
      t.integer :action_type, null: false, default: 0
      t.string :previous_status
      t.string :next_status
      t.text :note
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_report_actions, :public_id, unique: true
    add_index :coconique_report_actions, [:coconique_report_id, :created_at], name: "idx_coconique_report_actions_report_created"
  end
end
