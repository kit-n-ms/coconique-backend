class CreateCoconiqueSafetyRegistrationIntents < ActiveRecord::Migration[8.0]
  def change
    create_table :coconique_safety_registration_intents do |t|
      t.references :user, null: false, foreign_key: true
      t.references :coconique_event, foreign_key: true
      t.string :public_id, null: false
      t.integer :kind, null: false
      t.integer :status, null: false, default: 0
      t.string :return_path
      t.datetime :expires_at, null: false
      t.datetime :completed_at
      t.jsonb :payload, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_safety_registration_intents, :public_id, unique: true
    add_index :coconique_safety_registration_intents, [:user_id, :status], name: "idx_coconique_safety_intents_user_status"
    add_index :coconique_safety_registration_intents, :kind
  end
end
