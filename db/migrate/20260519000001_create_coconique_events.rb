class CreateCoconiqueEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :coconique_events do |t|
      t.string :public_id, null: false
      t.references :host, foreign_key: { to_table: :users }, index: true

      t.string :title, null: false
      t.string :category_key, null: false
      t.string :area, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :meeting_place, null: false
      t.string :image_url

      t.integer :capacity, null: false, default: 4
      t.integer :min_participants, null: false, default: 2
      t.integer :current_participants, null: false, default: 0
      t.integer :interested_count, null: false, default: 0

      t.string :cost_label, null: false, default: "各自負担"
      t.string :dress_code, null: false, default: "ドレスコードなし"
      t.string :host_display_name, null: false, default: "ココさん"
      t.string :host_age_group, null: false, default: "30代"
      t.text :host_message, null: false, default: ""
      t.text :summary, null: false, default: ""

      t.boolean :is_public_gambling_watching, null: false, default: false
      t.boolean :requires_age20_verified, null: false, default: false
      t.integer :status, null: false, default: 20
      t.datetime :published_at

      t.timestamps
    end

    add_index :coconique_events, :public_id, unique: true
    add_index :coconique_events, :category_key
    add_index :coconique_events, :starts_at
    add_index :coconique_events, :status
    add_index :coconique_events, [:status, :starts_at]
  end
end
