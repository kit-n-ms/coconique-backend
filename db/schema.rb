# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_11_093000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "app_memberships", force: :cascade do |t|
    t.string "app_key", null: false
    t.datetime "created_at", null: false
    t.datetime "started_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["app_key", "status"], name: "index_app_memberships_on_app_key_and_status"
    t.index ["user_id", "app_key"], name: "index_app_memberships_on_user_id_and_app_key", unique: true
    t.index ["user_id"], name: "index_app_memberships_on_user_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.string "target_id"
    t.string "target_type"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["metadata"], name: "index_audit_logs_on_metadata", using: :gin
    t.index ["target_type", "target_id"], name: "index_audit_logs_on_target_type_and_target_id"
    t.index ["user_id", "created_at"], name: "index_audit_logs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "auth_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "csrf_token_digest"
    t.datetime "expires_at", null: false
    t.string "ip_address"
    t.datetime "revoked_at"
    t.string "session_token_digest", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id", null: false
    t.index ["csrf_token_digest"], name: "index_auth_sessions_on_csrf_token_digest"
    t.index ["expires_at"], name: "index_auth_sessions_on_expires_at"
    t.index ["session_token_digest"], name: "index_auth_sessions_on_session_token_digest", unique: true
    t.index ["user_id", "revoked_at"], name: "index_auth_sessions_on_user_id_and_revoked_at"
    t.index ["user_id"], name: "index_auth_sessions_on_user_id"
  end

  create_table "coconique_emergency_contact_notifications", force: :cascade do |t|
    t.bigint "coconique_emergency_contact_id", null: false
    t.bigint "coconique_safety_check_session_id", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "kind", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "public_id", null: false
    t.datetime "sent_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["coconique_emergency_contact_id"], name: "idx_coconique_contact_notifications_on_contact"
    t.index ["coconique_safety_check_session_id", "kind"], name: "idx_coconique_contact_notifications_session_kind"
    t.index ["coconique_safety_check_session_id"], name: "idx_coconique_contact_notifications_on_session"
    t.index ["public_id"], name: "index_coconique_emergency_contact_notifications_on_public_id", unique: true
  end

  create_table "coconique_emergency_contacts", force: :cascade do |t|
    t.string "approval_token_digest"
    t.datetime "approval_token_expires_at"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "last_invited_at"
    t.string "name", null: false
    t.string "public_id", null: false
    t.datetime "rejected_at"
    t.datetime "revoked_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["approval_token_digest"], name: "index_coconique_emergency_contacts_on_approval_token_digest", unique: true
    t.index ["public_id"], name: "index_coconique_emergency_contacts_on_public_id", unique: true
    t.index ["status"], name: "index_coconique_emergency_contacts_on_status"
    t.index ["user_id", "email"], name: "index_coconique_emergency_contacts_on_user_id_and_email", unique: true
    t.index ["user_id"], name: "index_coconique_emergency_contacts_on_user_id"
  end

  create_table "coconique_event_chat_reads", force: :cascade do |t|
    t.bigint "coconique_event_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_read_at"
    t.bigint "last_read_message_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["coconique_event_id", "user_id"], name: "idx_coconique_chat_reads_on_event_and_user", unique: true
    t.index ["coconique_event_id"], name: "index_coconique_event_chat_reads_on_coconique_event_id"
    t.index ["last_read_at"], name: "index_coconique_event_chat_reads_on_last_read_at"
    t.index ["last_read_message_id"], name: "index_coconique_event_chat_reads_on_last_read_message_id"
    t.index ["user_id"], name: "index_coconique_event_chat_reads_on_user_id"
  end

  create_table "coconique_event_favorites", force: :cascade do |t|
    t.bigint "coconique_event_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["coconique_event_id"], name: "index_coconique_event_favorites_on_coconique_event_id"
    t.index ["user_id", "coconique_event_id"], name: "index_coconique_favorites_on_user_and_event", unique: true
    t.index ["user_id"], name: "index_coconique_event_favorites_on_user_id"
  end

  create_table "coconique_event_message_reactions", force: :cascade do |t|
    t.bigint "coconique_event_message_id", null: false
    t.datetime "created_at", null: false
    t.string "emoji_key", null: false
    t.string "public_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["coconique_event_message_id", "user_id", "emoji_key"], name: "idx_coconique_msg_reactions_unique_user_emoji", unique: true
    t.index ["coconique_event_message_id"], name: "idx_coconique_msg_reactions_on_message_id"
    t.index ["emoji_key"], name: "index_coconique_event_message_reactions_on_emoji_key"
    t.index ["public_id"], name: "index_coconique_event_message_reactions_on_public_id", unique: true
    t.index ["user_id"], name: "index_coconique_event_message_reactions_on_user_id"
  end

  create_table "coconique_event_messages", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "coconique_event_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "edited_at"
    t.jsonb "image_urls", default: [], null: false
    t.integer "kind", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "public_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["coconique_event_id", "created_at", "id"], name: "index_coconique_event_messages_on_event_and_created"
    t.index ["coconique_event_id"], name: "index_coconique_event_messages_on_coconique_event_id"
    t.index ["deleted_at"], name: "index_coconique_event_messages_on_deleted_at"
    t.index ["kind"], name: "index_coconique_event_messages_on_kind"
    t.index ["public_id"], name: "index_coconique_event_messages_on_public_id", unique: true
    t.index ["user_id"], name: "index_coconique_event_messages_on_user_id"
  end

  create_table "coconique_event_status_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "coconique_event_id", null: false
    t.datetime "created_at", null: false
    t.string "from_status"
    t.text "reason"
    t.string "to_status", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["coconique_event_id", "created_at"], name: "index_coconique_event_status_logs_on_event_and_created_at"
    t.index ["coconique_event_id"], name: "index_coconique_event_status_logs_on_coconique_event_id"
    t.index ["user_id"], name: "index_coconique_event_status_logs_on_user_id"
  end

  create_table "coconique_events", force: :cascade do |t|
    t.string "area", null: false
    t.string "area_city"
    t.string "area_prefecture"
    t.datetime "canceled_at"
    t.text "cancellation_reason"
    t.integer "capacity", default: 4, null: false
    t.string "category_key", null: false
    t.datetime "closed_at"
    t.string "cost_label", default: "各自負担", null: false
    t.datetime "created_at", null: false
    t.integer "current_participants", default: 0, null: false
    t.string "dress_code", default: "ドレスコードなし", null: false
    t.datetime "ends_at", null: false
    t.datetime "finished_at"
    t.string "host_age_group", default: "30代", null: false
    t.string "host_display_name", default: "ココさん", null: false
    t.bigint "host_id"
    t.text "host_message", default: "", null: false
    t.datetime "host_ticket_consumed_at"
    t.datetime "host_ticket_forfeited_at"
    t.bigint "host_ticket_lot_id"
    t.string "host_ticket_release_reason"
    t.datetime "host_ticket_released_at"
    t.integer "host_ticket_reservation_status", default: 0, null: false
    t.datetime "host_ticket_reserved_at"
    t.bigint "host_ticket_transaction_id"
    t.string "image_url"
    t.jsonb "image_urls", default: [], null: false
    t.integer "interested_count", default: 0, null: false
    t.boolean "is_public_gambling_watching", default: false, null: false
    t.string "meeting_place", null: false
    t.integer "min_participants", default: 2, null: false
    t.string "public_id", null: false
    t.datetime "published_at"
    t.datetime "recruitment_ends_at"
    t.string "reference_url"
    t.boolean "requires_age20_verified", default: false, null: false
    t.boolean "same_gender_only", default: false, null: false
    t.boolean "same_generation_only", default: false, null: false
    t.datetime "starts_at", null: false
    t.integer "status", default: 20, null: false
    t.text "summary", default: "", null: false
    t.jsonb "target_members", default: [], null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["area_prefecture", "area_city"], name: "index_coconique_events_on_area_prefecture_and_area_city"
    t.index ["area_prefecture"], name: "index_coconique_events_on_area_prefecture"
    t.index ["canceled_at"], name: "index_coconique_events_on_canceled_at"
    t.index ["category_key"], name: "index_coconique_events_on_category_key"
    t.index ["closed_at"], name: "index_coconique_events_on_closed_at"
    t.index ["finished_at"], name: "index_coconique_events_on_finished_at"
    t.index ["host_id"], name: "index_coconique_events_on_host_id"
    t.index ["host_ticket_lot_id"], name: "index_coconique_events_on_host_ticket_lot_id"
    t.index ["host_ticket_released_at"], name: "index_coconique_events_on_host_ticket_released_at"
    t.index ["host_ticket_reservation_status"], name: "index_coconique_events_on_host_ticket_reservation_status"
    t.index ["host_ticket_reserved_at"], name: "index_coconique_events_on_host_ticket_reserved_at"
    t.index ["host_ticket_transaction_id"], name: "index_coconique_events_on_host_ticket_transaction_id"
    t.index ["public_id"], name: "index_coconique_events_on_public_id", unique: true
    t.index ["recruitment_ends_at"], name: "index_coconique_events_on_recruitment_ends_at"
    t.index ["same_gender_only"], name: "index_coconique_events_on_same_gender_only"
    t.index ["same_generation_only"], name: "index_coconique_events_on_same_generation_only"
    t.index ["starts_at"], name: "index_coconique_events_on_starts_at"
    t.index ["status", "starts_at"], name: "index_coconique_events_on_status_and_starts_at"
    t.index ["status"], name: "index_coconique_events_on_status"
  end

  create_table "coconique_feedbacks", force: :cascade do |t|
    t.integer "accuracy_answer", null: false
    t.bigint "coconique_event_id", null: false
    t.bigint "coconique_participation_request_id", null: false
    t.datetime "created_at", null: false
    t.bigint "host_id", null: false
    t.integer "join_again_answer", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "private_note"
    t.boolean "public_countable", default: true, null: false
    t.string "public_id", null: false
    t.integer "safety_answer", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["coconique_event_id", "user_id"], name: "idx_coconique_feedbacks_unique_user_event", unique: true
    t.index ["coconique_event_id"], name: "index_coconique_feedbacks_on_coconique_event_id"
    t.index ["coconique_participation_request_id"], name: "idx_coconique_feedbacks_on_participation_request"
    t.index ["coconique_participation_request_id"], name: "idx_coconique_feedbacks_unique_request", unique: true
    t.index ["host_id", "public_countable", "created_at"], name: "idx_coconique_feedbacks_host_public"
    t.index ["host_id"], name: "index_coconique_feedbacks_on_host_id"
    t.index ["public_id"], name: "index_coconique_feedbacks_on_public_id", unique: true
    t.index ["user_id", "created_at"], name: "idx_coconique_feedbacks_user_created"
    t.index ["user_id"], name: "index_coconique_feedbacks_on_user_id"
  end

  create_table "coconique_host_ticket_lots", force: :cascade do |t|
    t.integer "available_count", default: 0, null: false
    t.integer "consumed_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "expired_count", default: 0, null: false
    t.datetime "expires_at"
    t.integer "forfeited_count", default: 0, null: false
    t.integer "grant_type", default: 0, null: false
    t.datetime "granted_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "period_ends_at"
    t.datetime "period_started_at"
    t.string "public_id", null: false
    t.integer "reserved_count", default: 0, null: false
    t.string "source_id"
    t.string "source_type"
    t.integer "total_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["public_id"], name: "index_coconique_host_ticket_lots_on_public_id", unique: true
    t.index ["source_type", "source_id"], name: "index_coconique_host_ticket_lots_on_source_type_and_source_id"
    t.index ["user_id", "expires_at"], name: "index_coconique_host_ticket_lots_on_user_id_and_expires_at"
    t.index ["user_id", "grant_type"], name: "index_coconique_host_ticket_lots_on_user_id_and_grant_type"
    t.index ["user_id"], name: "index_coconique_host_ticket_lots_on_user_id"
  end

  create_table "coconique_identity_verification_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "document_type"
    t.datetime "expires_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "provider", default: "stripe_identity", null: false
    t.string "provider_session_id"
    t.string "provider_status"
    t.string "public_id", null: false
    t.string "return_url"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "user_id", null: false
    t.datetime "verified_at"
    t.string "workflow_type"
    t.index ["provider", "provider_session_id"], name: "idx_coconique_identity_sessions_on_provider_session"
    t.index ["provider_session_id"], name: "idx_on_provider_session_id_edf83031f1"
    t.index ["public_id"], name: "index_coconique_identity_verification_sessions_on_public_id", unique: true
    t.index ["user_id", "status"], name: "idx_on_user_id_status_a3999f41a7"
    t.index ["user_id"], name: "index_coconique_identity_verification_sessions_on_user_id"
    t.index ["workflow_type"], name: "idx_coconique_identity_sessions_on_workflow_type"
  end

  create_table "coconique_notifications", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "kind", null: false
    t.string "link_path", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "notification_key", null: false
    t.datetime "occurred_at", null: false
    t.string "public_id", null: false
    t.datetime "read_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["public_id"], name: "index_coconique_notifications_on_public_id", unique: true
    t.index ["user_id", "deleted_at"], name: "index_coconique_notifications_on_user_id_and_deleted_at"
    t.index ["user_id", "notification_key"], name: "idx_coconique_notifications_user_key", unique: true
    t.index ["user_id", "occurred_at"], name: "index_coconique_notifications_on_user_id_and_occurred_at"
    t.index ["user_id", "read_at"], name: "index_coconique_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_coconique_notifications_on_user_id"
  end

  create_table "coconique_participation_requests", force: :cascade do |t|
    t.text "attendance_note"
    t.datetime "attendance_recorded_at"
    t.bigint "attendance_recorded_by_id"
    t.integer "attendance_status", default: 0, null: false
    t.bigint "coconique_event_id", null: false
    t.datetime "created_at", null: false
    t.text "message", default: "", null: false
    t.string "public_id", null: false
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.integer "status", default: 10, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.datetime "withdrawn_at"
    t.index ["attendance_recorded_by_id"], name: "index_coconique_requests_on_attendance_recorded_by"
    t.index ["coconique_event_id", "attendance_status"], name: "index_coconique_requests_on_event_attendance_status"
    t.index ["coconique_event_id", "status"], name: "index_coconique_requests_on_event_and_status"
    t.index ["coconique_event_id"], name: "index_coconique_participation_requests_on_coconique_event_id"
    t.index ["public_id"], name: "index_coconique_participation_requests_on_public_id", unique: true
    t.index ["reviewed_by_id"], name: "index_coconique_participation_requests_on_reviewed_by_id"
    t.index ["status"], name: "index_coconique_participation_requests_on_status"
    t.index ["user_id", "coconique_event_id"], name: "index_coconique_requests_on_user_event_current", unique: true, where: "(status = ANY (ARRAY[0, 10, 20, 30]))"
    t.index ["user_id"], name: "index_coconique_participation_requests_on_user_id"
    t.index ["withdrawn_at"], name: "index_coconique_participation_requests_on_withdrawn_at"
  end

  create_table "coconique_phone_verification_attempts", force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.string "code_digest", null: false
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "phone_number_digest", null: false
    t.string "provider", default: "fake_sms", null: false
    t.string "public_id", null: false
    t.string "sent_to_masked", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["phone_number_digest"], name: "idx_on_phone_number_digest_3d95412885"
    t.index ["public_id"], name: "index_coconique_phone_verification_attempts_on_public_id", unique: true
    t.index ["user_id", "status"], name: "idx_on_user_id_status_9cb596f148"
    t.index ["user_id"], name: "index_coconique_phone_verification_attempts_on_user_id"
  end

  create_table "coconique_promo_code_redemptions", force: :cascade do |t|
    t.string "code_digest", null: false
    t.string "code_label"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "public_id", null: false
    t.datetime "redeemed_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["code_digest"], name: "index_coconique_promo_code_redemptions_on_code_digest"
    t.index ["public_id"], name: "index_coconique_promo_code_redemptions_on_public_id", unique: true
    t.index ["user_id", "code_digest"], name: "idx_on_user_id_code_digest_21dd3cddfe", unique: true
    t.index ["user_id"], name: "index_coconique_promo_code_redemptions_on_user_id"
  end

  create_table "coconique_report_actions", force: :cascade do |t|
    t.integer "action_type", default: 0, null: false
    t.bigint "admin_user_id"
    t.bigint "coconique_report_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "next_status"
    t.text "note"
    t.string "previous_status"
    t.string "public_id", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_coconique_report_actions_on_admin_user_id"
    t.index ["coconique_report_id", "created_at"], name: "idx_coconique_report_actions_report_created"
    t.index ["coconique_report_id"], name: "idx_coconique_report_actions_on_report"
    t.index ["public_id"], name: "index_coconique_report_actions_on_public_id", unique: true
  end

  create_table "coconique_report_evidences", force: :cascade do |t|
    t.text "body"
    t.bigint "coconique_report_id", null: false
    t.datetime "created_at", null: false
    t.integer "evidence_type", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "public_id", null: false
    t.datetime "updated_at", null: false
    t.index ["coconique_report_id", "evidence_type"], name: "idx_coconique_evidences_report_type"
    t.index ["coconique_report_id"], name: "idx_coconique_report_evidences_on_report"
    t.index ["public_id"], name: "index_coconique_report_evidences_on_public_id", unique: true
  end

  create_table "coconique_reports", force: :cascade do |t|
    t.bigint "coconique_event_id"
    t.bigint "coconique_event_message_id"
    t.bigint "coconique_safety_check_session_id"
    t.datetime "created_at", null: false
    t.text "detail"
    t.string "event_status_at_report"
    t.string "public_id", null: false
    t.integer "reason", default: 0, null: false
    t.integer "report_phase", default: 0, null: false
    t.bigint "reported_user_id"
    t.bigint "reporter_id", null: false
    t.string "reporter_role"
    t.integer "severity", default: 10, null: false
    t.jsonb "snapshot", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.string "target_public_id"
    t.integer "target_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["coconique_event_id"], name: "index_coconique_reports_on_coconique_event_id"
    t.index ["coconique_event_message_id"], name: "idx_coconique_reports_on_message"
    t.index ["coconique_safety_check_session_id"], name: "idx_coconique_reports_on_safety_session"
    t.index ["public_id"], name: "index_coconique_reports_on_public_id", unique: true
    t.index ["reported_user_id", "created_at"], name: "idx_coconique_reports_reported_user_created"
    t.index ["reported_user_id"], name: "index_coconique_reports_on_reported_user_id"
    t.index ["reporter_id", "created_at"], name: "idx_coconique_reports_reporter_created"
    t.index ["reporter_id"], name: "index_coconique_reports_on_reporter_id"
    t.index ["status", "severity", "created_at"], name: "idx_coconique_reports_admin_list"
    t.index ["target_type", "target_public_id"], name: "idx_coconique_reports_target"
  end

  create_table "coconique_safety_check_sessions", force: :cascade do |t|
    t.datetime "answered_at"
    t.bigint "coconique_event_id", null: false
    t.bigint "coconique_participation_request_id"
    t.datetime "created_at", null: false
    t.datetime "due_at", null: false
    t.datetime "escalated_at"
    t.integer "extended_count", default: 0, null: false
    t.text "help_note"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "next_reminder_at", null: false
    t.string "public_id", null: false
    t.integer "reminders_sent_count", default: 0, null: false
    t.integer "response_kind"
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["coconique_event_id", "user_id", "role"], name: "idx_coconique_safety_sessions_unique_user_role", unique: true
    t.index ["coconique_event_id"], name: "index_coconique_safety_check_sessions_on_coconique_event_id"
    t.index ["coconique_participation_request_id"], name: "index_coconique_safety_sessions_on_request_id"
    t.index ["public_id"], name: "index_coconique_safety_check_sessions_on_public_id", unique: true
    t.index ["status", "next_reminder_at"], name: "idx_coconique_safety_sessions_status_next"
    t.index ["user_id", "status", "due_at"], name: "idx_coconique_safety_sessions_user_status_due"
    t.index ["user_id"], name: "index_coconique_safety_check_sessions_on_user_id"
  end

  create_table "coconique_safety_check_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "disabled_at"
    t.boolean "enabled", default: true, null: false
    t.datetime "enabled_since"
    t.integer "max_reminders", default: 3, null: false
    t.integer "mode", default: 10, null: false
    t.boolean "notify_contacts_on_help", default: false, null: false
    t.boolean "notify_contacts_on_no_response", default: true, null: false
    t.integer "reminder_interval_minutes", default: 30, null: false
    t.boolean "share_event_area", default: false, null: false
    t.boolean "share_event_title", default: false, null: false
    t.integer "start_delay_minutes", default: 60, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["enabled"], name: "index_coconique_safety_check_settings_on_enabled"
    t.index ["enabled_since"], name: "index_coconique_safety_check_settings_on_enabled_since"
    t.index ["user_id"], name: "index_coconique_safety_check_settings_on_user_id", unique: true
  end

  create_table "coconique_safety_registration_intents", force: :cascade do |t|
    t.bigint "coconique_event_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.integer "kind", null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "payload", default: {}, null: false
    t.string "public_id", null: false
    t.string "return_path"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["coconique_event_id"], name: "idx_on_coconique_event_id_ba1b6dfee1"
    t.index ["kind"], name: "index_coconique_safety_registration_intents_on_kind"
    t.index ["public_id"], name: "index_coconique_safety_registration_intents_on_public_id", unique: true
    t.index ["user_id", "status"], name: "idx_on_user_id_status_3028ecddff"
    t.index ["user_id"], name: "index_coconique_safety_registration_intents_on_user_id"
  end

  create_table "coconique_user_admin_notes", force: :cascade do |t|
    t.bigint "admin_user_id"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "public_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["admin_user_id"], name: "index_coconique_user_admin_notes_on_admin_user_id"
    t.index ["public_id"], name: "index_coconique_user_admin_notes_on_public_id", unique: true
    t.index ["user_id", "created_at"], name: "idx_coconique_user_admin_notes_user_created"
    t.index ["user_id"], name: "index_coconique_user_admin_notes_on_user_id"
  end

  create_table "coconique_user_blocks", force: :cascade do |t|
    t.bigint "blocked_id", null: false
    t.bigint "blocker_id", null: false
    t.bigint "coconique_report_id"
    t.datetime "created_at", null: false
    t.datetime "lifted_at"
    t.bigint "lifted_by_id"
    t.jsonb "metadata", default: {}, null: false
    t.text "note"
    t.string "public_id", null: false
    t.string "reason"
    t.datetime "updated_at", null: false
    t.index ["blocked_id", "lifted_at"], name: "idx_coconique_blocks_on_blocked_active"
    t.index ["blocker_id", "blocked_id"], name: "idx_coconique_active_blocks_pair", unique: true, where: "(lifted_at IS NULL)"
    t.index ["blocker_id", "lifted_at"], name: "idx_coconique_blocks_on_blocker_active"
    t.index ["coconique_report_id"], name: "index_coconique_user_blocks_on_coconique_report_id"
    t.index ["created_at"], name: "index_coconique_user_blocks_on_created_at"
    t.index ["lifted_by_id"], name: "index_coconique_user_blocks_on_lifted_by_id"
    t.index ["public_id"], name: "index_coconique_user_blocks_on_public_id", unique: true
  end

  create_table "coconique_user_restrictions", force: :cascade do |t|
    t.bigint "coconique_report_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_admin_id"
    t.datetime "ends_at"
    t.datetime "lifted_at"
    t.bigint "lifted_by_admin_id"
    t.jsonb "metadata", default: {}, null: false
    t.text "note"
    t.string "public_id", null: false
    t.string "reason", null: false
    t.datetime "starts_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["coconique_report_id"], name: "idx_coconique_user_restrictions_on_report"
    t.index ["created_by_admin_id"], name: "index_coconique_user_restrictions_on_created_by_admin_id"
    t.index ["lifted_by_admin_id"], name: "index_coconique_user_restrictions_on_lifted_by_admin_id"
    t.index ["public_id"], name: "index_coconique_user_restrictions_on_public_id", unique: true
    t.index ["status", "starts_at"], name: "idx_coconique_user_restrictions_status_started"
    t.index ["user_id", "status", "lifted_at"], name: "idx_coconique_user_restrictions_user_status"
    t.index ["user_id"], name: "index_coconique_user_restrictions_on_user_id"
  end

  create_table "credit_balances", force: :cascade do |t|
    t.string "app_key", null: false
    t.integer "balance", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "app_key"], name: "index_credit_balances_on_user_id_and_app_key", unique: true
    t.index ["user_id"], name: "index_credit_balances_on_user_id"
  end

  create_table "credit_products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "amount_jpy", null: false
    t.string "app_key", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "credits", null: false
    t.text "description"
    t.integer "display_order", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["app_key", "active", "display_order"], name: "index_credit_products_on_app_key_and_active_and_display_order"
    t.index ["app_key", "code"], name: "index_credit_products_on_app_key_and_code", unique: true
  end

  create_table "credit_transactions", force: :cascade do |t|
    t.integer "amount", null: false
    t.string "app_key", null: false
    t.integer "balance_after", null: false
    t.datetime "created_at", null: false
    t.bigint "credit_balance_id", null: false
    t.string "description"
    t.jsonb "metadata", default: {}, null: false
    t.string "source_id"
    t.string "source_type"
    t.string "transaction_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["credit_balance_id"], name: "index_credit_transactions_on_credit_balance_id"
    t.index ["source_type", "source_id"], name: "index_credit_transactions_on_source_type_and_source_id"
    t.index ["transaction_type"], name: "index_credit_transactions_on_transaction_type"
    t.index ["user_id", "app_key", "created_at"], name: "idx_on_user_id_app_key_created_at_6849d84b9d"
    t.index ["user_id"], name: "index_credit_transactions_on_user_id"
  end

  create_table "email_suppressions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "reason", null: false
    t.string "source", null: false
    t.string "source_event_id"
    t.datetime "suppressed_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_email_suppressions_on_email", unique: true
    t.index ["reason"], name: "index_email_suppressions_on_reason"
    t.index ["source_event_id"], name: "index_email_suppressions_on_source_event_id"
  end

  create_table "email_verifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_email_verifications_on_expires_at"
    t.index ["token_digest"], name: "index_email_verifications_on_token_digest", unique: true
    t.index ["user_id", "used_at"], name: "index_email_verifications_on_user_id_and_used_at"
    t.index ["user_id"], name: "index_email_verifications_on_user_id"
  end

  create_table "email_webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.string "message_id"
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at"
    t.text "processing_error"
    t.string "provider", null: false
    t.string "reason"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_email_webhook_events_on_email"
    t.index ["event_type"], name: "index_email_webhook_events_on_event_type"
    t.index ["message_id"], name: "index_email_webhook_events_on_message_id"
    t.index ["processed_at"], name: "index_email_webhook_events_on_processed_at"
    t.index ["provider", "event_id"], name: "index_email_webhook_events_on_provider_and_event_id", unique: true
  end

  create_table "password_resets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_password_resets_on_expires_at"
    t.index ["token_digest"], name: "index_password_resets_on_token_digest", unique: true
    t.index ["user_id", "used_at"], name: "index_password_resets_on_user_id_and_used_at"
    t.index ["user_id"], name: "index_password_resets_on_user_id"
  end

  create_table "payment_checkout_sessions", force: :cascade do |t|
    t.integer "amount_total", null: false
    t.text "cancel_url", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "credit_product_id", null: false
    t.integer "credits", null: false
    t.string "currency", default: "jpy", null: false
    t.datetime "expires_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "status", default: "created", null: false
    t.string "stripe_checkout_session_id"
    t.bigint "stripe_customer_id", null: false
    t.text "success_url", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["credit_product_id"], name: "index_payment_checkout_sessions_on_credit_product_id"
    t.index ["stripe_checkout_session_id"], name: "index_payment_checkout_sessions_on_stripe_checkout_session_id", unique: true
    t.index ["stripe_customer_id"], name: "index_payment_checkout_sessions_on_stripe_customer_id"
    t.index ["user_id", "created_at"], name: "index_payment_checkout_sessions_on_user_id_and_created_at"
    t.index ["user_id", "status"], name: "index_payment_checkout_sessions_on_user_id_and_status"
    t.index ["user_id"], name: "index_payment_checkout_sessions_on_user_id"
  end

  create_table "stripe_customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.boolean "livemode", default: false, null: false
    t.string "stripe_customer_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["stripe_customer_id"], name: "index_stripe_customers_on_stripe_customer_id", unique: true
    t.index ["user_id"], name: "index_stripe_customers_on_user_id", unique: true
  end

  create_table "stripe_webhook_events", force: :cascade do |t|
    t.string "api_version"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.boolean "livemode", default: false, null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at"
    t.text "processing_error"
    t.string "stripe_event_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_stripe_webhook_events_on_event_type"
    t.index ["processed_at"], name: "index_stripe_webhook_events_on_processed_at"
    t.index ["stripe_event_id"], name: "index_stripe_webhook_events_on_stripe_event_id", unique: true
  end

  create_table "terms_acceptances", force: :cascade do |t|
    t.datetime "accepted_at", null: false
    t.string "app_key", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.string "privacy_version", null: false
    t.string "terms_version", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id", null: false
    t.index ["accepted_at"], name: "index_terms_acceptances_on_accepted_at"
    t.index ["app_key", "terms_version", "privacy_version"], name: "index_terms_acceptances_on_versions"
    t.index ["user_id", "app_key"], name: "index_terms_acceptances_on_user_id_and_app_key"
    t.index ["user_id"], name: "index_terms_acceptances_on_user_id"
  end

  create_table "user_profiles", force: :cascade do |t|
    t.text "avatar_url"
    t.text "bio"
    t.jsonb "club_love_levels", default: {}, null: false
    t.jsonb "communication_preferences", default: [], null: false
    t.jsonb "conversation_topics", default: [], null: false
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.string "full_name"
    t.string "home_city"
    t.string "home_prefecture"
    t.date "identity_birth_date"
    t.string "identity_gender"
    t.jsonb "interest_category_keys", default: [], null: false
    t.string "legal_first_name"
    t.string "legal_first_name_kana"
    t.string "legal_full_name_raw"
    t.string "legal_last_name"
    t.string "legal_last_name_kana"
    t.string "legal_middle_name"
    t.string "legal_middle_name_kana"
    t.string "locale", default: "ja", null: false
    t.boolean "marketing_opt_in", default: false, null: false
    t.jsonb "participation_style_keys", default: [], null: false
    t.jsonb "preferred_areas", default: [], null: false
    t.string "profile_headline"
    t.string "public_age_label"
    t.string "timezone", default: "Asia/Tokyo", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["home_prefecture", "home_city"], name: "index_user_profiles_on_home_prefecture_and_home_city"
    t.index ["home_prefecture"], name: "index_user_profiles_on_home_prefecture"
    t.index ["identity_gender"], name: "index_user_profiles_on_identity_gender"
    t.index ["legal_first_name"], name: "index_user_profiles_on_legal_first_name"
    t.index ["legal_first_name_kana"], name: "index_user_profiles_on_legal_first_name_kana"
    t.index ["legal_last_name"], name: "index_user_profiles_on_legal_last_name"
    t.index ["legal_last_name_kana"], name: "index_user_profiles_on_legal_last_name_kana"
    t.index ["locale"], name: "index_user_profiles_on_locale"
    t.index ["public_age_label"], name: "index_user_profiles_on_public_age_label"
    t.index ["user_id"], name: "index_user_profiles_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "age_over_18", default: false, null: false
    t.boolean "age_verified", default: false, null: false
    t.integer "beta_member_type", default: 0, null: false
    t.datetime "billing_exempted_at"
    t.datetime "card_registered_at"
    t.datetime "coconique_founder_beta_joined_at"
    t.date "coconique_last_host_ticket_granted_on"
    t.datetime "coconique_subscription_canceled_at"
    t.datetime "coconique_subscription_current_period_ends_at"
    t.datetime "coconique_subscription_current_period_started_at"
    t.string "coconique_subscription_plan"
    t.datetime "coconique_subscription_started_at"
    t.integer "coconique_subscription_status", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "email_verified_at"
    t.string "identity_document_type"
    t.datetime "identity_external_session_deleted_at"
    t.string "identity_provider"
    t.string "identity_verification_id"
    t.integer "identity_verification_status", default: 0, null: false
    t.datetime "identity_verified_at"
    t.string "identity_workflow_type"
    t.datetime "last_login_at"
    t.integer "operator_verification_status", default: 0, null: false
    t.datetime "operator_verified_at"
    t.string "password_digest", null: false
    t.string "phone_number_digest"
    t.integer "phone_verification_status", default: 0, null: false
    t.datetime "phone_verified_at"
    t.string "promo_code_digest"
    t.datetime "promo_code_verified_at"
    t.integer "role", default: 0, null: false
    t.datetime "safety_registered_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.text "withdrawal_note"
    t.string "withdrawal_reason"
    t.datetime "withdrawn_at"
    t.index ["beta_member_type"], name: "index_users_on_beta_member_type"
    t.index ["coconique_last_host_ticket_granted_on"], name: "index_users_on_coconique_last_host_ticket_granted_on"
    t.index ["coconique_subscription_canceled_at"], name: "index_users_on_coconique_subscription_canceled_at"
    t.index ["coconique_subscription_plan"], name: "index_users_on_coconique_subscription_plan"
    t.index ["coconique_subscription_status"], name: "index_users_on_coconique_subscription_status"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["identity_document_type"], name: "index_users_on_identity_document_type"
    t.index ["identity_provider"], name: "index_users_on_identity_provider"
    t.index ["identity_verification_status"], name: "index_users_on_identity_verification_status"
    t.index ["operator_verification_status"], name: "index_users_on_operator_verification_status"
    t.index ["phone_number_digest"], name: "index_users_on_phone_number_digest"
    t.index ["phone_verification_status"], name: "index_users_on_phone_verification_status"
    t.index ["promo_code_digest"], name: "index_users_on_promo_code_digest"
    t.index ["role"], name: "index_users_on_role"
    t.index ["status"], name: "index_users_on_status"
    t.index ["withdrawn_at"], name: "index_users_on_withdrawn_at"
  end

  add_foreign_key "app_memberships", "users"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "auth_sessions", "users"
  add_foreign_key "coconique_emergency_contact_notifications", "coconique_emergency_contacts"
  add_foreign_key "coconique_emergency_contact_notifications", "coconique_safety_check_sessions"
  add_foreign_key "coconique_emergency_contacts", "users"
  add_foreign_key "coconique_event_chat_reads", "coconique_event_messages", column: "last_read_message_id"
  add_foreign_key "coconique_event_chat_reads", "coconique_events"
  add_foreign_key "coconique_event_chat_reads", "users"
  add_foreign_key "coconique_event_favorites", "coconique_events"
  add_foreign_key "coconique_event_favorites", "users"
  add_foreign_key "coconique_event_message_reactions", "coconique_event_messages"
  add_foreign_key "coconique_event_message_reactions", "users"
  add_foreign_key "coconique_event_messages", "coconique_events"
  add_foreign_key "coconique_event_messages", "users"
  add_foreign_key "coconique_event_status_logs", "coconique_events"
  add_foreign_key "coconique_event_status_logs", "users"
  add_foreign_key "coconique_events", "coconique_host_ticket_lots", column: "host_ticket_lot_id"
  add_foreign_key "coconique_events", "users", column: "host_id"
  add_foreign_key "coconique_feedbacks", "coconique_events"
  add_foreign_key "coconique_feedbacks", "coconique_participation_requests"
  add_foreign_key "coconique_feedbacks", "users"
  add_foreign_key "coconique_feedbacks", "users", column: "host_id"
  add_foreign_key "coconique_host_ticket_lots", "users"
  add_foreign_key "coconique_identity_verification_sessions", "users"
  add_foreign_key "coconique_notifications", "users"
  add_foreign_key "coconique_participation_requests", "coconique_events"
  add_foreign_key "coconique_participation_requests", "users"
  add_foreign_key "coconique_participation_requests", "users", column: "attendance_recorded_by_id"
  add_foreign_key "coconique_participation_requests", "users", column: "reviewed_by_id"
  add_foreign_key "coconique_phone_verification_attempts", "users"
  add_foreign_key "coconique_promo_code_redemptions", "users"
  add_foreign_key "coconique_report_actions", "coconique_reports"
  add_foreign_key "coconique_report_actions", "users", column: "admin_user_id"
  add_foreign_key "coconique_report_evidences", "coconique_reports"
  add_foreign_key "coconique_reports", "coconique_event_messages"
  add_foreign_key "coconique_reports", "coconique_events"
  add_foreign_key "coconique_reports", "coconique_safety_check_sessions"
  add_foreign_key "coconique_reports", "users", column: "reported_user_id"
  add_foreign_key "coconique_reports", "users", column: "reporter_id"
  add_foreign_key "coconique_safety_check_sessions", "coconique_events"
  add_foreign_key "coconique_safety_check_sessions", "coconique_participation_requests"
  add_foreign_key "coconique_safety_check_sessions", "users"
  add_foreign_key "coconique_safety_check_settings", "users"
  add_foreign_key "coconique_safety_registration_intents", "coconique_events"
  add_foreign_key "coconique_safety_registration_intents", "users"
  add_foreign_key "coconique_user_admin_notes", "users"
  add_foreign_key "coconique_user_admin_notes", "users", column: "admin_user_id"
  add_foreign_key "coconique_user_blocks", "coconique_reports"
  add_foreign_key "coconique_user_blocks", "users", column: "blocked_id"
  add_foreign_key "coconique_user_blocks", "users", column: "blocker_id"
  add_foreign_key "coconique_user_blocks", "users", column: "lifted_by_id"
  add_foreign_key "coconique_user_restrictions", "coconique_reports"
  add_foreign_key "coconique_user_restrictions", "users"
  add_foreign_key "coconique_user_restrictions", "users", column: "created_by_admin_id"
  add_foreign_key "coconique_user_restrictions", "users", column: "lifted_by_admin_id"
  add_foreign_key "credit_balances", "users"
  add_foreign_key "credit_transactions", "credit_balances"
  add_foreign_key "credit_transactions", "users"
  add_foreign_key "email_verifications", "users"
  add_foreign_key "password_resets", "users"
  add_foreign_key "payment_checkout_sessions", "credit_products"
  add_foreign_key "payment_checkout_sessions", "stripe_customers"
  add_foreign_key "payment_checkout_sessions", "users"
  add_foreign_key "stripe_customers", "users"
  add_foreign_key "terms_acceptances", "users"
  add_foreign_key "user_profiles", "users"
end
