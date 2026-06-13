class CreateCoconiqueParticipationRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :coconique_participation_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :coconique_event, null: false, foreign_key: true
      t.references :reviewed_by, foreign_key: { to_table: :users }, index: true

      t.integer :status, null: false, default: 10
      t.text :message, null: false, default: ""
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :coconique_participation_requests,
      [:user_id, :coconique_event_id],
      unique: true,
      name: "index_coconique_requests_on_user_and_event"
    add_index :coconique_participation_requests, :status
    add_index :coconique_participation_requests, [:coconique_event_id, :status],
      name: "index_coconique_requests_on_event_and_status"
  end
end
