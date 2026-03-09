namespace :tournaments do
  desc "Remove past tournaments and all dependent data (matches, games, participants, courts, dates)"
  task cleanup_past: :environment do
    CleanupPastTournamentsJob.perform_now
  end
end
