namespace :participations do
  desc "Reset participations for recurring games"
  task reset: :environment do
    ResetParticipationsJob.perform_now
  end

  desc "Clear participations for past one-off (non-recurring) games"
  task cleanup_one_off: :environment do
    CleanupPastOneOffGamesJob.perform_now
  end
end
