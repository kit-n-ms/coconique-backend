class AddRegionToCoconiqueEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :coconique_events, :area_prefecture, :string
    add_column :coconique_events, :area_city, :string

    add_index :coconique_events, :area_prefecture
    add_index :coconique_events, [:area_prefecture, :area_city]
  end
end
