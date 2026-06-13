class AddLostItemImagesToCoconiqueEventMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :coconique_event_messages, :image_urls, :jsonb, null: false, default: []
    add_index :coconique_event_messages, :kind
  end
end
