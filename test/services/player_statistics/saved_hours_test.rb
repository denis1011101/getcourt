require "test_helper"

module PlayerStatistics
  class SavedHoursTest < ActiveSupport::TestCase
    test "keeps hours from the web entry when a newer telegram entry has none" do
      user = users(:one)
      game = Game.create!(court: courts(:one), user: user, date: Date.yesterday, time: "10:00")
      hours_field = StatisticsPresenter.hours_field_for_game(game).to_s

      PlayerStatisticEntry.create!(
        user: user,
        game: game,
        actor: user,
        source: "web",
        recorded_at: 2.hours.ago,
        data: { hours_field => "1.5" }
      )
      PlayerStatisticEntry.create!(
        user: user,
        game: game,
        actor: user,
        source: "telegram",
        recorded_at: 1.hour.ago,
        data: { "aces" => 5 }
      )

      assert_equal 1.5, PlayerStatistics::SavedHours.for_game(game, user: user)
    end

    test "prefers the current user's hours over another participant's newer entry" do
      user = users(:one)
      other = users(:two)
      game = Game.create!(court: courts(:one), user: user, date: Date.yesterday, time: "10:00")
      hours_field = StatisticsPresenter.hours_field_for_game(game).to_s

      PlayerStatisticEntry.create!(
        user: user,
        game: game,
        actor: user,
        source: "web",
        recorded_at: 2.hours.ago,
        data: { hours_field => "1.5" }
      )
      PlayerStatisticEntry.create!(
        user: other,
        game: game,
        actor: other,
        source: "web",
        recorded_at: 1.hour.ago,
        data: { hours_field => "2" }
      )

      assert_equal 1.5, PlayerStatistics::SavedHours.for_game(game, user: user)
    end

    test "returns nil when no entry carries hours" do
      user = users(:one)
      game = Game.create!(court: courts(:one), user: user, date: Date.yesterday, time: "10:00")

      PlayerStatisticEntry.create!(
        user: user,
        game: game,
        actor: user,
        source: "telegram",
        recorded_at: 1.hour.ago,
        data: { "aces" => 5 }
      )

      assert_nil PlayerStatistics::SavedHours.for_game(game, user: user)
    end
  end
end
