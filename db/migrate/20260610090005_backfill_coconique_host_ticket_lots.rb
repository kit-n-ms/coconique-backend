class BackfillCoconiqueHostTicketLots < ActiveRecord::Migration[8.1]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationCreditBalance < ActiveRecord::Base
    self.table_name = "credit_balances"
  end

  class MigrationHostTicketLot < ActiveRecord::Base
    self.table_name = "coconique_host_ticket_lots"
  end

  def up
    return unless table_exists?(:coconique_host_ticket_lots)

    MigrationCreditBalance.where(app_key: "coconique").where("balance > 0").find_each do |balance|
      next if MigrationHostTicketLot.where(user_id: balance.user_id).exists?

      user = MigrationUser.find_by(id: balance.user_id)
      now = Time.current
      MigrationHostTicketLot.create!(
        user_id: balance.user_id,
        public_id: "htl-#{SecureRandom.hex(8)}",
        grant_type: 20,
        total_count: balance.balance,
        available_count: balance.balance,
        reserved_count: 0,
        consumed_count: 0,
        expired_count: 0,
        forfeited_count: 0,
        granted_at: now,
        expires_at: user&.coconique_subscription_current_period_ends_at,
        period_started_at: user&.coconique_subscription_current_period_started_at,
        period_ends_at: user&.coconique_subscription_current_period_ends_at,
        metadata: {
          backfilled: true,
          source: "legacy_credit_balance",
          original_balance: balance.balance
        },
        created_at: now,
        updated_at: now
      )
    end
  end

  def down
    MigrationHostTicketLot.where("metadata ->> 'source' = ?", "legacy_credit_balance").delete_all if table_exists?(:coconique_host_ticket_lots)
  end
end
