class AddCoconiqueBillingPlanToUsersAndEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :coconique_subscription_plan, :string
    add_column :users, :coconique_subscription_status, :integer, null: false, default: 0
    add_column :users, :coconique_subscription_started_at, :datetime
    add_column :users, :coconique_subscription_current_period_started_at, :datetime
    add_column :users, :coconique_subscription_current_period_ends_at, :datetime
    add_column :users, :coconique_founder_beta_joined_at, :datetime
    add_column :users, :coconique_last_host_ticket_granted_on, :date

    add_column :coconique_events, :host_ticket_consumed_at, :datetime
    add_column :coconique_events, :host_ticket_transaction_id, :bigint

    add_index :users, :coconique_subscription_status
    add_index :users, :coconique_subscription_plan
    add_index :users, :coconique_last_host_ticket_granted_on
    add_index :coconique_events, :host_ticket_transaction_id
  end
end
