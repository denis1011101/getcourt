require "test_helper"

module Statistics
  class ResetInactiveStatsServiceTest < ActiveSupport::TestCase
    def setup
      @now = Time.zone.local(2026, 7, 8, 12, 0, 0)
    end

    test "resets inactive player statistics and stores snapshot" do
      travel_to @now do
        user = create_user("inactive")
        statistic = statistic_with_values(user)
        Match.create!(user: user, mode: "singles", outcome: "win", played_at: 7.months.ago)

        assert_difference("PlayerStatisticEntry.where(source: 'inactivity_reset').count", 1) do
          assert_equal 1, ResetInactiveStatsService.new.call
        end

        statistic.reload
        assert_equal 0, statistic.singles_games
        assert_equal 0, statistic.singles_hours
        assert_nil statistic.singles_rating
        assert_nil statistic.first_serve_percent
        assert_in_delta @now, statistic.stats_reset_at, 1.second

        snapshot = PlayerStatisticEntry.where(user: user, source: "inactivity_reset").last
        assert_equal 3, snapshot.data["snapshot"]["singles_games"]
        assert_equal 1600.0, snapshot.data["snapshot"]["singles_rating"]
      end
    end

    test "does not reset active player" do
      travel_to @now do
        user = create_user("active")
        statistic_with_values(user)
        Match.create!(user: user, mode: "singles", outcome: "win", played_at: 1.month.ago)

        assert_no_difference("PlayerStatisticEntry.where(source: 'inactivity_reset').count") do
          assert_equal 0, ResetInactiveStatsService.new.call
        end
      end
    end

    test "does not reset at exact inactivity boundary" do
      travel_to @now do
        user = create_user("boundary")
        statistic_with_values(user)
        Match.create!(user: user, mode: "singles", outcome: "win", played_at: 6.months.ago)

        assert_equal 0, ResetInactiveStatsService.new.call
      end
    end

    test "second run is idempotent" do
      travel_to @now do
        user = create_user("idempotent")
        statistic_with_values(user)
        Match.create!(user: user, mode: "singles", outcome: "win", played_at: 7.months.ago)

        assert_equal 1, ResetInactiveStatsService.new.call

        assert_no_difference("PlayerStatisticEntry.where(user: user, source: 'inactivity_reset').count") do
          assert_equal 0, ResetInactiveStatsService.new.call
        end
      end
    end

    test "allows multiple reset snapshots with nil game_id" do
      user = create_user("repeat-reset")

      travel_to Time.zone.local(2026, 1, 1, 12, 0, 0) do
        statistic_with_values(user)
        Match.create!(user: user, mode: "singles", outcome: "win", played_at: 7.months.ago)
        assert_equal 1, ResetInactiveStatsService.new.call
      end

      travel_to Time.zone.local(2026, 2, 1, 12, 0, 0) do
        Match.create!(user: user, mode: "singles", outcome: "win", played_at: Time.current)
        user.player_statistic.update!(singles_games: 1, singles_wins: 1, singles_rating: 1516.0)
      end

      travel_to Time.zone.local(2026, 9, 2, 12, 0, 0) do
        assert_nothing_raised do
          assert_equal 1, ResetInactiveStatsService.new.call
        end

        assert_equal 2, PlayerStatisticEntry.where(user: user, source: "inactivity_reset", game_id: nil).count
      end
    end

    private

    def create_user(name)
      User.create!(name: name, email: "#{name}-#{SecureRandom.hex(4)}@example.com")
    end

    def statistic_with_values(user)
      user.player_statistic.tap do |statistic|
        statistic.update!(
          singles_games: 3,
          singles_wins: 2,
          singles_losses: 1,
          singles_hours: 4.5,
          aces: 5,
          first_serve_percent: 61.2,
          singles_rating: 1600.0
        )
      end
    end
  end
end
