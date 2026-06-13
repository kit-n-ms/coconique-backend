class CreateCoconiqueHostTicketLots < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_host_ticket_lots do |t|
      t.references :user, null: false, foreign_key: true
      t.string :public_id, null: false
      t.integer :grant_type, null: false, default: 0
      t.integer :total_count, null: false, default: 0
      t.integer :available_count, null: false, default: 0
      t.integer :reserved_count, null: false, default: 0
      t.integer :consumed_count, null: false, default: 0
      t.integer :expired_count, null: false, default: 0
      t.integer :forfeited_count, null: false, default: 0
      t.string :source_type
      t.string :source_id
      t.datetime :granted_at, null: false
      t.datetime :expires_at
      t.datetime :period_started_at
      t.datetime :period_ends_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_host_ticket_lots, :public_id, unique: true
    add_index :coconique_host_ticket_lots, [:user_id, :grant_type]
    add_index :coconique_host_ticket_lots, [:user_id, :expires_at]
    add_index :coconique_host_ticket_lots, [:source_type, :source_id]
  end
end
