class TermsAcceptance < ApplicationRecord
  belongs_to :user

  validates :app_key, presence: true
  validates :terms_version, presence: true
  validates :privacy_version, presence: true
  validates :accepted_at, presence: true

  before_validation :set_accepted_at, on: :create

  private

  def set_accepted_at
    self.accepted_at ||= Time.current
  end
end