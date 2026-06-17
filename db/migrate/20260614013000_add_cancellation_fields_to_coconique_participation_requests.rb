class AddCancellationFieldsToCoconiqueParticipationRequests < ActiveRecord::Migration[8.1]
  def change
    change_table :coconique_participation_requests, bulk: true do |t|
      t.datetime :canceled_at
      t.bigint :canceled_by_id
      t.string :cancellation_reason_category
      t.text :cancellation_message
      t.string :cancellation_timing
      t.integer :late_cancel_points, null: false, default: 0
      t.jsonb :cancellation_metadata, null: false, default: {}
    end

    add_index :coconique_participation_requests, :canceled_at
    add_index :coconique_participation_requests, :canceled_by_id
    add_index :coconique_participation_requests, :late_cancel_points
    add_foreign_key :coconique_participation_requests, :users, column: :canceled_by_id
  end
end
