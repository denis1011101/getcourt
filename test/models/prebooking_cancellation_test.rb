require "test_helper"

class PrebookingCancellationTest < ActiveSupport::TestCase
  test "is invalid without date" do
    cancellation = PrebookingCancellation.new(game: games(:one), user: users(:one), date: nil)

    assert_not cancellation.valid?
    assert_includes cancellation.errors[:date], "can't be blank"
  end

  test "enforces unique cancellation per game and date" do
    date = Date.current
    PrebookingCancellation.create!(game: games(:one), user: users(:one), date: date)

    duplicate = PrebookingCancellation.new(game: games(:one), user: users(:two), date: date)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:game_id], "has already been taken"
  end
end
