class ResetInactivePlayerStatisticsJob < ApplicationJob
  queue_as :default

  def perform
    reset_count = Statistics::ResetInactiveStatsService.new.call
    Rails.logger.info "Reset inactive player statistics for #{reset_count} players"
  end
end
