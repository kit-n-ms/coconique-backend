class CreateCoconiqueEventFavorites < ActiveRecord::Migration[8.0]
  def change
    create_table :coconique_event_favorites do |t|
      t.references :user, null: false, foreign_key: true
      t.references :coconique_event, null: false, foreign_key: true

      t.timestamps
    end

    add_index :coconique_event_favorites,
      [:user_id, :coconique_event_id],
      unique: true,
      name: "index_coconique_favorites_on_user_and_event"
  end
end
