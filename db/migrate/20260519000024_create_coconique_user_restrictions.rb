class CreateCoconiqueUserRestrictions < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_user_restrictions do |t|
      t.string :public_id, null: false
      t.references :user, null: false, foreign_key: true
      t.references :coconique_report, foreign_key: true, index: { name: "idx_coconique_user_restrictions_on_report" }
      t.references :created_by_admin, foreign_key: { to_table: :users }
      t.references :lifted_by_admin, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0
      t.string :reason, null: false
      t.text :note
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.datetime :lifted_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_user_restrictions, :public_id, unique: true
    add_index :coconique_user_restrictions, [:user_id, :status, :lifted_at], name: "idx_coconique_user_restrictions_user_status"
    add_index :coconique_user_restrictions, [:status, :starts_at], name: "idx_coconique_user_restrictions_status_started"
  end
end
