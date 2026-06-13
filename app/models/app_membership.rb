class AppMembership < ApplicationRecord
  belongs_to :user

  enum :status, {
    active: 0,
    suspended: 1,
    closed: 2
  }

  validates :app_key, presence: true
  validates :app_key, uniqueness: { scope: :user_id }
  validates :started_at, presence: true

  before_validation :set_started_at, on: :create

  private

  def set_started_at
    self.started_at ||= Time.current
  end
end