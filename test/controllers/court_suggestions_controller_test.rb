require "test_helper"

class CourtSuggestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email: "court-suggestion-owner@example.com")
    @author = User.create!(email: "court-suggestion-author@example.com", name: "Author")
    @court = Court.create!(name: "Published Court", sport: "Tennis", user: @owner, moderation_status: "approved", approved_at: Time.current)
  end

  teardown do
    @court&.destroy
    @author&.destroy
    @owner&.destroy
  end

  test "guest must sign in to suggest a correction" do
    get new_court_correction_url(@court)

    assert_redirected_to new_session_path
  end

  test "non-owner sees prefilled suggestion form" do
    sign_in_as(@author)

    get new_court_correction_url(@court)

    assert_response :success
    assert_select "input[name='court_suggestion[name]'][value='Published Court']"
    assert_select "textarea[name='court_suggestion[comment]']", count: 0
  end

  test "owner is sent to the normal edit form" do
    sign_in_as(@owner)

    get new_court_correction_url(@court)

    assert_redirected_to edit_court_path(@court)
  end

  test "create stores only changed fields and notifies admin with a link" do
    sign_in_as(@author)
    notified = nil

    stub_singleton(Telegram::AdminNotifier, :notify_court_suggestion, ->(*args, **kwargs) { notified = [ args, kwargs ] }) do
      post court_corrections_url(@court), params: {
        court_suggestion: { name: @court.name, sport: "Padel", comment: "The lines were changed." }
      }
    end

    suggestion = @court.court_suggestions.find_by!(user: @author)
    assert_equal({ "sport" => "Padel" }, suggestion.payload)
    assert_nil suggestion.comment
    assert_equal @court.name, @court.reload.name
    assert_redirected_to @court
    assert_equal suggestion, notified.first.first
  end

  test "suggestion without a single changed field is rejected" do
    sign_in_as(@author)

    post court_corrections_url(@court), params: {
      court_suggestion: { name: @court.name, sport: @court.sport, comment: "Opening hours are wrong." }
    }

    assert_response :unprocessable_entity
    assert_nil @court.court_suggestions.find_by(user: @author)
  end

  test "second pending suggestion is rejected" do
    @court.court_suggestions.create!(user: @author, payload: { "sport" => "Padel" })
    sign_in_as(@author)

    post court_corrections_url(@court), params: {
      court_suggestion: { name: "Another name" }
    }

    assert_response :unprocessable_entity
    assert_equal 1, @court.court_suggestions.pending.where(user: @author).count
  end

  test "court page shows suggestion call to action only to non-manager" do
    sign_in_as(@author)
    get court_url(@court)
    assert_select "a[href='#{new_court_correction_path(@court)}']"

    sign_in_as(@owner)
    get court_url(@court)
    assert_select "a[href='#{new_court_correction_path(@court)}']", count: 0
  end

  test "admin can list and view suggestions" do
    suggestion = @court.court_suggestions.create!(user: @author, payload: { "sport" => "Padel" })
    @author.update_column(:admin, true)
    sign_in_as(@author)

    get court_suggestions_url
    assert_response :success
    assert_select "a[href='#{court_suggestion_path(suggestion)}']"

    get court_suggestion_url(suggestion)
    assert_response :success
    assert_includes response.body, "Padel"
  end

  test "non-admin cannot list or view suggestions" do
    suggestion = @court.court_suggestions.create!(user: @author, payload: { "sport" => "Padel" })
    sign_in_as(@owner)

    get court_suggestions_url
    assert_response :forbidden

    get court_suggestion_url(suggestion)
    assert_response :forbidden
  end

  private

  def sign_in_as(user)
    post session_url, params: { email: user.email }
  end
end
