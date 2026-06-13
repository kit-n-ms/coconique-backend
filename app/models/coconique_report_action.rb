class CoconiqueReportAction < ApplicationRecord
  belongs_to :coconique_report
  belongs_to :admin_user, class_name: "User", optional: true

  enum :action_type, {
    note: 0,
    status_change: 10,
    warning: 20,
    restrict: 30,
    suspend: 40,
    ban: 50,
    close: 60,
    reopen: 70
  }

  before_validation :ensure_public_id, on: :create
  before_validation :ensure_metadata

  validates :public_id, presence: true, uniqueness: true
  validates :note, length: { maximum: 5000 }, allow_blank: true

  private

  def ensure_public_id
    self.public_id = "rpa-#{SecureRandom.hex(8)}" if public_id.blank?
  end

  def ensure_metadata
    self.metadata ||= {}
  end
end
