class CreateCoconiqueEventChatReads < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_event_chat_reads do |t|
      t.references :coconique_event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :last_read_message, foreign_key: { to_table: :coconique_event_messages }
      t.datetime :last_read_at

      t.timestamps
    end

    add_index :coconique_event_chat_reads,
      [:coconique_event_id, :user_id],
      unique: true,
      name: "idx_coconique_chat_reads_on_event_and_user"
    add_index :coconique_event_chat_reads, :last_read_at
  end
end
