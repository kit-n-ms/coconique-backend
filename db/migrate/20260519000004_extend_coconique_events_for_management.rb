class ExtendCoconiqueEventsForManagement < ActiveRecord::Migration[8.0]
  def change
    add_column :coconique_events, :recruitment_ends_at, :datetime
    add_column :coconique_events, :reference_url, :string
    add_column :coconique_events, :target_members, :jsonb, null: false, default: []
    add_column :coconique_events, :closed_at, :datetime
    add_column :coconique_events, :canceled_at, :datetime
    add_column :coconique_events, :finished_at, :datetime
    add_column :coconique_events, :cancellation_reason, :text

    add_index :coconique_events, :recruitment_ends_at
    add_index :coconique_events, :closed_at
    add_index :coconique_events, :canceled_at
    add_index :coconique_events, :finished_at
  end
end
