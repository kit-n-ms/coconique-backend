class CreateCoconiqueEventMessageReactions < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_event_message_reactions do |t|
      t.string :public_id, null: false
      t.references :coconique_event_message, null: false, foreign_key: true, index: { name: "idx_coconique_msg_reactions_on_message_id" }
      t.references :user, null: false, foreign_key: true
      t.string :emoji_key, null: false

      t.timestamps
    end

    add_index :coconique_event_message_reactions, :public_id, unique: true
    add_index :coconique_event_message_reactions, [:coconique_event_message_id, :user_id, :emoji_key], unique: true, name: "idx_coconique_msg_reactions_unique_user_emoji"
    add_index :coconique_event_message_reactions, :emoji_key
  end
end
