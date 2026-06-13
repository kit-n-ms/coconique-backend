class AddEventImagesAndStatusLogsToCoconiqueEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :coconique_events, :image_urls, :jsonb, null: false, default: []

    create_table :coconique_event_status_logs do |t|
      t.references :coconique_event, null: false, foreign_key: true, index: true
      t.references :user, foreign_key: true, index: true
      t.string :action, null: false
      t.string :from_status
      t.string :to_status, null: false
      t.text :reason

      t.timestamps
    end

    add_index :coconique_event_status_logs,
      [:coconique_event_id, :created_at],
      name: "index_coconique_event_status_logs_on_event_and_created_at"
  end
end
