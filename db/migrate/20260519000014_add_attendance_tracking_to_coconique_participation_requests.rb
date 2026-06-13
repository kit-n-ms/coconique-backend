class AddAttendanceTrackingToCoconiqueParticipationRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :coconique_participation_requests, :attendance_status, :integer, null: false, default: 0
    add_reference :coconique_participation_requests,
      :attendance_recorded_by,
      foreign_key: { to_table: :users },
      index: { name: "index_coconique_requests_on_attendance_recorded_by" }
    add_column :coconique_participation_requests, :attendance_recorded_at, :datetime
    add_column :coconique_participation_requests, :attendance_note, :text

    add_index :coconique_participation_requests,
      [:coconique_event_id, :attendance_status],
      name: "index_coconique_requests_on_event_attendance_status"
  end
end
