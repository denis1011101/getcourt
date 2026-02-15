require "test_helper"

class TournamentsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get tournaments_url
    assert_response :success
  end

  test "should get options" do
    get options_tournaments_url, params: { tournament_id: tournaments(:one).id }
    assert_response :success
  end

  test "should get show" do
    get tournament_url(tournaments(:one))
    assert_response :success
  end

  test "should redirect new when not authenticated" do
    get new_tournament_url
    assert_redirected_to new_session_path
  end
end
