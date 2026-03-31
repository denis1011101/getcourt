require "test_helper"

module PlayerStatistics
  class UpsertMatchForGameServiceTest < ActiveSupport::TestCase
    test "increments games for normal game even when stats entry already exists" do
      user = users(:one)
      actor = users(:two)
      game = Game.create!(
        court: courts(:one),
        user: actor,
        date: Date.yesterday,
        time: "10:00",
        with_coach: false
      )

      PlayerStatisticEntry.create!(
        user: user,
        game: game,
        actor: actor,
        source: "web",
        recorded_at: Time.current,
        data: { "singles_hours" => 1.5 }
      )

      stats = user.player_statistic || user.create_player_statistic
      initial_games = stats.singles_games.to_i
      initial_wins = stats.singles_wins.to_i
      initial_losses = stats.singles_losses.to_i

      assert_difference("Match.count", 1) do
        PlayerStatistics::UpsertMatchForGameService.new(
          user: user,
          game: game,
          actor: actor,
          mode: :singles,
          outcome: "win",
          played_at: game.date.to_time,
          score: "6-4 6-4"
        ).call
      end

      stats.reload
      assert_equal initial_games + 1, stats.singles_games
      assert_equal initial_wins + 1, stats.singles_wins
      assert_equal initial_losses, stats.singles_losses
    end
  end
end
