class AddCoconiqueProfileFieldsToUserProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :user_profiles, :identity_birth_date, :date
    add_column :user_profiles, :public_age_label, :string
    add_column :user_profiles, :profile_headline, :string
    add_column :user_profiles, :bio, :text
    add_column :user_profiles, :interest_category_keys, :jsonb, null: false, default: []
    add_column :user_profiles, :participation_style_keys, :jsonb, null: false, default: []
    add_column :user_profiles, :preferred_areas, :jsonb, null: false, default: []
    add_column :user_profiles, :conversation_topics, :jsonb, null: false, default: []
    add_column :user_profiles, :communication_preferences, :jsonb, null: false, default: []
    add_column :user_profiles, :avatar_url, :string
    add_column :user_profiles, :club_love_levels, :jsonb, null: false, default: {}

    add_index :user_profiles, :public_age_label
  end
end
