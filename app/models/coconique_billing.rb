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
      # Stripe Subscriptionユーザーは `invoice.paid` webhookをチケット付与の正とする。
      # ここで自動付与すると、checkout.session.completed / subscription.updated だけで
      # チケットが付く可能性があるため、Stripe連動時は同期のみスキップする。
      return if user.respond_to?(:coconique_stripe_subscription_id) && user.coconique_stripe_subscription_id.present?

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


    def record_stripe_subscription_checkout_completed!(payment:, checkout_session:)
      return if payment.completed?

      now = Time.current
      subscription_id = stripe_id(stripe_value(checkout_session, :subscription))
      customer_id = stripe_id(stripe_value(checkout_session, :customer))
      payment_status = stripe_value(checkout_session, :payment_status)
      invoice_id = stripe_id(stripe_value(checkout_session, :invoice))

      PaymentCheckoutSession.transaction do
        payment.lock!
        return if payment.completed?

        payment.update!(
          status: "completed",
          completed_at: now,
          stripe_subscription_id: subscription_id,
          stripe_invoice_id: invoice_id,
          stripe_payment_status: payment_status,
          metadata: payment.metadata.merge(
            "stripe_checkout_session_completed_at" => now.iso8601,
            "stripe_customer_id" => customer_id,
            "stripe_subscription_id" => subscription_id,
            "stripe_invoice_id" => invoice_id,
            "stripe_payment_status" => payment_status,
            "activation_source" => "checkout.session.completed",
            "tickets_granted_by" => "invoice.paid"
          ).compact
        )

        payment.user.update!(
          card_registered_at: payment.user.card_registered_at || now,
          coconique_subscription_plan: "founder_beta",
          coconique_subscription_status: stripe_subscription_status_for("incomplete"),
          coconique_subscription_started_at: payment.user.coconique_subscription_started_at,
          coconique_founder_beta_joined_at: payment.user.coconique_founder_beta_joined_at,
          coconique_stripe_subscription_id: subscription_id.presence || payment.user.coconique_stripe_subscription_id,
          coconique_stripe_price_id: payment.metadata["stripe_price_id"].presence || payment.user.coconique_stripe_price_id,
          coconique_subscription_latest_invoice_id: invoice_id.presence || payment.user.coconique_subscription_latest_invoice_id,
          coconique_subscription_past_due_at: nil
        )
        payment.user.refresh_coconique_safety_registered_at! if payment.user.respond_to?(:refresh_coconique_safety_registered_at!)
      end
    end

    def apply_stripe_invoice_paid!(stripe_invoice:, source: nil)
      user = find_user_for_stripe_invoice(stripe_invoice)
      return nil if user.blank?

      invoice_id = stripe_value(stripe_invoice, :id)
      return user if invoice_id.present? && user.coconique_subscription_latest_invoice_id == invoice_id && monthly_grant_for_invoice_exists?(user, invoice_id)

      now = Time.current
      subscription_id = stripe_subscription_id_from_invoice(stripe_invoice)
      customer_id = stripe_id(stripe_value(stripe_invoice, :customer))
      price_id = stripe_invoice_price_id(stripe_invoice)
      period_started_at, period_ends_at = stripe_invoice_period(stripe_invoice)
      period_started_at ||= now
      period_ends_at ||= period_started_at + 1.month
      amount_paid = stripe_value(stripe_invoice, :amount_paid).to_i
      currency = stripe_value(stripe_invoice, :currency).presence || "jpy"
      billing_reason = stripe_value(stripe_invoice, :billing_reason)

      User.transaction do
        user.lock!
        return user if invoice_id.present? && user.coconique_subscription_latest_invoice_id == invoice_id && monthly_grant_for_invoice_exists?(user, invoice_id)

        user.update!(
          card_registered_at: user.card_registered_at || now,
          coconique_subscription_plan: "founder_beta",
          coconique_subscription_status: stripe_subscription_status_for("active"),
          coconique_subscription_started_at: user.coconique_subscription_started_at || period_started_at,
          coconique_subscription_current_period_started_at: period_started_at,
          coconique_subscription_current_period_ends_at: period_ends_at,
          coconique_founder_beta_joined_at: user.coconique_founder_beta_joined_at || now,
          coconique_stripe_subscription_id: subscription_id.presence || user.coconique_stripe_subscription_id,
          coconique_stripe_price_id: price_id.presence || user.coconique_stripe_price_id,
          coconique_subscription_latest_invoice_id: invoice_id.presence || user.coconique_subscription_latest_invoice_id,
          coconique_subscription_last_payment_at: now,
          coconique_subscription_past_due_at: nil,
          coconique_subscription_cancel_at_period_end: false
        )
      end

      payment = find_payment_for_stripe_invoice(stripe_invoice, user: user)
      payment&.update!(
        status: "completed",
        completed_at: payment.completed_at || now,
        stripe_subscription_id: subscription_id.presence || payment.stripe_subscription_id,
        stripe_invoice_id: invoice_id.presence || payment.stripe_invoice_id,
        stripe_payment_intent_id: stripe_id(stripe_value(stripe_invoice, :payment_intent)).presence || payment.stripe_payment_intent_id,
        stripe_payment_status: "paid",
        metadata: payment.metadata.merge(
          "stripe_invoice_id" => invoice_id,
          "stripe_subscription_id" => subscription_id,
          "stripe_invoice_paid_at" => now.iso8601
        ).compact
      )

      grant_monthly_host_tickets!(
        user: user.reload,
        source: source || payment || user,
        period_started_at: period_started_at,
        period_ends_at: period_ends_at,
        metadata: {
          subscription_plan: "founder_beta",
          subscription_status: "active",
          billing_provider: "stripe",
          stripe_invoice_id: invoice_id,
          stripe_subscription_id: subscription_id,
          stripe_customer_id: customer_id,
          stripe_price_id: price_id,
          amount_paid: amount_paid,
          currency: currency,
          billing_reason: billing_reason
        }.compact
      )

      capture_stripe_card_fingerprint_signal!(
        user: user.reload,
        stripe_invoice: stripe_invoice,
        source: source || payment || user
      )

      user.reload.refresh_coconique_safety_registered_at! if user.respond_to?(:refresh_coconique_safety_registered_at!)
      user
    end

    def mark_stripe_invoice_payment_failed!(stripe_invoice:, source: nil)
      user = find_user_for_stripe_invoice(stripe_invoice)
      return nil if user.blank?

      invoice_id = stripe_value(stripe_invoice, :id)
      subscription_id = stripe_subscription_id_from_invoice(stripe_invoice)
      now = Time.current

      user.update!(
        coconique_subscription_status: stripe_subscription_status_for("past_due"),
        coconique_stripe_subscription_id: subscription_id.presence || user.coconique_stripe_subscription_id,
        coconique_subscription_latest_invoice_id: invoice_id.presence || user.coconique_subscription_latest_invoice_id,
        coconique_subscription_past_due_at: user.coconique_subscription_past_due_at || now,
        safety_registered_at: nil
      )

      host_ticket_balance_for(user).record_lifecycle!(
        source: source || user,
        transaction_type: "subscription_past_due",
        description: "Coconique月額プランの支払い確認が必要です",
        metadata: {
          stripe_invoice_id: invoice_id,
          stripe_subscription_id: subscription_id,
          billing_provider: "stripe"
        }.compact
      )
    end

    def sync_stripe_subscription_status!(stripe_subscription:, source: nil)
      subscription_id = stripe_value(stripe_subscription, :id)
      user = User.find_by(coconique_stripe_subscription_id: subscription_id)
      user ||= find_user_for_stripe_customer(stripe_value(stripe_subscription, :customer))
      return nil if user.blank?

      now = Time.current
      stripe_status = stripe_value(stripe_subscription, :status)
      period_started_at = stripe_time(stripe_value(stripe_subscription, :current_period_start))
      period_ends_at = stripe_time(stripe_value(stripe_subscription, :current_period_end))
      canceled_at = stripe_time(stripe_value(stripe_subscription, :canceled_at))
      cancel_at = stripe_time(stripe_value(stripe_subscription, :cancel_at))
      cancel_at_period_end = ActiveModel::Type::Boolean.new.cast(stripe_value(stripe_subscription, :cancel_at_period_end))

      local_status = stripe_subscription_status_for(stripe_status)
      if stripe_subscription_active_status?(stripe_status) && user.coconique_subscription_latest_invoice_id.blank? && !paid_subscription_evidence?(user)
        local_status = :incomplete
      end
      if stripe_subscription_active_status?(stripe_status) && paid_subscription_evidence?(user)
        local_status = :active
      end

      user.update!(
        coconique_stripe_subscription_id: subscription_id.presence || user.coconique_stripe_subscription_id,
        coconique_subscription_status: local_status,
        coconique_subscription_plan: user.coconique_subscription_plan.presence || "founder_beta",
        coconique_subscription_started_at: user.coconique_subscription_started_at || period_started_at || now,
        coconique_subscription_current_period_started_at: period_started_at || user.coconique_subscription_current_period_started_at,
        coconique_subscription_current_period_ends_at: period_ends_at || user.coconique_subscription_current_period_ends_at,
        coconique_subscription_cancel_at_period_end: cancel_at_period_end,
        coconique_subscription_cancel_at: cancel_at,
        coconique_subscription_canceled_at: canceled_at || (stripe_status == "canceled" ? now : user.coconique_subscription_canceled_at),
        coconique_subscription_past_due_at: stripe_status == "past_due" ? (user.coconique_subscription_past_due_at || now) : nil,
        safety_registered_at: %i[active trialing].include?(local_status) ? user.safety_registered_at : nil
      )

      user.refresh_coconique_safety_registered_at! if user.respond_to?(:refresh_coconique_safety_registered_at!)
      user
    end

    def handle_stripe_subscription_deleted!(stripe_subscription:, source: nil)
      user = sync_stripe_subscription_status!(stripe_subscription: stripe_subscription, source: source)
      return nil if user.blank?

      cancel_coconique_subscription!(
        user: user,
        reason: "stripe_subscription_deleted",
        source: source
      )
      user.reload.refresh_coconique_safety_registered_at! if user.respond_to?(:refresh_coconique_safety_registered_at!)
      user
    end


    def repair_paid_subscription_state!(user)
      return user if user.blank? || !user.persisted?
      return user if user.coconique_subscription_active? || user.coconique_subscription_trialing?
      return user unless user.coconique_subscription_founder_beta_like?
      return user unless paid_subscription_evidence?(user)

      now = Time.current
      attrs = {
        coconique_subscription_status: User.coconique_subscription_statuses[:active],
        coconique_subscription_past_due_at: nil,
        safety_registered_at: nil,
        updated_at: now
      }
      if user.coconique_subscription_started_at.blank?
        attrs[:coconique_subscription_started_at] = user.coconique_subscription_current_period_started_at || now
      end
      if user.coconique_subscription_current_period_started_at.blank?
        attrs[:coconique_subscription_current_period_started_at] = user.coconique_subscription_started_at || now
      end
      if user.coconique_subscription_current_period_ends_at.blank?
        attrs[:coconique_subscription_current_period_ends_at] = (attrs[:coconique_subscription_current_period_started_at] || now) + 1.month
      end

      user.update_columns(**attrs)
      user.reload.refresh_coconique_safety_registered_at! if user.respond_to?(:refresh_coconique_safety_registered_at!)
      user
    end

    def paid_subscription_evidence?(user)
      return false if user.blank?
      return false unless user.coconique_subscription_founder_beta_like?
      return false if user.withdrawn? || user.banned?

      period_ends_at = user.coconique_subscription_current_period_ends_at
      return false if period_ends_at.present? && period_ends_at <= Time.current

      return true if user.coconique_subscription_last_payment_at.present?
      return true if user.coconique_subscription_latest_invoice_id.present?

      user.coconique_host_ticket_lots.monthly_grants_for_current_period.exists?
    end

    def capture_stripe_card_fingerprint_signal!(user:, stripe_invoice:, source:)
      return unless defined?(Coconique::ReentrySignals)
      return unless stripe_card_fingerprint_capture_enabled?

      payment_intent = stripe_value(stripe_invoice, :payment_intent)
      payment_intent_id = stripe_id(payment_intent)
      return if payment_intent_id.blank?

      payment_intent_object = payment_intent
      if payment_intent_object.is_a?(String) || stripe_value(payment_intent_object, :payment_method).blank?
        return unless defined?(Stripe::PaymentIntent)

        payment_intent_object = Stripe::PaymentIntent.retrieve(
          id: payment_intent_id,
          expand: ["payment_method"]
        )
      end

      payment_method = stripe_value(payment_intent_object, :payment_method)
      card = stripe_value(payment_method, :card)
      fingerprint = stripe_value(card, :fingerprint)
      return if fingerprint.blank?

      Coconique::ReentrySignals.record_stripe_card_fingerprint!(
        user: user,
        fingerprint: fingerprint,
        source: source,
        metadata: {
          stripe_payment_intent_id: payment_intent_id,
          stripe_invoice_id: stripe_value(stripe_invoice, :id),
          card_brand: stripe_value(card, :brand),
          card_country: stripe_value(card, :country),
          card_last4_present: stripe_value(card, :last4).present?,
          raw_card_number_stored: false
        }.compact
      )
    rescue StandardError => e
      Rails.logger.warn("[CoconiqueBilling] stripe card fingerprint capture skipped: #{e.class}: #{e.message}")
      nil
    end

    def stripe_card_fingerprint_capture_enabled?
      return false if Rails.env.test? && ENV["COCONIQUE_CAPTURE_STRIPE_CARD_FINGERPRINT"].blank?

      ActiveModel::Type::Boolean.new.cast(ENV.fetch("COCONIQUE_CAPTURE_STRIPE_CARD_FINGERPRINT", "true"))
    end

    def find_user_for_stripe_invoice(stripe_invoice)
      metadata = stripe_invoice_metadata(stripe_invoice)
      user = User.find_by(id: metadata["user_id"]) if metadata["user_id"].present?
      return user if user.present?

      subscription_id = stripe_subscription_id_from_invoice(stripe_invoice)
      user = User.find_by(coconique_stripe_subscription_id: subscription_id) if subscription_id.present?
      return user if user.present?

      find_user_for_stripe_customer(stripe_value(stripe_invoice, :customer))
    end

    def find_user_for_stripe_customer(stripe_customer_id)
      return nil if stripe_customer_id.blank?

      StripeCustomer.find_by(stripe_customer_id: stripe_customer_id)&.user
    end

    def find_payment_for_stripe_invoice(stripe_invoice, user: nil)
      metadata = stripe_invoice_metadata(stripe_invoice)
      payment = PaymentCheckoutSession.find_by(id: metadata["payment_checkout_session_id"]) if metadata["payment_checkout_session_id"].present?
      return payment if payment.present?

      subscription_id = stripe_subscription_id_from_invoice(stripe_invoice)
      scope = PaymentCheckoutSession.where(stripe_subscription_id: subscription_id) if subscription_id.present?
      scope ||= user&.payment_checkout_sessions&.where(checkout_mode: "subscription")
      scope&.order(created_at: :desc)&.first
    end

    def stripe_invoice_metadata(stripe_invoice)
      metadata = {}
      [
        stripe_value(stripe_invoice, :metadata),
        stripe_value(stripe_value(stripe_invoice, :subscription_details), :metadata),
        stripe_value(stripe_value(stripe_invoice, :parent), :subscription_details)&.then { |details| stripe_value(details, :metadata) }
      ].compact.each do |candidate|
        candidate.to_h.each { |key, value| metadata[key.to_s] = value }
      end
      metadata
    rescue NoMethodError
      metadata
    end

    def stripe_subscription_id_from_invoice(stripe_invoice)
      direct = stripe_value(stripe_invoice, :subscription)
      return direct if direct.present?

      parent = stripe_value(stripe_invoice, :parent)
      subscription_details = stripe_value(parent, :subscription_details)
      stripe_value(subscription_details, :subscription)
    end

    def stripe_invoice_price_id(stripe_invoice)
      line = stripe_invoice_subscription_line(stripe_invoice)
      price = stripe_value(line, :price)
      stripe_value(price, :id)
    end

    def stripe_invoice_period(stripe_invoice)
      line = stripe_invoice_subscription_line(stripe_invoice)
      period = stripe_value(line, :period)
      started_at = stripe_time(stripe_value(period, :start)) || stripe_time(stripe_value(stripe_invoice, :period_start))
      ends_at = stripe_time(stripe_value(period, :end)) || stripe_time(stripe_value(stripe_invoice, :period_end))
      [started_at, ends_at]
    end

    def stripe_invoice_subscription_line(stripe_invoice)
      lines = stripe_value(stripe_invoice, :lines)
      data = stripe_value(lines, :data)
      Array(data).find do |line|
        price = stripe_value(line, :price)
        recurring = stripe_value(price, :recurring)
        stripe_value(recurring, :interval).present?
      end || Array(data).first
    end

    def stripe_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?

      Time.zone.at(value.to_i)
    end

    def stripe_id(value)
      return nil if value.blank?
      return value if value.is_a?(String)

      stripe_value(value, :id)
    end

    def stripe_value(object, key)
      return nil if object.blank?
      return object[key] if object.respond_to?(:key?) && object.key?(key)
      return object[key.to_s] if object.respond_to?(:key?) && object.key?(key.to_s)
      return object.public_send(key) if object.respond_to?(key)

      nil
    end

    def stripe_subscription_status_for(stripe_status)
      case stripe_status.to_s
      when "trialing" then :trialing
      when "active" then :active
      when "past_due" then :past_due
      when "canceled" then :canceled
      when "unpaid" then :unpaid
      when "incomplete", "incomplete_expired" then :incomplete
      else :none
      end
    end

    def stripe_subscription_active_status?(stripe_status)
      %w[active trialing].include?(stripe_status.to_s)
    end

    def monthly_grant_for_invoice_exists?(user, invoice_id)
      return false if invoice_id.blank?

      user.coconique_host_ticket_lots.any? do |lot|
        lot.metadata["stripe_invoice_id"].to_s == invoice_id.to_s
      end
    end

    def monthly_grant_type_for(user)
      user.coconique_collaborator_beta? ? :collaborator_grant : :monthly_grant
    end
  end
end
