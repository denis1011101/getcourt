namespace :statistics do
  desc "Reset player statistics after long inactivity"
  task reset_inactive: :environment do
    ResetInactivePlayerStatisticsJob.perform_now
  end
end
