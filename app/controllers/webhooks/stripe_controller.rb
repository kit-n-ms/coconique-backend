module Webhooks
  class StripeController < ActionController::API
    def create
      event = construct_stripe_event!

      webhook_event = StripeWebhookEvent.find_or_initialize_by(
        stripe_event_id: event.id
      )

      if webhook_event.persisted? && webhook_event.processed?
        return render json: { ok: true, skipped: true }
      end

      webhook_event.assign_attributes(
        event_type: event.type,
        api_version: event.api_version,
        livemode: event.livemode || false,
        payload: event.to_hash
      )

      webhook_event.save!

      process_event!(event)

      webhook_event.update!(
        processed_at: Time.current,
        processing_error: nil
      )

      render json: { ok: true }
    rescue JSON::ParserError
      render json: { ok: false, error: "invalid_payload" }, status: :bad_request
    rescue Stripe::SignatureVerificationError
      render json: { ok: false, error: "invalid_signature" }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("[StripeWebhook] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      if defined?(webhook_event) && webhook_event.present?
        webhook_event.update!(
          processing_error: "#{e.class}: #{e.message}"
        )
      end

      render json: { ok: false, error: "webhook_processing_failed" }, status: :internal_server_error
    end

    private

    def construct_stripe_event!
      payload = request.raw_post
      signature = request.env["HTTP_STRIPE_SIGNATURE"]
      secret = ENV.fetch("STRIPE_WEBHOOK_SECRET")

      Stripe::Webhook.construct_event(
        payload,
        signature,
        secret
      )
    end

    def process_event!(event)
      case event.type
      when "checkout.session.completed"
        handle_checkout_session_completed!(event.data.object)
      when "checkout.session.expired"
        handle_checkout_session_expired!(event.data.object)
      when "identity.verification_session.verified"
        handle_identity_verification_session_verified!(event.data.object)
      when "identity.verification_session.requires_input"
        handle_identity_verification_session_requires_input!(event.data.object)
      when "identity.verification_session.canceled"
        handle_identity_verification_session_canceled!(event.data.object)
      else
        Rails.logger.info("[StripeWebhook] ignored event: #{event.type}")
      end
    end

    def handle_checkout_session_completed!(session)
      payment = PaymentCheckoutSession.find_by!(
        stripe_checkout_session_id: session.id
      )

      return if payment.completed?

      unless session.payment_status == "paid"
        Rails.logger.warn("[StripeWebhook] checkout.session.completed but payment_status=#{session.payment_status}")
        return
      end

      CoconiqueBilling.complete_checkout_session!(
        payment,
        stripe_payment_status: session.payment_status,
        stripe_payment_intent: session.payment_intent,
        fake_checkout: false
      )
    end

    def handle_identity_verification_session_verified!(session)
      local_session = CoconiqueIdentityVerificationSession.find_by!(provider_session_id: session.id)
      local_session.mark_verified!(
        provider_session_id: session.id,
        age_over_18: true,
        provider_status: session.status,
        document_type: local_session.document_type.presence || "unknown",
        metadata: {
          stripe_status: session.status,
          stripe_livemode: session.respond_to?(:livemode) ? session.livemode : nil
        }.compact
      )
    end

    def handle_identity_verification_session_requires_input!(session)
      local_session = CoconiqueIdentityVerificationSession.find_by(provider_session_id: session.id)
      return if local_session.blank?

      local_session.mark_requires_input!(provider_status: session.status, metadata: { "stripe_status" => session.status })
    end

    def handle_identity_verification_session_canceled!(session)
      local_session = CoconiqueIdentityVerificationSession.find_by(provider_session_id: session.id)
      return if local_session.blank?

      local_session.mark_canceled!(provider_status: session.status, metadata: { "stripe_status" => session.status })
    end

    def handle_checkout_session_expired!(session)
      payment = PaymentCheckoutSession.find_by(
        stripe_checkout_session_id: session.id
      )

      return if payment.blank?
      return if payment.completed?

      payment.update!(
        status: "expired"
      )
    end
  end
end
