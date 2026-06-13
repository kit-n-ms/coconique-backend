class CreateStripeWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :stripe_webhook_events do |t|
      t.string :stripe_event_id, null: false
      t.string :event_type, null: false
      t.string :api_version
      t.boolean :livemode, null: false, default: false
      t.datetime :processed_at
      t.text :processing_error
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :stripe_webhook_events, :stripe_event_id, unique: true
    add_index :stripe_webhook_events, :event_type
    add_index :stripe_webhook_events, :processed_at
  end
end