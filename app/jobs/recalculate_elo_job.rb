class RecalculateEloJob < ApplicationJob
  queue_as :default

  def perform(modes)
    Array(modes).map(&:to_s).uniq.each do |mode|
      PlayerStatistic.recalculate_elo_for_mode!(mode) if Match::MODES.include?(mode)
    end
  end
end
