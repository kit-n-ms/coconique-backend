class CreateCoconiqueSafetyCheckSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_safety_check_settings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: true
      t.integer :mode, null: false, default: 10
      t.integer :start_delay_minutes, null: false, default: 60
      t.integer :reminder_interval_minutes, null: false, default: 30
      t.integer :max_reminders, null: false, default: 3
      t.boolean :notify_contacts_on_no_response, null: false, default: true
      t.boolean :notify_contacts_on_help, null: false, default: false
      t.boolean :share_event_title, null: false, default: false
      t.boolean :share_event_area, null: false, default: false

      t.timestamps
    end

    add_index :coconique_safety_check_settings, :enabled
  end
end
