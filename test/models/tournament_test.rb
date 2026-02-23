require "test_helper"

class TournamentTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "started? returns false without start_date" do
    tournament = Tournament.new
    assert_equal false, tournament.started?
  end

  test "started? returns true for past start_date without time" do
    tournament = Tournament.new(start_date: Date.yesterday)
    assert_equal true, tournament.started?
  end

  test "started? respects start time on start_date" do
    travel_to Time.zone.local(2026, 2, 23, 10, 0, 0) do
      started_tournament = Tournament.new(start_date: Date.current, time: "09:30")
      not_started_tournament = Tournament.new(start_date: Date.current, time: "10:30")

      assert_equal true, started_tournament.started?
      assert_equal false, not_started_tournament.started?
    end
  end
end
