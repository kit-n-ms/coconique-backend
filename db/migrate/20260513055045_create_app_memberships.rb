class CreateAppMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :app_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.string :app_key, null: false
      t.integer :status, null: false, default: 0
      t.datetime :started_at, null: false

      t.timestamps
    end

    add_index :app_memberships, [:user_id, :app_key], unique: true
    add_index :app_memberships, [:app_key, :status]
  end
end