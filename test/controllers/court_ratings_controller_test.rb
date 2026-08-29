require "test_helper"

class CourtRatingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @court = Court.create!(name: "Ratable Court", moderation_status: "approved", approved_at: Time.current)
    @verified = User.create!(email: "rating-verified@example.com", email_verified_at: Time.current)
    @unverified = User.create!(email: "rating-unverified@example.com")
    @telegram_user = User.create!(email: "rating-telegram@example.com", telegram_chat_id: 987_654_321)
  end

  teardown do
    @court&.destroy
    @verified&.destroy
    @unverified&.destroy
    @telegram_user&.destroy
  end

  test "guest is sent to sign in" do
    post court_rating_url(@court), params: { value: 4 }

    assert_redirected_to new_session_path
    assert_equal 0, @court.reload.ratings_count
  end

  test "signed in but unverified person is sent to verification" do
    sign_in_as(@unverified)

    post court_rating_url(@court), params: { value: 4 }

    assert_redirected_to new_account_verification_path
    assert_equal 0, @court.reload.ratings_count
  end

  test "verified person rates the court" do
    sign_in_as(@verified)

    post court_rating_url(@court), params: { value: 4 }

    assert_redirected_to court_path(@court, anchor: "rating")
    assert_equal 1, @court.reload.ratings_count
    assert_in_delta 4.0, @court.ratings_average.to_f, 0.001
  end

  test "connected telegram counts as a confirmed account" do
    sign_in_as(@telegram_user)

    post court_rating_url(@court), params: { value: 3 }

    assert_equal 3, @court.rating_by(@telegram_user).value
  end

  test "person can remove their own rating" do
    sign_in_as(@verified)
    post court_rating_url(@court), params: { value: 5 }

    delete court_rating_url(@court)

    assert_redirected_to court_path(@court, anchor: "rating")
    assert_equal 0, @court.reload.ratings_count
  end

  test "invalid value keeps the stored rating" do
    sign_in_as(@verified)
    post court_rating_url(@court), params: { value: 4 }

    post court_rating_url(@court), params: { value: 9 }

    assert_equal 4, @court.rating_by(@verified).value
    assert_equal 4.0, @court.reload.ratings_average.to_f
  end

  test "court under moderation cannot be rated" do
    pending_court = Court.create!(name: "Pending Court")
    sign_in_as(@verified)

    post court_rating_url(pending_court), params: { value: 5 }

    assert_response :not_found
    assert_equal 0, pending_court.reload.ratings_count
  ensure
    pending_court&.destroy
  end

  test "court page shows the average" do
    rate(@verified, 5)
    rate(@telegram_user, 4)

    get court_url(@court)

    assert_response :success
    assert_select "#rating", text: /4[.,]5/
  end

  private

  def rate(user, value)
    rating = @court.rating_from(user)
    rating.value = value
    rating.save!
  end

  def sign_in_as(user)
    post session_url, params: { email: user.email }
  end
end
