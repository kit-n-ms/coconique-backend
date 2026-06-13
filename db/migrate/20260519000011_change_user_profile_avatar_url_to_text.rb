class ChangeUserProfileAvatarUrlToText < ActiveRecord::Migration[8.0]
  def change
    change_column :user_profiles, :avatar_url, :text
  end
end
