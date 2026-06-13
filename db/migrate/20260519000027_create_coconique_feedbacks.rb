class CreateCoconiqueFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :coconique_feedbacks do |t|
      t.string :public_id, null: false
      t.references :user, null: false, foreign_key: true
      t.references :host, null: false, foreign_key: { to_table: :users }
      t.references :coconique_event, null: false, foreign_key: true
      t.references :coconique_participation_request, null: false, foreign_key: true, index: { name: "idx_coconique_feedbacks_on_participation_request" }
      t.integer :safety_answer, null: false
      t.integer :accuracy_answer, null: false
      t.integer :join_again_answer, null: false
      t.text :private_note
      t.integer :status, null: false, default: 0
      t.boolean :public_countable, null: false, default: true
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :coconique_feedbacks, :public_id, unique: true
    add_index :coconique_feedbacks, :coconique_participation_request_id, unique: true, name: "idx_coconique_feedbacks_unique_request"
    add_index :coconique_feedbacks, [:coconique_event_id, :user_id], unique: true, name: "idx_coconique_feedbacks_unique_user_event"
    add_index :coconique_feedbacks, [:host_id, :public_countable, :created_at], name: "idx_coconique_feedbacks_host_public"
    add_index :coconique_feedbacks, [:user_id, :created_at], name: "idx_coconique_feedbacks_user_created"
  end
end
