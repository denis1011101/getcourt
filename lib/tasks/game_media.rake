namespace :game_media do
  desc "Destroy game photos and clips older than a month (frees disk space)"
  task cleanup_old: :environment do
    CleanupOldGameMediaJob.perform_now
  end
end
