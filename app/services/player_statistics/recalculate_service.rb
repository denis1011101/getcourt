module PlayerStatistics
  class RecalculateService
    def initialize(user:, source: nil)
      @user = user
      @source = source
    end

    def call
      keys = StatisticsPresenter.allowed_keys
      totals = {}

      keys.each do |k|
        totals[k] = (PlayerStatistic.numeric_field_type(k) == :float) ? 0.0 : 0
      end

      scope = PlayerStatisticEntry.where(user_id: @user.id)
      scope = scope.where(source: @source) if @source.present?
      scope = scope.where.not(source: Statistics::ResetInactiveStatsService::SOURCE)

      scope.find_each do |e|
        (e.data || {}).each do |k, v|
          next unless totals.key?(k)
          next if v.nil?
          totals[k] += (PlayerStatistic.numeric_field_type(k) == :float) ? v.to_f : v.to_i
        end
      end

      ps = @user.player_statistic || @user.create_player_statistic
      ps.update!(totals)
      ps
    end
  end
end
