class CreateUserProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :user_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.string :display_name, null: false
      t.string :full_name
      t.string :locale, null: false, default: "ja"
      t.string :timezone, null: false, default: "Asia/Tokyo"
      t.boolean :marketing_opt_in, null: false, default: false

      t.timestamps
    end

    add_index :user_profiles, :locale
  end
end