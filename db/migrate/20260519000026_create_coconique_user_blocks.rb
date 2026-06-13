class CreateCoconiqueUserBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_user_blocks do |t|
      t.string :public_id, null: false
      t.references :blocker, null: false, foreign_key: { to_table: :users }, index: false
      t.references :blocked, null: false, foreign_key: { to_table: :users }, index: false
      t.references :coconique_report, foreign_key: true
      t.string :reason
      t.text :note
      t.datetime :lifted_at
      t.references :lifted_by, foreign_key: { to_table: :users }
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :coconique_user_blocks, :public_id, unique: true
    add_index :coconique_user_blocks, [:blocker_id, :blocked_id], unique: true, where: "lifted_at IS NULL", name: "idx_coconique_active_blocks_pair"
    add_index :coconique_user_blocks, [:blocker_id, :lifted_at], name: "idx_coconique_blocks_on_blocker_active"
    add_index :coconique_user_blocks, [:blocked_id, :lifted_at], name: "idx_coconique_blocks_on_blocked_active"
    add_index :coconique_user_blocks, :created_at
  end
end
