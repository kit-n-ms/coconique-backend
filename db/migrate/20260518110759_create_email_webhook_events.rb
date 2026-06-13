class CreateEmailWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :email_webhook_events do |t|
      t.string :provider, null: false
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :email
      t.string :message_id
      t.string :status
      t.string :reason
      t.jsonb :payload, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :processed_at
      t.text :processing_error

      t.timestamps
    end

    add_index :email_webhook_events, [:provider, :event_id], unique: true
    add_index :email_webhook_events, :event_type
    add_index :email_webhook_events, :email
    add_index :email_webhook_events, :message_id
    add_index :email_webhook_events, :processed_at
  end
end