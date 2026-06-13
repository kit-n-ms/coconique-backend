class AllowReapplicationAfterWithdrawal < ActiveRecord::Migration[8.0]
  ACTIVE_REQUEST_STATUSES = [0, 10, 20, 30].freeze

  def up
    if index_exists?(:coconique_participation_requests, [:user_id, :coconique_event_id], name: "index_coconique_requests_on_user_and_event")
      remove_index :coconique_participation_requests, name: "index_coconique_requests_on_user_and_event"
    end

    add_index :coconique_participation_requests,
      [:user_id, :coconique_event_id],
      unique: true,
      where: "status IN (#{ACTIVE_REQUEST_STATUSES.join(',')})",
      name: "index_coconique_requests_on_user_event_current",
      if_not_exists: true
  end

  def down
    if index_exists?(:coconique_participation_requests, [:user_id, :coconique_event_id], name: "index_coconique_requests_on_user_event_current")
      remove_index :coconique_participation_requests, name: "index_coconique_requests_on_user_event_current"
    end

    add_index :coconique_participation_requests,
      [:user_id, :coconique_event_id],
      unique: true,
      name: "index_coconique_requests_on_user_and_event",
      if_not_exists: true
  end
end
