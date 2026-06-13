class AddHomeRegionToUserProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :user_profiles, :home_prefecture, :string
    add_column :user_profiles, :home_city, :string

    add_index :user_profiles, :home_prefecture
    add_index :user_profiles, [:home_prefecture, :home_city]
  end
end
