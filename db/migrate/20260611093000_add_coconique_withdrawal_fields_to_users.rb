class AddCoconiqueWithdrawalFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :withdrawn_at, :datetime unless column_exists?(:users, :withdrawn_at)
    add_column :users, :withdrawal_reason, :string unless column_exists?(:users, :withdrawal_reason)
    add_column :users, :withdrawal_note, :text unless column_exists?(:users, :withdrawal_note)
    add_column :users, :coconique_subscription_canceled_at, :datetime unless column_exists?(:users, :coconique_subscription_canceled_at)

    add_index :users, :withdrawn_at unless index_exists?(:users, :withdrawn_at)
    add_index :users, :coconique_subscription_canceled_at unless index_exists?(:users, :coconique_subscription_canceled_at)
  end
end
