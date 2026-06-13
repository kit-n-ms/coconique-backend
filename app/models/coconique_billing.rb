class CoconiqueBilling
  APP_KEY = "coconique".freeze
  FOUNDER_BETA_PRODUCT_CODE = "founder_beta_monthly".freeze
  HOST_TICKET_1_PRODUCT_CODE = "host_ticket_1".freeze
  MONTHLY_HOST_TICKET_GRANT = 5
  FOUNDER_BETA_FIRST_MONTH_JPY = 100
  FOUNDER_BETA_MONTHLY_JPY = 430
  ADDITIONAL_HOST_TICKET_JPY = 1000
  ADDITIONAL_HOST_TICKET_EXPIRES_IN_DAYS = 180
  MAX_ADDITIONAL_HOST_TICKET_PURCHASES_PER_PERIOD = 5

  class InsufficientHostTickets < StandardError; end
  class AdditionalHostTicketPurchaseUnavailable < StandardError; end

  class << self
    def ensure_products!
      ensure_founder_beta_product!
      ensure_host_ticket_product!
    end

    def ensure_founder_beta_product!
      product = CreditProduct.find_or_initialize_by(app_key: APP_KEY, code: FOUNDER_BETA_PRODUCT_CODE)
      product.assign_attributes(
        name: "Founder βプラン 初月100円",
        description: "2ヶ月目以降は月額430円。毎月、募集公開に使える主催チケット5枚が付与されます。参加申請は月額内で利用できます。",
        amount_jpy: FOUNDER_BETA_FIRST_MONTH_JPY,
        credits: MONTHLY_HOST_TICKET_GRANT,
        active: true,
        display_order: 1
      )
      product.save!
      product
    end

    def ensure_host_ticket_product!
      product = CreditProduct.find_or_initialize_by(app_key: APP_KEY, code: HOST_TICKET_1_PRODUCT_CODE)
      product.assign_attributes(
        name: "追加主催チケット 1枚",
        description: "月5枚の主催チケットを使い切った場合に購入できます。有効期限は購入日から180日です。",
        amount_jpy: ADDITIONAL_HOST_TICKET_JPY,
        credits: 1,
        active: true,
        display_order: 20
      )
      product.save!
      product
    end

    def coconique_app_key?(app_key)
      app_key.to_s == APP_KEY
    end

    def founder_beta_product?(product_or_code)
      code = product_or_code.respond_to?(:code) ? product_or_code.code : product_or_code
      code.to_s == FOUNDER_BETA_PRODUCT_CODE
    end

    def host_ticket_product?(product_or_code)
      code = product_or_code.respond_to?(:code) ? product_or_code.code : product_or_code
      code.to_s == HOST_TICKET_1_PRODUCT_CODE
    end

    def product_kind(product)
      return "founder_beta_subscription" if founder_beta_product?(product)
      return "host_ticket" if host_ticket_product?(product)

      "credit"
    end

    def host_ticket_balance_for(user)
      CreditBalance.find_or_create_for!(user: user, app_key: APP_KEY)
    end

    def sync_host_tickets_for_user!(user:, now: Time.current)
      return unless user&.persisted?

      user.with_lock do
        user.reload
        expire_due_host_ticket_lots!(user: user, now: now)
        sync_subscription_period!(user: user, now: now) if user.coconique_billing_active?
      end
    end

    def sync_subscription_period!(user:, now: Time.current)
      return unless user.coconique_billing_active?

      if user.coconique_subscription_current_period_started_at.blank? || user.coconique_subscription_current_period_ends_at.blank?
        start_at = user.coconique_subscription_started_at || now
        user.update_columns(
          coconique_subscription_current_period_started_at: start_at,
          coconique_subscription_current_period_ends_at: start_at + 1.month,
          updated_at: now
        )
        user.reload
      end

      while user.coconique_subscription_current_period_ends_at.present? && user.coconique_subscription_current_period_ends_at <= now
        next_period_start = user.coconique_subscription_current_period_ends_at
        next_period_end = next_period_start + 1.month
        user.update_columns(
          coconique_subscription_current_period_started_at: next_period_start,
          coconique_subscription_current_period_ends_at: next_period_end,
          updated_at: now
        )
        user.reload
      end

      grant_monthly_host_tickets!(
        user: user,
        source: user,
        granted_on: user.coconique_subscription_current_period_started_at.to_date,
        period_started_at: user.coconique_subscription_current_period_started_at,
        period_ends_at: user.coconique_subscription_current_period_ends_at,
        metadata: {
          subscription_plan: user.coconique_subscription_plan,
          subscription_status: user.coconique_subscription_status,
          auto_sync: true
        }
      )
    end

    def grant_monthly_host_tickets!(user:, source:, granted_on: Date.current, force: false, period_started_at: nil, period_ends_at: nil, metadata: {})
      now = Time.current
      period_started_at ||= user.coconique_subscription_current_period_started_at || granted_on.in_time_zone.beginning_of_day
      period_ends_at ||= user.coconique_subscription_current_period_ends_at || period_started_at + 1.month
      grant_date = period_started_at.to_date

      user.with_lock do
        expire_due_host_ticket_lots!(user: user, now: period_started_at)

        already_granted = user.coconique_host_ticket_lots
          .where(grant_type: monthly_grant_type_for(user))
          .where(period_started_at: period_started_at)
          .exists?
        legacy_granted = user.coconique_last_host_ticket_granted_on == grant_date

        return host_ticket_balance_for(user) if (already_granted || legacy_granted) && !force

        balance = host_ticket_balance_for(user)
        lot = user.coconique_host_ticket_lots.create!(
          grant_type: monthly_grant_type_for(user),
          total_count: MONTHLY_HOST_TICKET_GRANT,
          available_count: MONTHLY_HOST_TICKET_GRANT,
          granted_at: now,
          expires_at: period_ends_at,
          period_started_at: period_started_at,
          period_ends_at: period_ends_at,
          source: source,
          metadata: {
            app_key: APP_KEY,
            granted_on: grant_date.iso8601,
            monthly_grant: true,
            monthly_host_ticket_grant: MONTHLY_HOST_TICKET_GRANT,
            expires_at: period_ends_at&.iso8601
          }.merge(metadata || {})
        )

        balance.add_credit!(
          amount: MONTHLY_HOST_TICKET_GRANT,
          transaction_type: "monthly_grant",
          source: source,
          description: "月次主催チケット付与",
          metadata: {
            app_key: APP_KEY,
            lot_id: lot.public_id,
            granted_on: grant_date.iso8601,
            expires_at: period_ends_at&.iso8601,
            monthly_grant: true,
            monthly_host_ticket_grant: MONTHLY_HOST_TICKET_GRANT
          }.merge(metadata || {})
        )

        user.update_columns(
          coconique_last_host_ticket_granted_on: grant_date,
          updated_at: now
        )

        balance.reload
      end
    end

    def activate_founder_beta_subscription!(user:, source:, metadata: {})
      now = Time.current
      period_started_at = now
      period_ends_at = 1.month.from_now

      user.update!(
        card_registered_at: user.card_registered_at || now,
        coconique_subscription_plan: "founder_beta",
        coconique_subscription_status: :active,
        coconique_subscription_started_at: user.coconique_subscription_started_at || now,
        coconique_subscription_current_period_started_at: period_started_at,
        coconique_subscription_current_period_ends_at: period_ends_at,
        coconique_founder_beta_joined_at: user.coconique_founder_beta_joined_at || now
      )

      grant_monthly_host_tickets!(
        user: user,
        source: source,
        granted_on: period_started_at.to_date,
        period_started_at: period_started_at,
        period_ends_at: period_ends_at,
        metadata: {
          subscription_plan: "founder_beta",
          subscription_status: "active"
        }.merge(metadata || {})
      )

      user.refresh_coconique_safety_registered_at! if user.respond_to?(:refresh_coconique_safety_registered_at!)
      user
    end

    def activate_collaborator_free_plan!(user:, source:, metadata: {})
      now = Time.current
      period_started_at = now
      period_ends_at = 1.month.from_now

      user.update!(
        billing_exempted_at: user.billing_exempted_at || now,
        coconique_subscription_plan: "collaborator_beta_free",
        coconique_subscription_status: :active,
        coconique_subscription_started_at: user.coconique_subscription_started_at || now,
        coconique_subscription_current_period_started_at: period_started_at,
        coconique_subscription_current_period_ends_at: period_ends_at,
        coconique_founder_beta_joined_at: user.coconique_founder_beta_joined_at || now
      )

      grant_monthly_host_tickets!(
        user: user,
        source: source,
        granted_on: period_started_at.to_date,
        period_started_at: period_started_at,
        period_ends_at: period_ends_at,
        metadata: {
          subscription_plan: "collaborator_beta_free",
          collaborator_beta: true
        }.merge(metadata || {})
      )

      user.refresh_coconique_safety_registered_at! if user.respond_to?(:refresh_coconique_safety_registered_at!)
      user
    end

    def complete_checkout_session!(payment, stripe_payment_status:, stripe_payment_intent:, fake_checkout: false)
      return if payment.completed?

      PaymentCheckoutSession.transaction do
        payment.lock!
        return if payment.completed?

        product = payment.credit_product
        app_key = payment.metadata.fetch("app_key")

        if coconique_app_key?(app_key) && host_ticket_product?(product)
          ensure_additional_host_ticket_purchase_allowed!(payment.user)
        end

        payment.update!(
          status: "completed",
          completed_at: Time.current,
          metadata: payment.metadata.merge(
            "stripe_payment_status" => stripe_payment_status,
            "stripe_payment_intent" => stripe_payment_intent,
            "fake_checkout" => fake_checkout
          )
        )

        payment.user.mark_card_registered! if payment.user.respond_to?(:mark_card_registered!)

        if coconique_app_key?(app_key) && founder_beta_product?(product)
          activate_founder_beta_subscription!(
            user: payment.user,
            source: payment,
            metadata: {
              stripe_checkout_session_id: payment.stripe_checkout_session_id,
              amount_total: payment.amount_total,
              currency: payment.currency,
              fake_checkout: fake_checkout
            }
          )
        elsif coconique_app_key?(app_key) && host_ticket_product?(product)
          grant_purchased_host_ticket!(
            user: payment.user,
            payment: payment,
            quantity: payment.credits,
            metadata: {
              stripe_checkout_session_id: payment.stripe_checkout_session_id,
              amount_total: payment.amount_total,
              currency: payment.currency,
              fake_checkout: fake_checkout,
              product_code: product.code,
              product_kind: product_kind(product)
            }
          )
        else
          balance = CreditBalance.find_or_create_for!(user: payment.user, app_key: app_key)
          balance.add_credit!(
            amount: payment.credits,
            transaction_type: "purchase",
            source: payment,
            description: "デポジット購入",
            metadata: {
              stripe_checkout_session_id: payment.stripe_checkout_session_id,
              amount_total: payment.amount_total,
              currency: payment.currency,
              fake_checkout: fake_checkout,
              product_code: product.code,
              product_kind: product_kind(product)
            }
          )
        end
      end
    end

    def grant_purchased_host_ticket!(user:, payment:, quantity:, metadata: {})
      now = Time.current
      expires_at = ADDITIONAL_HOST_TICKET_EXPIRES_IN_DAYS.days.from_now

      lot = user.coconique_host_ticket_lots.create!(
        grant_type: :purchase_grant,
        total_count: quantity,
        available_count: quantity,
        granted_at: now,
        expires_at: expires_at,
        source: payment,
        metadata: {
          app_key: APP_KEY,
          purchased: true,
          expires_at: expires_at.iso8601,
          purchase_valid_days: ADDITIONAL_HOST_TICKET_EXPIRES_IN_DAYS
        }.merge(metadata || {})
      )

      balance = host_ticket_balance_for(user)
      balance.add_credit!(
        amount: quantity,
        transaction_type: "purchase_grant",
        source: payment,
        description: "追加主催チケット購入",
        metadata: {
          lot_id: lot.public_id,
          expires_at: expires_at.iso8601,
          purchase_valid_days: ADDITIONAL_HOST_TICKET_EXPIRES_IN_DAYS
        }.merge(metadata || {})
      )
    end

    def additional_host_ticket_purchase_available?(user)
      sync_host_tickets_for_user!(user: user) if user.persisted?
      return false unless user.coconique_billing_active?
      return false if host_ticket_balance_for(user).balance.positive?

      additional_host_ticket_purchases_count(user) < MAX_ADDITIONAL_HOST_TICKET_PURCHASES_PER_PERIOD
    end

    def ensure_additional_host_ticket_purchase_allowed!(user)
      return true if additional_host_ticket_purchase_available?(user)

      raise AdditionalHostTicketPurchaseUnavailable, "追加主催チケットは、利用可能な主催チケットが0枚になった場合のみ購入できます。"
    end

    def additional_host_ticket_purchases_count(user)
      period_start, period_end = current_purchase_limit_period_for(user)
      user.credit_transactions
        .where(app_key: APP_KEY, transaction_type: "purchase_grant")
        .where("created_at >= ? AND created_at < ?", period_start, period_end)
        .sum(:amount)
        .to_i
    end

    def current_purchase_limit_period_for(user)
      start_at = user.coconique_subscription_current_period_started_at || Time.current.beginning_of_month
      end_at = user.coconique_subscription_current_period_ends_at || start_at + 1.month
      [start_at, end_at]
    end

    def reserve_host_ticket_for_event!(event:, user:)
      return nil if event.host_ticket_consumed? || event.host_ticket_reserved?

      sync_host_tickets_for_user!(user: user)

      CreditBalance.transaction do
        event.lock!
        return nil if event.host_ticket_consumed? || event.host_ticket_reserved?

        lot = next_available_host_ticket_lot_for(user)
        raise InsufficientHostTickets if lot.blank?

        lot.lock!
        raise InsufficientHostTickets unless lot.available?

        lot.update!(
          available_count: lot.available_count - 1,
          reserved_count: lot.reserved_count + 1
        )

        transaction = host_ticket_balance_for(user).consume_credit!(
          amount: 1,
          transaction_type: "reserve_for_event",
          source: event,
          description: "募集公開による主催チケット仮押さえ",
          metadata: {
            lot_id: lot.public_id,
            event_public_id: event.public_id,
            event_title: event.title,
            host_ticket_reserved: true,
            visible_as_spent: true,
            grant_type: lot.grant_type,
            expires_at: lot.expires_at&.iso8601
          }
        )

        event.update_columns(
          host_ticket_reservation_status: CoconiqueEvent.host_ticket_reservation_statuses[:reserved],
          host_ticket_reserved_at: Time.current,
          host_ticket_lot_id: lot.id,
          host_ticket_transaction_id: transaction.id,
          updated_at: Time.current
        )

        transaction
      end
    rescue CreditBalance::InsufficientBalance
      raise InsufficientHostTickets
    end

    def consume_reserved_host_ticket_for_event!(event:)
      return nil if event.blank? || event.host_ticket_consumed?
      return nil unless event.host_ticket_reserved?

      CreditBalance.transaction do
        event.lock!
        return nil if event.host_ticket_consumed?
        return nil unless event.host_ticket_reserved?

        lot = event.host_ticket_lot
        lot&.lock!
        if lot.present? && lot.reserved_count.positive?
          lot.update!(
            reserved_count: lot.reserved_count - 1,
            consumed_count: lot.consumed_count + 1
          )
        end

        balance = host_ticket_balance_for(event.host)
        transaction = balance.record_lifecycle!(
          source: event,
          transaction_type: "consume_reserved",
          description: "成立・終了による主催チケット消費確定",
          metadata: {
            lot_id: lot&.public_id,
            event_public_id: event.public_id,
            event_title: event.title,
            host_ticket_consumed: true
          }
        )

        event.update_columns(
          host_ticket_reservation_status: CoconiqueEvent.host_ticket_reservation_statuses[:consumed],
          host_ticket_consumed_at: Time.current,
          updated_at: Time.current
        )

        transaction
      end
    end

    def release_reserved_host_ticket_for_event!(event:, reason: nil, admin: nil)
      return nil if event.blank?
      return nil if event.host_ticket_released? || event.host_ticket_consumed?
      return nil unless event.host_ticket_reserved? || event.host_ticket_forfeited?

      CreditBalance.transaction do
        event.lock!
        return nil if event.host_ticket_released? || event.host_ticket_consumed?
        return nil unless event.host_ticket_reserved? || event.host_ticket_forfeited?

        lot = event.host_ticket_lot
        lot&.lock!
        if lot.present?
          if event.host_ticket_reserved? && lot.reserved_count.positive?
            lot.update!(
              reserved_count: lot.reserved_count - 1,
              available_count: lot.available_count + 1
            )
          elsif event.host_ticket_forfeited? && lot.forfeited_count.positive?
            lot.update!(
              forfeited_count: lot.forfeited_count - 1,
              available_count: lot.available_count + 1
            )
          end
        end

        transaction = host_ticket_balance_for(event.host).add_credit!(
          amount: 1,
          transaction_type: "release_reserved",
          source: event,
          description: "主催チケット返還",
          metadata: {
            lot_id: lot&.public_id,
            event_public_id: event.public_id,
            event_title: event.title,
            reason: reason,
            admin_user_id: admin&.id
          }.compact
        )

        event.update_columns(
          host_ticket_reservation_status: CoconiqueEvent.host_ticket_reservation_statuses[:released],
          host_ticket_released_at: Time.current,
          host_ticket_release_reason: reason,
          updated_at: Time.current
        )

        transaction
      end
    end

    def forfeit_reserved_host_ticket_for_event!(event:, reason: nil, admin: nil)
      return nil if event.blank?
      return nil if event.host_ticket_forfeited? || event.host_ticket_consumed? || event.host_ticket_released?
      return nil unless event.host_ticket_reserved?

      CreditBalance.transaction do
        event.lock!
        return nil if event.host_ticket_forfeited? || event.host_ticket_consumed? || event.host_ticket_released?
        return nil unless event.host_ticket_reserved?

        lot = event.host_ticket_lot
        lot&.lock!
        if lot.present? && lot.reserved_count.positive?
          lot.update!(
            reserved_count: lot.reserved_count - 1,
            forfeited_count: lot.forfeited_count + 1
          )
        end

        transaction = host_ticket_balance_for(event.host).record_lifecycle!(
          source: event,
          transaction_type: "forfeit_reserved",
          description: "主催チケット没収確定",
          metadata: {
            lot_id: lot&.public_id,
            event_public_id: event.public_id,
            event_title: event.title,
            reason: reason,
            admin_user_id: admin&.id
          }.compact
        )

        event.update_columns(
          host_ticket_reservation_status: CoconiqueEvent.host_ticket_reservation_statuses[:forfeited],
          host_ticket_forfeited_at: Time.current,
          host_ticket_release_reason: reason,
          updated_at: Time.current
        )

        transaction
      end
    end

    def expire_due_host_ticket_lots!(user:, now: Time.current)
      balance = host_ticket_balance_for(user)
      user.coconique_host_ticket_lots.due_to_expire(now).find_each do |lot|
        CoconiqueHostTicketLot.transaction do
          lot.lock!
          amount = lot.available_count.to_i
          next if amount <= 0

          lot.update!(
            available_count: 0,
            expired_count: lot.expired_count + amount
          )

          balance.consume_credit!(
            amount: amount,
            transaction_type: "expire",
            source: lot,
            description: lot.grant_purchase_grant? ? "追加主催チケット期限切れ" : "月次主催チケット期限切れ",
            metadata: {
              lot_id: lot.public_id,
              grant_type: lot.grant_type,
              expires_at: lot.expires_at&.iso8601
            }
          )
        end
      end
    end

    def next_available_host_ticket_lot_for(user)
      lots = user.coconique_host_ticket_lots.available(Time.current).to_a
      lots.sort_by do |lot|
        [host_ticket_lot_priority(lot), lot.expires_at || 100.years.from_now, lot.created_at]
      end.first
    end

    def host_ticket_lot_priority(lot)
      return 0 if lot.grant_monthly_grant? || lot.grant_collaborator_grant?
      return 1 if lot.grant_purchase_grant?
      return 2 if lot.grant_admin_grant?

      99
    end

    def cancel_coconique_subscription!(user:, reason: nil, source: nil)
      now = Time.current
      user.update_columns(
        coconique_subscription_status: User.coconique_subscription_statuses[:canceled],
        coconique_subscription_canceled_at: now,
        billing_exempted_at: nil,
        safety_registered_at: nil,
        updated_at: now
      )

      balance = host_ticket_balance_for(user)
      balance.record_lifecycle!(
        source: source || user,
        transaction_type: "subscription_canceled",
        description: "Coconique月額プラン停止",
        metadata: { reason: reason }.compact
      )
    end

    def forfeit_all_host_tickets_for_user!(user:, reason:, source: nil, admin: nil)
      now = Time.current
      balance = host_ticket_balance_for(user)

      user.coconique_host_ticket_lots.where("available_count > 0 OR reserved_count > 0").find_each do |lot|
        CoconiqueHostTicketLot.transaction do
          lot.lock!
          available = lot.available_count.to_i
          reserved = lot.reserved_count.to_i
          next if available <= 0 && reserved <= 0

          consume_amount = [available, balance.reload.balance].min
          if consume_amount.positive?
            balance.consume_credit!(
              amount: consume_amount,
              transaction_type: "forfeit",
              source: source || lot,
              description: "主催チケット失効・没収",
              metadata: {
                lot_id: lot.public_id,
                grant_type: lot.grant_type,
                reason: reason,
                admin_user_id: admin&.id,
                withdrawn_or_banned: true
              }.compact
            )
          end

          if reserved.positive?
            balance.record_lifecycle!(
              source: source || lot,
              transaction_type: "forfeit_reserved",
              description: "仮押さえ中主催チケット失効・没収",
              metadata: {
                lot_id: lot.public_id,
                grant_type: lot.grant_type,
                reserved_count: reserved,
                reason: reason,
                admin_user_id: admin&.id,
                withdrawn_or_banned: true
              }.compact
            )
          end

          lot.update!(
            available_count: 0,
            reserved_count: 0,
            forfeited_count: lot.forfeited_count.to_i + available + reserved
          )
        end
      end

      balance.reload
    end

    def monthly_grant_type_for(user)
      user.coconique_collaborator_beta? ? :collaborator_grant : :monthly_grant
    end
  end
end
