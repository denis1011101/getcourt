require "test_helper"

class GamesControllerTest < ActionDispatch::IntegrationTest
  test "index is available without authentication" do
    get root_url

    assert_response :success
  end

  test "create requires authentication" do
    assert_no_difference("Game.count") do
      post games_url, params: { game: { court_id: courts(:one).id, date: Date.current + 1.day, time: "18:00" } }
    end

    assert_redirected_to new_session_path
  end

  test "authenticated user can create game" do
    post session_url, params: { email: "games_test_user@example.com" }

    assert_difference("Game.count", 1) do
      post games_url, params: {
        game: {
          court_id: courts(:one).id,
          date: Date.current + 1.day,
          time: "18:00",
          recurring: "0",
          players_count: "4"
        }
      }
    end

    assert_redirected_to game_path(Game.order(:id).last)
  end

  test "owner can update own game" do
    post session_url, params: { email: "owner_update@example.com" }
    owner = User.find_by!(email: "owner_update@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.current + 2.days, time: "10:00")

    patch game_url(game), params: {
      game: {
        court_id: game.court_id,
        date: game.date,
        time: "10:00",
        players_count: "6"
      }
    }

    assert_redirected_to game_path(game)
    assert_equal 6, game.reload.players_count
  end
end
