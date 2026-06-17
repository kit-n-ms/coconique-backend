class CreateCoconiqueReentrySignals < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_reentry_signals do |t|
      t.references :user, null: false, foreign_key: true
      t.string :signal_kind, null: false
      t.string :signal_digest, null: false
      t.string :provider
      t.string :source_type
      t.bigint :source_id
      t.integer :status, null: false, default: 0
      t.datetime :detected_at, null: false
      t.datetime :matched_blocklist_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_reentry_signals, [:user_id, :signal_kind, :signal_digest], unique: true, name: "idx_coconique_reentry_signals_user_kind_digest"
    add_index :coconique_reentry_signals, [:signal_kind, :signal_digest], name: "idx_coconique_reentry_signals_kind_digest"
    add_index :coconique_reentry_signals, :status

    create_table :coconique_reentry_blocklist_entries do |t|
      t.references :source_user, foreign_key: { to_table: :users }
      t.string :signal_kind, null: false
      t.string :signal_digest, null: false
      t.string :provider
      t.string :reason, null: false
      t.datetime :blocked_at, null: false
      t.datetime :lifted_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_reentry_blocklist_entries, [:signal_kind, :signal_digest], name: "idx_coconique_reentry_blocklist_kind_digest"
    add_index :coconique_reentry_blocklist_entries, [:signal_kind, :signal_digest], unique: true, where: "lifted_at IS NULL", name: "idx_coconique_reentry_blocklist_active_unique"
    add_index :coconique_reentry_blocklist_entries, :blocked_at
    add_index :coconique_reentry_blocklist_entries, :lifted_at
  end
end
