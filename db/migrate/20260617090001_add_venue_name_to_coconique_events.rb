class AddVenueNameToCoconiqueEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :coconique_events, :venue_name, :string
  end
end
