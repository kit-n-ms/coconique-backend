class CoconiqueEventFavorite < ApplicationRecord
  belongs_to :user
  belongs_to :coconique_event

  validates :user_id, uniqueness: { scope: :coconique_event_id }

  after_create :increment_event_interested_count!
  after_destroy :decrement_event_interested_count!

  private

  def increment_event_interested_count!
    coconique_event.increment!(:interested_count)
  end

  def decrement_event_interested_count!
    coconique_event.with_lock do
      coconique_event.update!(
        interested_count: [coconique_event.interested_count - 1, 0].max
      )
    end
  end
end
