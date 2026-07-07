require "test_helper"

class PlayerStatisticTest < ActiveSupport::TestCase
  test "summary_for returns correct totals" do
    user = users(:one)
    # fixture: singles_games=1, doubles_games=1, singles_wins=1, doubles_wins=1
    summary = PlayerStatistic.summary_for(user)
    assert_equal 2, summary[:games]
    assert_equal 2, summary[:wins]
    assert_equal 100.0, summary[:win_pct]
  end

  test "summary_for returns zeros when no record exists" do
    user = User.new(id: 99999)
    summary = PlayerStatistic.summary_for(user)
    assert_equal 0, summary[:games]
    assert_equal 0, summary[:wins]
    assert_nil summary[:win_pct]
  end

  test "elo recalculation starts from base after stats reset" do
    travel_to Time.zone.local(2026, 7, 8, 12, 0, 0) do
      player = create_user("elo-player")
      opponent = create_user("elo-opponent")
      statistic = player.player_statistic

      statistic.record_match!(mode: :singles, won: true, opponent: opponent, played_at: 7.months.ago)
      assert_operator statistic.reload.singles_rating, :>, PlayerStatistic::BASE_ELO

      Statistics::ResetInactiveStatsService.new.call
      assert_nil statistic.reload.singles_rating

      statistic.record_match!(mode: :singles, won: true, opponent: opponent, played_at: Time.current)

      opponent_rating = Ratings::EloRatingService.new(
        current_rating: PlayerStatistic::BASE_ELO,
        opponent_rating: PlayerStatistic::BASE_ELO,
        result: PlayerStatistic::ELO_RESULTS.fetch("loss")
      ).call
      expected_rating = Ratings::EloRatingService.new(
        current_rating: PlayerStatistic::BASE_ELO,
        opponent_rating: opponent_rating,
        result: PlayerStatistic::ELO_RESULTS.fetch("win")
      ).call

      assert_in_delta expected_rating, statistic.reload.singles_rating, 0.01
    end
  end

  test "elo recalculation does not restore rating when reset happened after last match" do
    travel_to Time.zone.local(2026, 7, 8, 12, 0, 0) do
      inactive = create_user("inactive-elo")
      opponent = create_user("inactive-opponent")
      active = create_user("active-elo")
      active_opponent = create_user("active-opponent")

      inactive.player_statistic.record_match!(mode: :singles, won: true, opponent: opponent, played_at: 7.months.ago)
      Statistics::ResetInactiveStatsService.new.call

      active.player_statistic.record_match!(mode: :singles, won: true, opponent: active_opponent, played_at: Time.current)

      assert_nil inactive.player_statistic.reload.singles_rating
    end
  end

  private

  def create_user(name)
    User.create!(name: name, email: "#{name}-#{SecureRandom.hex(4)}@example.com")
  end
end
