require "test_helper"

class CourtSuggestionRejectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email: "suggestion-rejection-owner@example.com")
    @author = User.create!(email: "suggestion-rejection-author@example.com")
    @admin = User.create!(email: "suggestion-rejection-admin@example.com", admin: true)
    @court = Court.create!(name: "Original", user: @owner, moderation_status: "approved", approved_at: Time.current)
    @suggestion = @court.court_suggestions.create!(user: @author, payload: { "name" => "Unused" })
  end

  teardown do
    @court&.destroy
    @admin&.destroy
    @author&.destroy
    @owner&.destroy
  end

  test "admin rejects without changing court" do
    sign_in_as(@admin)

    post court_suggestion_rejection_url(@suggestion)

    assert_redirected_to court_suggestion_path(@suggestion)
    assert_equal "Original", @court.reload.name
    assert_equal "rejected", @suggestion.reload.status
    assert_equal @admin, @suggestion.reviewed_by
  end

  test "non-admin cannot reject suggestion" do
    sign_in_as(@owner)

    post court_suggestion_rejection_url(@suggestion)

    assert_response :forbidden
    assert_equal "pending", @suggestion.reload.status
  end

  private

  def sign_in_as(user)
    post session_url, params: { email: user.email }
  end
end
