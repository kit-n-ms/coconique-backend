require "openssl"

module Coconique
  class ReentrySignals
    DIDIT_AUTO_BLOCK_KINDS = %w[
      didit_vendor_user_id
      didit_user_id
      didit_entity_id
      didit_person_id
      didit_biometric_id
      didit_face_reference_id
      didit_document_reference_id
    ].freeze

    STRIPE_REVIEW_KINDS = %w[
      stripe_card_fingerprint
    ].freeze

    class << self
      def record_identity_signals_for_session!(session)
        return [] if session.blank? || session.user.blank?

        metadata = (session.metadata || {}).stringify_keys
        raw_signals = identity_raw_signals(metadata)
        record_many!(
          user: session.user,
          provider: session.provider,
          source: session,
          raw_signals: raw_signals,
          metadata: {
            identity_session_public_id: session.public_id,
            provider_session_id_present: session.provider_session_id.present?,
            document_type: session.document_type,
            workflow_type: session.workflow_type
          }
        )
      end

      def record_stripe_card_fingerprint!(user:, fingerprint:, source:, metadata: {})
        record!(
          user: user,
          signal_kind: "stripe_card_fingerprint",
          raw_value: fingerprint,
          provider: "stripe",
          source: source,
          metadata: metadata
        )
      end

      def record_many!(user:, raw_signals:, provider: nil, source: nil, metadata: {})
        raw_signals.filter_map do |signal_kind, raw_value|
          record!(
            user: user,
            signal_kind: signal_kind,
            raw_value: raw_value,
            provider: provider,
            source: source,
            metadata: metadata
          )
        end
      end

      def record!(user:, signal_kind:, raw_value:, provider: nil, source: nil, metadata: {})
        raw = normalize_raw_value(raw_value)
        return nil if user.blank? || raw.blank?

        digest = digest_for(signal_kind: signal_kind, raw_value: raw)
        now = Time.current
        signal = CoconiqueReentrySignal.find_or_initialize_by(
          user: user,
          signal_kind: signal_kind,
          signal_digest: digest
        )
        signal.assign_attributes(
          provider: provider.presence || signal.provider,
          source_type: source&.class&.name || signal.source_type,
          source_id: source&.id || signal.source_id,
          detected_at: signal.detected_at || now,
          metadata: (signal.metadata || {}).merge((metadata || {}).stringify_keys).merge(
            "raw_value_stored" => false,
            "signal_recorded_at" => now.iso8601
          )
        )
        signal.save!

        if (entry = CoconiqueReentryBlocklistEntry.active.find_by(signal_kind: signal_kind, signal_digest: digest))
          signal.update!(status: :matched_blocklist, matched_blocklist_at: now)
          apply_blocklist_match!(user: user, signal: signal, entry: entry)
        end

        signal
      end

      def block_user_signals!(user:, reason:, source: nil, admin: nil)
        return [] if user.blank?

        now = Time.current
        user.coconique_reentry_signals.blocklistable.map do |signal|
          CoconiqueReentryBlocklistEntry.find_or_create_by!(
            signal_kind: signal.signal_kind,
            signal_digest: signal.signal_digest,
            lifted_at: nil
          ) do |entry|
            entry.source_user = user
            entry.provider = signal.provider
            entry.reason = reason.presence || "規約違反により再登録防止対象に登録"
            entry.blocked_at = now
            entry.metadata = {
              source_type: source&.class&.name,
              source_id: source&.id,
              admin_user_id: admin&.id,
              signal_public_user_id: user.id,
              raw_value_stored: false,
              note: "本人確認書類番号・カード番号・画像は保存せず、照合用HMAC digestのみ保存"
            }.compact
          end
        end
      end

      def blocked_identity_signal?(user)
        return false if user.blank?

        user.coconique_reentry_signals.matched_blocklist.where(signal_kind: DIDIT_AUTO_BLOCK_KINDS).exists?
      end

      def blocked_payment_signal?(user)
        return false if user.blank?

        user.coconique_reentry_signals.matched_blocklist.where(signal_kind: STRIPE_REVIEW_KINDS).exists?
      end

      def digest_for(signal_kind:, raw_value:)
        OpenSSL::HMAC.hexdigest("SHA256", secret, "#{signal_kind}:#{normalize_raw_value(raw_value)}")
      end

      private

      def apply_blocklist_match!(user:, signal:, entry:)
        return if user.blank?
        return if user.coconique_user_restrictions.active.where(status: [:restricted, :suspended, :banned]).exists?

        status = DIDIT_AUTO_BLOCK_KINDS.include?(signal.signal_kind) ? :banned : :restricted
        reason = DIDIT_AUTO_BLOCK_KINDS.include?(signal.signal_kind) ?
          "過去にBANされたユーザーと本人確認シグナルが一致しました。" :
          "過去にBANされたユーザーと決済カードシグナルが一致しました。運営確認が必要です。"

        CoconiqueUserRestriction.create!(
          user: user,
          status: status,
          reason: reason,
          note: "再登録防止シグナルが既存ブロックリストに一致しました。カードfingerprint一致は家族カード等の可能性があるため、必要に応じて運営確認してください。",
          starts_at: Time.current,
          metadata: {
            automatic_reentry_signal_match: true,
            signal_kind: signal.signal_kind,
            signal_id: signal.id,
            blocklist_entry_id: entry.id,
            source_user_id: entry.source_user_id,
            raw_value_stored: false
          }
        )
      end

      def identity_raw_signals(metadata)
        {
          "didit_vendor_user_id" => first_present(metadata, "didit_vendor_user_id", "vendor_user_id", "vendorUserId"),
          "didit_user_id" => first_present(metadata, "didit_user_id", "diditUserId", "provider_user_id", "providerUserId"),
          "didit_entity_id" => first_present(metadata, "didit_entity_id", "entity_id", "entityId"),
          "didit_person_id" => first_present(metadata, "didit_person_id", "person_id", "personId"),
          "didit_biometric_id" => first_present(metadata, "didit_biometric_id", "biometric_id", "biometricId"),
          "didit_face_reference_id" => first_present(metadata, "didit_face_reference_id", "face_reference_id", "faceReferenceId", "face_id", "faceId"),
          "didit_document_reference_id" => first_present(metadata, "didit_document_reference_id", "document_reference_id", "documentReferenceId", "document_id", "documentId")
        }
      end

      def first_present(hash, *keys)
        keys.each do |key|
          value = deep_find(hash, key)
          return value if normalize_raw_value(value).present?
        end
        nil
      end

      def deep_find(object, key)
        case object
        when Hash
          return object[key] if object.key?(key)
          object.each_value do |value|
            found = deep_find(value, key)
            return found if normalize_raw_value(found).present?
          end
        when Array
          object.each do |value|
            found = deep_find(value, key)
            return found if normalize_raw_value(found).present?
          end
        end
        nil
      end

      def normalize_raw_value(value)
        value.to_s.strip.presence
      end

      def secret
        ENV["COCONIQUE_REENTRY_SIGNAL_SECRET"].presence || Rails.application.secret_key_base
      end
    end
  end
end
