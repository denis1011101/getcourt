require "test_helper"

module PlayerStatistics
  class UpsertMatchForGameServiceTest < ActiveSupport::TestCase
    test "takes the surface from the game the match was played in" do
      court = Court.create!(name: "Surface Court", coordinates: "55.75, 37.61", surfaces: [ "artificial_grass", "hard" ])
      game = Game.create!(court: court, user: users(:two), date: Date.yesterday, time: "10:00", surface: "artificial_grass")

      match = PlayerStatistics::UpsertMatchForGameService.new(
        user: users(:one), game: game, actor: users(:two), mode: :singles, outcome: "win", played_at: game.date.to_time
      ).call

      assert_equal "artificial_grass", match.reload.surface
    end

    test "falls back to the court's surface when the game did not pick one" do
      court = Court.create!(name: "Single Surface Court", coordinates: "55.75, 37.61", surfaces: [ "clay" ])
      game = Game.create!(court: court, user: users(:two), date: Date.yesterday, time: "10:00")

      match = PlayerStatistics::UpsertMatchForGameService.new(
        user: users(:one), game: game, actor: users(:two), mode: :singles, outcome: "loss", played_at: game.date.to_time
      ).call

      assert_equal "clay", match.reload.surface
    end

    test "leaves the surface unknown when the court offers several and the game picked none" do
      court = Court.create!(name: "Mixed Court", coordinates: "55.75, 37.61", surfaces: [ "hard", "clay" ])
      game = Game.create!(court: court, user: users(:two), date: Date.yesterday, time: "10:00")

      match = PlayerStatistics::UpsertMatchForGameService.new(
        user: users(:one), game: game, actor: users(:two), mode: :singles, outcome: "draw", played_at: game.date.to_time
      ).call

      assert_nil match.reload.surface
    end

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

    test "repeated edits to match updated before stats reset do not recount it" do
      user = users(:one)
      actor = users(:two)
      game = Game.create!(
        court: courts(:one),
        user: actor,
        date: 7.months.ago.to_date,
        time: "10:00",
        with_coach: false
      )
      played_at = game.date.to_time
      stats = user.player_statistic
      stats.update!(
        singles_games: 0,
        singles_wins: 0,
        singles_losses: 0,
        singles_hours: 0,
        stats_reset_at: Time.current
      )
      Match.create!(
        user: user,
        game: game,
        mode: "singles",
        outcome: "win",
        played_at: played_at,
        stats: { "hours" => 2.0 }
      )
      Match.where(user: user, game: game).update_all(updated_at: 7.months.ago)

      PlayerStatistics::UpsertMatchForGameService.new(
        user: user,
        game: game,
        actor: actor,
        mode: :singles,
        outcome: "loss",
        played_at: played_at,
        hours: 1.0
      ).call

      PlayerStatistics::UpsertMatchForGameService.new(
        user: user,
        game: game,
        actor: actor,
        mode: :singles,
        outcome: "win",
        played_at: played_at,
        hours: 1.5
      ).call

      stats.reload
      assert_equal 1, stats.singles_games
      assert_equal 1, stats.singles_wins
      assert_equal 0, stats.singles_losses
      assert_equal 1.5, stats.singles_hours
    end

    test "repeated guest singles upsert updates existing match without duplicating counters" do
      user = User.create!(email: "guest_upsert_user@example.com")
      played_at = Time.current

      PlayerStatistics::UpsertMatchForGameService.new(
        user: user,
        game: nil,
        actor: user,
        mode: :singles,
        outcome: "win",
        played_at: played_at,
        score: "6-4",
        stats: {
          "team_a_ids" => [ user.id ],
          "team_b_ids" => [],
          "team_b_guest_names" => [ "Guest One" ]
        }
      ).call

      PlayerStatistics::UpsertMatchForGameService.new(
        user: user,
        game: nil,
        actor: user,
        mode: :singles,
        outcome: "loss",
        played_at: played_at,
        score: "4-6",
        stats: {
          "team_a_ids" => [ user.id ],
          "team_b_ids" => [],
          "team_b_guest_names" => [ "Guest One" ]
        }
      ).call

      stats = user.player_statistic.reload
      assert_equal 1, Match.where(user: user).count
      assert_equal 1, stats.singles_games
      assert_equal 0, stats.singles_wins
      assert_equal 1, stats.singles_losses
    ensure
      Match.where(user: user).delete_all if user
      user&.destroy
    end
  end
end
