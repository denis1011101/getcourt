namespace :games do
  desc "Reset participations for recurring games (runs ResetParticipationsJob)"
  task reset_participations: :environment do
    ResetParticipationsJob.perform_now
  end
end
