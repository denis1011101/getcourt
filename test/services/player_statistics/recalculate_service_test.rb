require "test_helper"

module PlayerStatistics
  class RecalculateServiceTest < ActiveSupport::TestCase
    test "ignores inactivity reset snapshots" do
      user = users(:one)
      actor = users(:two)

      PlayerStatisticEntry.create!(
        user: user,
        actor: actor,
        source: Statistics::ResetInactiveStatsService::SOURCE,
        recorded_at: Time.current,
        data: { "snapshot" => { "singles_games" => 99, "aces" => 99 } }
      )
      PlayerStatisticEntry.create!(
        user: user,
        actor: actor,
        source: "telegram",
        recorded_at: Time.current,
        data: { "singles_games" => 1, "aces" => 2 }
      )

      statistic = PlayerStatistics::RecalculateService.new(user: user).call

      assert_equal 1, statistic.singles_games
      assert_equal 2, statistic.aces
    end
  end
end
