require "test_helper"

class CourtSuggestionApprovalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email: "suggestion-approval-owner@example.com")
    @author = User.create!(email: "suggestion-approval-author@example.com")
    @admin = User.create!(email: "suggestion-approval-admin@example.com", admin: true)
    @court = Court.create!(name: "Original", sport: "Tennis", user: @owner, moderation_status: "approved", approved_at: Time.current)
    @suggestion = @court.court_suggestions.create!(user: @author, payload: { "name" => "Corrected" })
  end

  teardown do
    @court&.destroy
    @admin&.destroy
    @author&.destroy
    @owner&.destroy
  end

  test "admin applies suggestion without unpublishing court" do
    sign_in_as(@admin)

    post court_suggestion_approval_url(@suggestion)

    assert_redirected_to court_suggestion_path(@suggestion)
    assert_equal "Corrected", @court.reload.name
    assert_equal "approved", @court.moderation_status
    assert_equal "approved", @suggestion.reload.status
    assert_equal @admin, @suggestion.reviewed_by
  end

  test "non-admin cannot apply suggestion" do
    sign_in_as(@owner)

    post court_suggestion_approval_url(@suggestion)

    assert_response :forbidden
    assert_equal "Original", @court.reload.name
    assert_equal "pending", @suggestion.reload.status
  end

  test "invalid court update stays pending" do
    @suggestion.update_column(:payload, { "name" => "" })
    sign_in_as(@admin)

    post court_suggestion_approval_url(@suggestion)

    assert_redirected_to court_suggestion_path(@suggestion)
    assert_equal "Original", @court.reload.name
    assert_equal "pending", @suggestion.reload.status
  end

  private

  def sign_in_as(user)
    post session_url, params: { email: user.email }
  end
end
