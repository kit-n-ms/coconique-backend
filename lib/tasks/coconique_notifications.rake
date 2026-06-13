namespace :coconique do
  namespace :notifications do
    desc "Delete notifications soft-deleted more than 90 days ago"
    task cleanup_deleted: :environment do
      threshold = 90.days.ago
      deleted = CoconiqueNotification.where.not(deleted_at: nil).where("deleted_at < ?", threshold).delete_all
      puts "Deleted Coconique notifications soft-deleted before #{threshold.iso8601}: #{deleted}"
    end
  end
end
