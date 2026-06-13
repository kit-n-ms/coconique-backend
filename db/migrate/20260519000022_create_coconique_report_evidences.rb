class CreateCoconiqueReportEvidences < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_report_evidences do |t|
      t.string :public_id, null: false
      t.references :coconique_report, null: false, foreign_key: true, index: { name: "idx_coconique_report_evidences_on_report" }
      t.integer :evidence_type, null: false, default: 0
      t.text :body
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_report_evidences, :public_id, unique: true
    add_index :coconique_report_evidences, [:coconique_report_id, :evidence_type], name: "idx_coconique_evidences_report_type"
  end
end
