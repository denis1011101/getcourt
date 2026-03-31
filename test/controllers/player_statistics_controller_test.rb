require "test_helper"

class PlayerStatisticsControllerTest < ActionDispatch::IntegrationTest
  test "score upsert increments games even when stats entry already exists for normal game" do
    post session_url, params: { email: "stats_owner@example.com" }
    owner = User.find_by!(email: "stats_owner@example.com")
    participant = User.create!(email: "stats_participant@example.com")

    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.yesterday,
      time: "10:00",
      with_coach: false
    )
    Participation.create!(game: game, user: participant, status: "approved")

    post game_player_statistics_url(game), params: {
      statistics: { hours: "1.5" }
    }

    assert_redirected_to game_path(game)
    assert_equal 1, PlayerStatisticEntry.where(game: game, user: participant).count

    post game_player_statistics_url(game), params: {
      statistics: { score: "6-4 6-4" },
      team_a_user_ids: [ owner.id ],
      team_b_user_ids: [ participant.id ],
      winner_team: "b"
    }

    assert_redirected_to game_path(game)

    participant_stats = participant.player_statistic.reload
    assert_equal 1, participant_stats.singles_games
    assert_equal 1, participant_stats.singles_wins
    assert_equal 0, participant_stats.singles_losses
  end
end
