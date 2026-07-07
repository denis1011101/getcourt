require "test_helper"

class ResetInactivePlayerStatisticsJobTest < ActiveJob::TestCase
  test "calls reset inactive stats service" do
    travel_to Time.zone.local(2026, 7, 8, 12, 0, 0) do
      user = User.create!(name: "inactive job", email: "inactive-job-#{SecureRandom.hex(4)}@example.com")
      user.player_statistic.update!(singles_games: 1, singles_wins: 1, singles_rating: 1516.0)
      Match.create!(user: user, mode: "singles", outcome: "win", played_at: 7.months.ago)

      ResetInactivePlayerStatisticsJob.perform_now

      assert_nil user.player_statistic.reload.singles_rating
    end
  end
end
