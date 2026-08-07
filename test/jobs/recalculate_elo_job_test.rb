require "test_helper"

class RecalculateEloJobTest < ActiveJob::TestCase
  test "recalculates each valid mode once" do
    recalculated = []

    stub_singleton(PlayerStatistic, :recalculate_elo_for_mode!, ->(mode) { recalculated << mode }) do
      RecalculateEloJob.perform_now([ "singles", "invalid", "singles", "doubles" ])
    end

    assert_equal %w[singles doubles], recalculated
  end
end
