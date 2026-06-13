class CreateCoconiqueUserAdminNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_user_admin_notes do |t|
      t.string :public_id, null: false
      t.references :user, null: false, foreign_key: true
      t.references :admin_user, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_user_admin_notes, :public_id, unique: true
    add_index :coconique_user_admin_notes, [:user_id, :created_at], name: "idx_coconique_user_admin_notes_user_created"
  end
end
