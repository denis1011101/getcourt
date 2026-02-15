require "test_helper"

class ParticipationTest < ActiveSupport::TestCase
  test "is invalid when same user joins same game twice" do
    duplicate = Participation.new(user: participations(:one).user, game: participations(:one).game)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already joined this game"
  end

  test "requires status" do
    participation = Participation.new(user: users(:one), game: games(:two), status: nil)

    assert_not participation.valid?
    assert_includes participation.errors[:status], "can't be blank"
  end
end
