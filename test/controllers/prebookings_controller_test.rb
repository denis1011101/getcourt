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
  test "more lazily creates slots for expanded horizon" do
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      date: Date.current,
      recurring: true,
      prebooking_enabled: true,
      players_count: 2
    )

    users(:two).update!(email: "expanded-prebooking@example.com")
    post session_url, params: { email: users(:two).email }

    assert_difference -> { game.prebookings.count }, 12 do
      get more_game_prebookings_url(game, horizon: 6)
    end

    assert_response :success
    assert_select "turbo-frame#prebookings-#{game.id}"
  end
end
