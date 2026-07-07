module Statistics
  class ResetInactiveStatsService
    INACTIVITY_PERIOD = 6.months
    SOURCE = "inactivity_reset"

    def call
      reset_count = 0

      PlayerStatistic.includes(:user).find_each do |statistic|
        next unless statistic.resettable_statistics?

        last_activity_at = last_activity_at(statistic.user_id)
        next unless last_activity_at && last_activity_at < INACTIVITY_PERIOD.ago
        next unless statistic.stats_reset_at.blank? || statistic.stats_reset_at < last_activity_at

        reset_statistic!(statistic)
        reset_count += 1
      end

      reset_count
    end

    private

    def last_activity_at(user_id)
      [
        Match.where(user_id: user_id).maximum(:played_at),
        PlayerStatisticEntry.where(user_id: user_id).where.not(source: SOURCE).maximum(:recorded_at)
      ].compact.max
    end

    def reset_statistic!(statistic)
      statistic.with_lock do
        now = Time.current

        PlayerStatisticEntry.create!(
          user: statistic.user,
          actor: statistic.user,
          source: SOURCE,
          data: { "snapshot" => statistic.attributes },
          recorded_at: now
        )

        statistic.update!(PlayerStatistic.reset_attributes.merge(stats_reset_at: now))
      end
    end
  end
end
