class AddIdentityGenderAndEventVisibilityFilters < ActiveRecord::Migration[8.1]
  def change
    add_column :user_profiles, :identity_gender, :string
    add_index :user_profiles, :identity_gender

    add_column :coconique_events, :same_gender_only, :boolean, null: false, default: false
    add_column :coconique_events, :same_generation_only, :boolean, null: false, default: false
    add_index :coconique_events, :same_gender_only
    add_index :coconique_events, :same_generation_only
  end
end
