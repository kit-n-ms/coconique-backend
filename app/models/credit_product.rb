class CreditProduct < ApplicationRecord
  validates :app_key, presence: true
  validates :code, presence: true, uniqueness: { scope: :app_key }
  validates :name, presence: true
  validates :amount_jpy, numericality: { greater_than: 0 }
  validates :credits, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(display_order: :asc, id: :asc) }
end