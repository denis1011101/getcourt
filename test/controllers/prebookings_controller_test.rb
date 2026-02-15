require "test_helper"

class PrebookingsControllerTest < ActionDispatch::IntegrationTest
  test "should redirect book when not authenticated" do
    post book_game_prebooking_url(games(:one), prebookings(:one))
    assert_redirected_to new_session_path
  end

  test "should redirect cancel when not authenticated" do
    post cancel_game_prebooking_url(games(:one), prebookings(:one))
    assert_redirected_to new_session_path
  end
end
