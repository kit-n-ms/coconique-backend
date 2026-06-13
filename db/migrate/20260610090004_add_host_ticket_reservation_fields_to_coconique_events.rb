class AddHostTicketReservationFieldsToCoconiqueEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :coconique_events, :host_ticket_reservation_status, :integer, null: false, default: 0
    add_column :coconique_events, :host_ticket_reserved_at, :datetime
    add_column :coconique_events, :host_ticket_released_at, :datetime
    add_column :coconique_events, :host_ticket_forfeited_at, :datetime
    add_column :coconique_events, :host_ticket_release_reason, :string
    add_reference :coconique_events, :host_ticket_lot, foreign_key: { to_table: :coconique_host_ticket_lots }

    add_index :coconique_events, :host_ticket_reservation_status
    add_index :coconique_events, :host_ticket_reserved_at
    add_index :coconique_events, :host_ticket_released_at
  end
end
