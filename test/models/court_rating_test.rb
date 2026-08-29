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
    rate(@user, 5)
    rate(@user, 2)

    assert_equal 1, @court.reload.ratings_count
    assert_equal 2, @court.rating_by(@user).value
  end

  test "average and count follow added and removed ratings" do
    rate(@user, 5)
    rate(@other, 2)

    assert_equal 2, @court.reload.ratings_count
    assert_in_delta 3.5, @court.ratings_average.to_f, 0.001

    @court.rating_by(@other).destroy

    assert_equal 1, @court.reload.ratings_count
    assert_in_delta 5.0, @court.ratings_average.to_f, 0.001
  end

  test "rating an approved court leaves it published" do
    rate(@user, 4)

    assert_predicate @court.reload, :approved?
  end

  test "rejected update keeps the stored value and reports the failure" do
    rate(@user, 4)

    rating = @court.rating_from(@user)
    rating.value = 9

    assert_not rating.save
    assert_equal 4, @court.rating_by(@user).value
  end

  private

  def rate(user, value)
    rating = @court.rating_from(user)
    rating.value = value
    rating.save!
    rating
  end
end
