class ExtendCoconiqueParticipationRequestsForFlow < ActiveRecord::Migration[8.0]
  def up
    add_column :coconique_participation_requests, :public_id, :string
    add_column :coconique_participation_requests, :withdrawn_at, :datetime

    CoconiqueParticipationRequest.reset_column_information
    CoconiqueParticipationRequest.find_each do |request|
      request.update_columns(public_id: "prq-#{SecureRandom.hex(8)}") if request.public_id.blank?
    end

    change_column_null :coconique_participation_requests, :public_id, false
    add_index :coconique_participation_requests, :public_id, unique: true
    add_index :coconique_participation_requests, :withdrawn_at
  end

  def down
    remove_index :coconique_participation_requests, :withdrawn_at if index_exists?(:coconique_participation_requests, :withdrawn_at)
    remove_index :coconique_participation_requests, :public_id if index_exists?(:coconique_participation_requests, :public_id)
    remove_column :coconique_participation_requests, :withdrawn_at
    remove_column :coconique_participation_requests, :public_id
  end
end
