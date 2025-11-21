namespace :participations do
  desc "Reset participations for recurring games"
  task reset: :environment do
    ResetParticipationsJob.perform_now
  end
end
