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

  test "guest is valid without user" do
    participation = Participation.new(game: games(:one), guest_name: "Alex Guest", status: "approved")

    assert participation.valid?
    assert participation.guest?
    assert_equal "Alex Guest", participation.display_name
  end

  test "registered participation cannot have guest name" do
    participation = Participation.new(user: users(:one), game: games(:two), guest_name: "Alex Guest")

    assert_not participation.valid?
    assert_includes participation.errors[:guest_name], "must be blank"
  end

  test "registered participation requires existing user" do
    participation = Participation.new(user_id: 987_654_321, game: games(:two), status: "approved")

    assert_not participation.valid?
    assert_includes participation.errors[:user], "can't be blank"
  end

  test "guest name is unique per game case-insensitively" do
    Participation.create!(game: games(:one), guest_name: "Alex Guest", status: "approved")
    duplicate = Participation.new(game: games(:one), guest_name: "alex guest", status: "approved")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:guest_name], "has already been taken"
  end

  test "guest name is limited to 50 characters" do
    participation = Participation.new(game: games(:one), guest_name: "a" * 51, status: "approved")

    assert_not participation.valid?
    assert_includes participation.errors[:guest_name], "is too long (maximum is 50 characters)"
  end
end
