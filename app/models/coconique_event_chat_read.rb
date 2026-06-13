class CoconiqueEventChatRead < ApplicationRecord
  belongs_to :coconique_event
  belongs_to :user
  belongs_to :last_read_message,
    class_name: "CoconiqueEventMessage",
    optional: true

  validates :user_id, uniqueness: { scope: :coconique_event_id }

  def self.mark_read!(event:, user:, message: nil)
    return if event.blank? || user.blank?

    latest_message = message || event.coconique_event_messages.visible.order(created_at: :desc, id: :desc).first
    return if latest_message.blank?

    read_state = find_or_initialize_by(coconique_event: event, user: user)
    return if read_state.last_read_at.present? && read_state.last_read_at >= latest_message.created_at

    read_state.last_read_message = latest_message
    read_state.last_read_at = latest_message.created_at
    read_state.save!
  end
end
