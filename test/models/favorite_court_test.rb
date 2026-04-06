require "test_helper"

class FavoriteCourtTest < ActiveSupport::TestCase
  test "is invalid when the same court is favorited twice by one user" do
    user = User.create!(email: "favorite_court_#{SecureRandom.hex(4)}@example.com", name: "User")
    court = Court.create!(name: "Center Court")
    FavoriteCourt.create!(user: user, court: court)

    duplicate = FavoriteCourt.new(user: user, court: court)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:court_id], "has already been taken"
  ensure
    duplicate&.destroy
    user&.destroy
    court&.destroy
  end

  test "links user and court associations" do
    user = User.create!(email: "favorite_court_assoc_#{SecureRandom.hex(4)}@example.com", name: "User")
    court = Court.create!(name: "Court A")
    favorite = FavoriteCourt.create!(user: user, court: court)

    assert_equal user, favorite.user
    assert_equal court, favorite.court
    assert_includes user.favorite_courts, court
    assert_includes court.fans, user
  ensure
    favorite&.destroy
    user&.destroy
    court&.destroy
  end
end
