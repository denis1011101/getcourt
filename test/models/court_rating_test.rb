require "test_helper"

class CourtRatingTest < ActiveSupport::TestCase
  setup do
    @court = Court.create!(name: "Rated Court", moderation_status: "approved", approved_at: Time.current)
    @user = User.create!(email: "court-rating-one@example.com")
    @other = User.create!(email: "court-rating-two@example.com")
  end

  teardown do
    @court&.destroy
    @user&.destroy
    @other&.destroy
  end

  test "rating outside 1..5 is rejected" do
    rating = @court.ratings.build(user: @user, value: 6)

    assert_not rating.valid?
    assert_includes rating.errors.attribute_names, :value
  end

  test "second rating from the same person overwrites the first" do
    @court.rate_by!(@user, 5)
    @court.rate_by!(@user, 2)

    assert_equal 1, @court.reload.ratings_count
    assert_equal 2, @court.rating_by(@user).value
  end

  test "average and count follow added and removed ratings" do
    @court.rate_by!(@user, 5)
    @court.rate_by!(@other, 2)

    assert_equal 2, @court.reload.ratings_count
    assert_in_delta 3.5, @court.ratings_average.to_f, 0.001

    @court.rating_by(@other).destroy

    assert_equal 1, @court.reload.ratings_count
    assert_in_delta 5.0, @court.ratings_average.to_f, 0.001
  end

  test "rating an approved court leaves it published" do
    @court.rate_by!(@user, 4)

    assert_predicate @court.reload, :approved?
  end
end
