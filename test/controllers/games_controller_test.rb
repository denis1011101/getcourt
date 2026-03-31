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

  test "new form shows urgent player search option" do
    post session_url, params: { email: "games_form_user@example.com" }

    get new_game_url

    assert_response :success
    assert_includes response.body, "Urgent player search"
  end

  test "new form includes hidden prebooking field" do
    post session_url, params: { email: "games_form_hidden_prebooking@example.com" }

    get new_game_url

    assert_response :success
    assert_select 'input[type="hidden"][name="game[prebooking_enabled]"][value="0"]'
  end

  test "prebooking fragment includes hidden prebooking field when recurring is disabled" do
    post session_url, params: { email: "games_fragment_hidden_prebooking@example.com" }

    get prebooking_fragment_games_url, params: { recurring: "0" }

    assert_response :success
    assert_select 'input[type="hidden"][name="game[prebooking_enabled]"][value="0"]'
  end

  # ---- pagination ---------------------------------------------------------

  test "index assigns @pagy" do
    get root_url

    assert_not_nil assigns(:pagy)
  end

  test "index shows at most 12 games per page" do
    # 2 fixture games + 11 new = 13 total → page 1 must have ≤ 12
    11.times { |i| Game.create!(court: courts(:one), user: users(:one), date: Date.current + (i + 3).days, time: "10:00") }

    get root_url

    assert_response :success
    assert assigns(:games).size <= 12
  end

  test "index page 2 returns overflow games" do
    11.times { |i| Game.create!(court: courts(:one), user: users(:one), date: Date.current + (i + 3).days, time: "10:00") }

    get root_url, params: { page: 2 }

    assert_response :success
    assert assigns(:games).size >= 1
  end

  test "index with_spots filter still paginates" do
    get root_url, params: { with_spots: "1" }

    assert_response :success
    assert_not_nil assigns(:pagy)
  end

  test "index city filter still paginates" do
    Court.create!(name: "London Court", moderation_status: "approved", city_name: "London")

    get root_url, params: { city: "London" }

    assert_response :success
    assert_not_nil assigns(:pagy)
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

  test "owner can toggle urgent player search on and off" do
    post session_url, params: { email: "owner_urgent_toggle@example.com" }
    owner = User.find_by!(email: "owner_urgent_toggle@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.current + 2.days, time: "10:00")

    assert_not game.urgent_player_search?

    post toggle_urgent_player_search_game_url(game)
    assert_redirected_to game_path(game)
    assert game.reload.urgent_player_search?

    post toggle_urgent_player_search_game_url(game)
    assert_redirected_to game_path(game)
    assert_not game.reload.urgent_player_search?
  end

  test "non-owner cannot toggle urgent player search" do
    owner = User.create!(email: "owner_forbidden_urgent@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.current + 2.days, time: "10:00")

    post session_url, params: { email: "stranger_forbidden_urgent@example.com" }
    post toggle_urgent_player_search_game_url(game)

    assert_response :forbidden
    assert_not game.reload.urgent_player_search?
  end
end
