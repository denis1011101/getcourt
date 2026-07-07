require "test_helper"

module PlayerStatistics
  class ApplyEntryServiceTest < ActiveSupport::TestCase
    test "editing entry recorded before stats reset does not subtract stale values" do
      user = users(:one)
      actor = users(:two)
      game = Game.create!(court: courts(:one), user: actor, date: 7.months.ago.to_date)
      statistic = user.player_statistic
      statistic.update!(aces: 0, stats_reset_at: Time.current)

      PlayerStatisticEntry.create!(
        user: user,
        game: game,
        actor: actor,
        source: "telegram",
        recorded_at: 7.months.ago,
        data: { "aces" => 5 }
      )

      PlayerStatistics::ApplyEntryService.new(
        user: user,
        game: game,
        actor: actor,
        data: { "aces" => 3 },
        source: "telegram"
      ).call

      assert_equal 3, statistic.reload.aces
    end
  end
end
