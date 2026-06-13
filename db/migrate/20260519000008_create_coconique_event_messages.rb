class CreateCoconiqueEventMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_event_messages do |t|
      t.string :public_id, null: false
      t.references :coconique_event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :kind, null: false, default: 0
      t.text :body, null: false
      t.datetime :edited_at
      t.datetime :deleted_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_event_messages, :public_id, unique: true
    add_index :coconique_event_messages, [:coconique_event_id, :created_at, :id], name: "index_coconique_event_messages_on_event_and_created"
    add_index :coconique_event_messages, :deleted_at
  end
end
