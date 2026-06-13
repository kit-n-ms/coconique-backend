class CreateEmailSuppressions < ActiveRecord::Migration[8.1]
  def change
    create_table :email_suppressions do |t|
      t.string :email, null: false
      t.string :reason, null: false
      t.string :source, null: false
      t.string :source_event_id
      t.datetime :suppressed_at, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :email_suppressions, :email, unique: true
    add_index :email_suppressions, :reason
    add_index :email_suppressions, :source_event_id
  end
end