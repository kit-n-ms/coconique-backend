class CreateCoconiqueNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_notifications do |t|
      t.string :public_id, null: false
      t.references :user, null: false, foreign_key: true
      t.string :notification_key, null: false
      t.string :kind, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.string :link_path, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :read_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :coconique_notifications, :public_id, unique: true
    add_index :coconique_notifications, [:user_id, :notification_key], unique: true, name: "idx_coconique_notifications_user_key"
    add_index :coconique_notifications, [:user_id, :read_at]
    add_index :coconique_notifications, [:user_id, :deleted_at]
    add_index :coconique_notifications, [:user_id, :occurred_at]
  end
end
