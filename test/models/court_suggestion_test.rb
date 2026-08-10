require "test_helper"

class CourtSuggestionTest < ActiveSupport::TestCase
  test "requires a changed field or comment" do
    suggestion = CourtSuggestion.new(court: courts(:one), user: users(:one), payload: {})

    assert_not suggestion.valid?
  end

  test "allows comment-only suggestion" do
    suggestion = CourtSuggestion.new(court: courts(:one), user: users(:one), payload: {}, comment: "The opening hours are outdated")

    assert suggestion.valid?
  end

  test "allows only one pending suggestion per user and court" do
    suggestion = CourtSuggestion.new(court: courts(:one), user: users(:two), payload: { "free" => true })

    assert_not suggestion.valid?
    assert suggestion.errors[:user_id].present?
  end

  test "apply changes only payload fields and records reviewer" do
    court = courts(:one)
    court.update!(name: "Original", sport: "Tennis", moderation_status: "approved")
    admin = users(:one)
    admin.update_column(:admin, true)
    suggestion = CourtSuggestion.create!(court: court, user: users(:one), payload: { "name" => "Corrected" })

    assert suggestion.apply_by!(admin)
    assert_equal "Corrected", court.reload.name
    assert_equal "Tennis", court.sport
    assert_equal "approved", court.moderation_status
    assert_equal "approved", suggestion.reload.status
    assert_equal admin, suggestion.reviewed_by
    assert suggestion.reviewed_at.present?
  end

  test "invalid court change leaves suggestion pending" do
    admin = users(:one)
    admin.update_column(:admin, true)
    suggestion = CourtSuggestion.create!(court: courts(:one), user: users(:one), payload: { "name" => "" })

    assert_not suggestion.apply_by!(admin)
    assert_equal "pending", suggestion.reload.status
    assert_not_equal "", suggestion.court.reload.name
  end

  test "reject records reviewer without changing court" do
    admin = users(:one)
    admin.update_column(:admin, true)
    suggestion = CourtSuggestion.create!(court: courts(:two), user: users(:two), payload: { "name" => "Unused" })
    original_name = suggestion.court.name

    assert suggestion.reject_by!(admin)
    assert_equal original_name, suggestion.court.reload.name
    assert_equal "rejected", suggestion.reload.status
    assert_equal admin, suggestion.reviewed_by
  end
end
