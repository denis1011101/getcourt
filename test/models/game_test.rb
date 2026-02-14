require "test_helper"

class GameTest < ActiveSupport::TestCase
  test "is invalid without date" do
    game = Game.new(court: courts(:one), user: users(:one), date: nil)

    assert_not game.valid?
    assert_includes game.errors[:date], "must be present"
  end

  test "prebooking_enabled requires recurring game" do
    game = Game.new(court: courts(:one), user: users(:one), date: Date.current, recurring: false, prebooking_enabled: true)

    assert_not game.valid?
    assert_includes game.errors[:prebooking_enabled], "can be enabled only for repeating (weekly) games"
  end

  test "next_date for recurring game moves to nearest upcoming occurrence" do
    game = Game.new(court: courts(:one), user: users(:one), date: Date.current - 14.days, recurring: true)

    assert game.next_date >= Date.current
    assert_equal 0, ((game.next_date - game.date) % 7)
  end

  test "prebooking_required_players uses players_count with fallback" do
    game = games(:one)

    game.players_count = 6
    assert_equal 6, game.prebooking_required_players

    game.players_count = 0
    assert_equal 4, game.prebooking_required_players
  end
end
