class SplitUserProfileLegalNames < ActiveRecord::Migration[8.1]
  def up
    add_column :user_profiles, :legal_last_name, :string
    add_column :user_profiles, :legal_first_name, :string
    add_column :user_profiles, :legal_middle_name, :string
    add_column :user_profiles, :legal_full_name_raw, :string

    say_with_time "Backfill legal name fields from full_name for existing user_profiles" do
      UserProfile.reset_column_information
      UserProfile.find_each do |profile|
        next if profile.legal_last_name.present? || profile.legal_first_name.present?

        raw_name = profile.full_name.to_s.strip
        next if raw_name.blank?

        parts = raw_name.split(/\s+/, 3)
        profile.update_columns(
          legal_last_name: parts[0],
          legal_first_name: parts[1].presence || "未設定",
          legal_middle_name: parts[2],
          legal_full_name_raw: raw_name
        )
      end
    end

    add_index :user_profiles, :legal_last_name
    add_index :user_profiles, :legal_first_name
  end

  def down
    remove_index :user_profiles, :legal_first_name if index_exists?(:user_profiles, :legal_first_name)
    remove_index :user_profiles, :legal_last_name if index_exists?(:user_profiles, :legal_last_name)
    remove_column :user_profiles, :legal_full_name_raw
    remove_column :user_profiles, :legal_middle_name
    remove_column :user_profiles, :legal_first_name
    remove_column :user_profiles, :legal_last_name
  end
end
