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
end
