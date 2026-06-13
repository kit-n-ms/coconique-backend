class CoconiqueEventStatusLog < ApplicationRecord
  belongs_to :coconique_event
  belongs_to :user, optional: true

  validates :action, presence: true, length: { maximum: 100 }
  validates :to_status, presence: true, length: { maximum: 50 }
  validates :from_status, length: { maximum: 50 }, allow_blank: true
  validates :reason, length: { maximum: 1000 }, allow_blank: true
end
