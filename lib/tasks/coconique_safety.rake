namespace :coconique do
  namespace :safety do
    desc "Create due safety check sessions and process reminders / emergency contact notifications"
    task process: :environment do
      CoconiqueEvent.finish_due_events!
      CoconiqueSafetyCheckSession.create_due_sessions!
      CoconiqueSafetyCheckSession.process_due_notifications!
      puts "Coconique safety checks processed."
    end
  end
end
