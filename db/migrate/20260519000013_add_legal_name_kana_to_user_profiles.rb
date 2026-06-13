class AddLegalNameKanaToUserProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :user_profiles, :legal_last_name_kana, :string
    add_column :user_profiles, :legal_first_name_kana, :string
    add_column :user_profiles, :legal_middle_name_kana, :string

    add_index :user_profiles, :legal_last_name_kana
    add_index :user_profiles, :legal_first_name_kana
  end
end
