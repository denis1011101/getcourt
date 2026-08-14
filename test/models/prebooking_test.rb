require "test_helper"

class PrebookingTest < ActiveSupport::TestCase
  test "user can only book one slot per game and date" do
    game = games(:one)
    date = Date.current + 6.weeks
    game.prebookings.create!(date: date, slot_index: 1, user: users(:one))
    duplicate = game.prebookings.build(date: date, slot_index: 2, user: users(:one))

    assert_not duplicate.valid?
    assert duplicate.errors.added?(:user_id, "can have only one booking for this game on the same date")
  end
end
