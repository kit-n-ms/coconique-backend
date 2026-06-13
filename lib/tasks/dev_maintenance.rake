# lib/tasks/dev_maintenance.rake

namespace :dev do
  desc "Clear Solid Queue failed executions in development"
  task clear_solid_queue_failures: :environment do
    abort "development only" unless Rails.env.development?

    count = SolidQueue::FailedExecution.count
    SolidQueue::FailedExecution.delete_all
    puts "deleted SolidQueue::FailedExecution: #{count}"
  end

  desc "Clear email webhook events in development"
  task clear_email_webhook_events: :environment do
    abort "development only" unless Rails.env.development?

    count = EmailWebhookEvent.count
    EmailWebhookEvent.delete_all
    puts "deleted EmailWebhookEvent: #{count}"
  end

  desc "Clear email suppressions in development"
  task clear_email_suppressions: :environment do
    abort "development only" unless Rails.env.development?

    count = EmailSuppression.count
    EmailSuppression.delete_all
    puts "deleted EmailSuppression: #{count}"
  end

  desc "Clear tmp/mails in development"
  task clear_tmp_mails: :environment do
    abort "development only" unless Rails.env.development?

    dir = Rails.root.join("tmp/mails")
    count = Dir.exist?(dir) ? Dir.children(dir).size : 0
    FileUtils.rm_rf(dir)
    FileUtils.mkdir_p(dir)
    puts "deleted tmp/mails files: #{count}"
  end

  desc "Clear common local test artifacts in development"
  task clear_local_artifacts: [
    :clear_solid_queue_failures,
    :clear_email_webhook_events,
    :clear_tmp_mails
  ]
end
