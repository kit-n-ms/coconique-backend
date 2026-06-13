module Api
  module V1
    module Admin
      class CoconiqueHostTicketsController < BaseController
        def release_event
          event = find_event!
          reason = admin_reason(default: "運営判断により主催チケットを返還")

          transaction = nil
          was_open = cancelable_open_event?(event)
          user_message = admin_user_message(
            default_message: was_open ? "利用規約に抵触する募集内容のためキャンセルとなりました。チケットの返還が行われました。" : "キャンセルの理由によりチケットが返還されました。"
          )

          event.with_lock do
            event.reload
            was_open = cancelable_open_event?(event)
            previous_status = event.status

            if was_open
              event.cancel!(reason: reason, host_ticket_policy: :release, cancellation_notice_kind: :admin)
              event.coconique_event_status_logs.create!(
                user: current_user,
                action: "admin.coconique_event.canceled_with_ticket_release",
                from_status: previous_status,
                to_status: event.status,
                reason: reason
              )
              transaction = latest_event_ticket_transaction(event, "release_reserved")
            else
              transaction = ::CoconiqueBilling.release_reserved_host_ticket_for_event!(
                event: event,
                reason: reason,
                admin: current_user
              )
            end
          end

          notify_host!(
            event: event.reload,
            title: was_open ? "募集をキャンセルし、チケットを返還しました" : "主催チケットを返還しました",
            body: user_message,
            metadata: { host_ticket_returned: true, admin_cancel: was_open }
          )

          AuditLog.record!(
            user: current_user,
            action: was_open ? "admin.coconique_host_ticket.cancel_and_release_event" : "admin.coconique_host_ticket.release_event",
            request: request,
            target: event,
            metadata: {
              event_public_id: event.public_id,
              host_id: event.host_id,
              transaction_id: transaction&.id,
              reason: reason,
              user_message: user_message,
              admin_cancel: was_open
            }
          )

          render_success({ event: event_ticket_json(event.reload), transaction: transaction_json(transaction) })
        end

        def forfeit_event
          event = find_event!
          reason = admin_reason(default: "運営判断により主催チケットを没収")

          transaction = nil
          was_open = cancelable_open_event?(event)
          user_message = admin_user_message(
            default_message: was_open ? "利用規約に抵触する募集内容のためキャンセルとなりました。" : "利用規約に抵触する内容が確認されたため、主催チケットは返還されませんでした。"
          )

          event.with_lock do
            event.reload
            was_open = cancelable_open_event?(event)
            previous_status = event.status

            if was_open
              event.cancel!(reason: reason, host_ticket_policy: :forfeit, cancellation_notice_kind: :admin)
              event.coconique_event_status_logs.create!(
                user: current_user,
                action: "admin.coconique_event.canceled_with_ticket_forfeit",
                from_status: previous_status,
                to_status: event.status,
                reason: reason
              )
              transaction = latest_event_ticket_transaction(event, "forfeit_reserved")
            else
              transaction = ::CoconiqueBilling.forfeit_reserved_host_ticket_for_event!(
                event: event,
                reason: reason,
                admin: current_user
              )
            end
          end

          notify_host!(
            event: event.reload,
            title: was_open ? "募集をキャンセルしました" : "主催チケットを没収確定しました",
            body: user_message,
            metadata: { host_ticket_forfeited: true, admin_cancel: was_open }
          )

          AuditLog.record!(
            user: current_user,
            action: was_open ? "admin.coconique_host_ticket.cancel_and_forfeit_event" : "admin.coconique_host_ticket.forfeit_event",
            request: request,
            target: event,
            metadata: {
              event_public_id: event.public_id,
              host_id: event.host_id,
              transaction_id: transaction&.id,
              reason: reason,
              user_message: user_message,
              admin_cancel: was_open
            }
          )

          render_success({ event: event_ticket_json(event.reload), transaction: transaction_json(transaction) })
        end

        private

        def find_event!
          ::CoconiqueEvent.find_by!(public_id: params[:public_id])
        end

        def admin_reason(default:)
          params[:reason].to_s.presence || default
        end

        def admin_user_message(default_message:)
          params[:user_message].to_s.presence || params[:userMessage].to_s.presence || default_message
        end

        def cancelable_open_event?(event)
          event.recruiting? || event.closed? || event.confirmed?
        end

        def latest_event_ticket_transaction(event, type)
          return nil if event.blank?

          ::CreditTransaction.where(
            app_key: ::CoconiqueBilling::APP_KEY,
            source_type: event.class.name,
            source_id: event.id.to_s,
            transaction_type: type
          ).order(created_at: :desc, id: :desc).first
        end

        def notify_host!(event:, title:, body:, metadata: {})
          return if event.host.blank?

          ::CoconiqueNotification.create_system_notification!(
            user: event.host,
            notification_key: "admin-event-ticket-#{event.public_id}-#{event.host_ticket_reservation_status}-#{SecureRandom.hex(6)}",
            title: title,
            body: body,
            link_path: "/app/host/events/#{event.public_id}",
            occurred_at: Time.current,
            metadata: {
              event_public_id: event.public_id,
              event_title: event.title,
              admin_user_id: current_user.id
            }.merge(metadata || {})
          )
        end

        def event_ticket_json(event)
          {
            id: event.public_id,
            title: event.title,
            status: event.status,
            canceledAt: event.canceled_at&.iso8601,
            cancellationReason: event.cancellation_reason,
            hostTicketReservationStatus: event.host_ticket_reservation_status,
            hostTicketReservedAt: event.host_ticket_reserved_at&.iso8601,
            hostTicketConsumedAt: event.host_ticket_consumed_at&.iso8601,
            hostTicketReleasedAt: event.host_ticket_released_at&.iso8601,
            hostTicketForfeitedAt: event.host_ticket_forfeited_at&.iso8601,
            hostTicketReleaseReason: event.host_ticket_release_reason
          }
        end

        def transaction_json(transaction)
          return nil if transaction.blank?

          {
            id: transaction.id,
            transactionType: transaction.transaction_type,
            amount: transaction.amount,
            balanceAfter: transaction.balance_after,
            description: transaction.description,
            createdAt: transaction.created_at&.iso8601
          }
        end
      end
    end
  end
end
