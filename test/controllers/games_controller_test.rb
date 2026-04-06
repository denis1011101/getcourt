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
    assert_select "#game_prebooking_enabled", 1
  end

  test "prebooking fragment includes hidden prebooking field when recurring is disabled" do
    post session_url, params: { email: "games_fragment_hidden_prebooking@example.com" }

    get prebooking_fragment_games_url, params: { recurring: "0" }

    assert_response :success
    assert_select 'input[type="hidden"][name="game[prebooking_enabled]"][value="0"]'
    assert_select "#game_prebooking_enabled", 0
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

  test "index country filter shows full country name in summary and filters games" do
    city_ids = []
    city_ids << City.create!(name: "Kitzbuhel", country_code: "AT", population: 8_000).id
    city_ids << City.create!(name: "Yekaterinburg", country_code: "RU", population: 1_500_000).id
    austrian_court = Court.create!(name: "Kitz Court", city_name: "Kitzbuhel", moderation_status: "approved", approved_at: Time.current)
    russian_court = Court.create!(name: "Ekb Court", city_name: "Yekaterinburg", moderation_status: "approved", approved_at: Time.current)
    austrian_game = Game.create!(court: austrian_court, user: users(:one), date: Date.current + 1.day, time: "10:00")
    russian_game = Game.create!(court: russian_court, user: users(:one), date: Date.current + 2.days, time: "11:00")

    get games_browse_url(country_slug: "austria")

    assert_response :success
    assert_includes assigns(:games), austrian_game
    assert_not_includes assigns(:games), russian_game
    assert_select "[data-testid='results-summary']", text: /Austria/
  ensure
    austrian_game&.destroy
    russian_game&.destroy
    austrian_court&.destroy
    russian_court&.destroy
    City.where(id: city_ids).delete_all if city_ids
  end

  test "country to city mapping prefers the most populous matching city" do
    city_ids = []
    city_ids << City.create!(name: "Minsk", country_code: "BY", population: 1_742_124).id
    city_ids << City.create!(name: "Minsk", country_code: "RU", population: 0).id
    city_ids << City.create!(name: "Yekaterinburg", country_code: "RU", population: 1_500_000).id
    minsk_court = Court.create!(name: "Minsk Court", city_name: "Minsk", moderation_status: "approved", approved_at: Time.current)
    ekb_court = Court.create!(name: "Ekb Court", city_name: "Yekaterinburg", moderation_status: "approved", approved_at: Time.current)
    minsk_game = Game.create!(court: minsk_court, user: users(:one), date: Date.current + 1.day, time: "10:00")
    ekb_game = Game.create!(court: ekb_court, user: users(:one), date: Date.current + 2.days, time: "11:00")

    get games_browse_url(country_slug: "russia")

    assert_response :success
    assert_not_includes assigns(:cities), "Minsk"
    assert_includes assigns(:games), ekb_game
    assert_not_includes assigns(:games), minsk_game
  ensure
    minsk_game&.destroy
    ekb_game&.destroy
    minsk_court&.destroy
    ekb_court&.destroy
    City.where(id: city_ids).delete_all if city_ids
  end

  test "query location filters redirect to pretty games url without commit parameter" do
    city_ids = []
    city_ids << City.create!(name: "Yekaterinburg", country_code: "RU", population: 1_500_000).id
    court = Court.create!(name: "Ekb Court", city_name: "Yekaterinburg", moderation_status: "approved", approved_at: Time.current)
    Game.create!(court: court, user: users(:one), date: Date.current + 1.day, time: "10:00")

    get root_url, params: { country: "RU", city: "Yekaterinburg", commit: "Search" }

    assert_redirected_to games_browse_path(country_slug: "russia", city_slug: "yekaterinburg")
  ensure
    Game.where(court_id: court&.id).delete_all
    court&.destroy
    City.where(id: city_ids).delete_all if city_ids
  end

  test "pretty games url renders canonical title and description for location" do
    city_ids = []
    city_ids << City.create!(name: "Yekaterinburg", country_code: "RU", population: 1_500_000).id
    court = Court.create!(name: "Ekb Court", city_name: "Yekaterinburg", moderation_status: "approved", approved_at: Time.current)
    Game.create!(court: court, user: users(:one), date: Date.current + 1.day, time: "10:00")

    get games_browse_url(country_slug: "russia", city_slug: "yekaterinburg")

    assert_response :success
    assert_select "title", text: "Tennis games in Yekaterinburg, Russia — GetCourt"
    assert_select "meta[name='description'][content='Find tennis, padel, table tennis and squash games in Yekaterinburg, Russia. Join a match or create your own on GetCourt.']", count: 1
    assert_select "link[rel='canonical'][href='https://getcourt.co/games/russia/yekaterinburg']", count: 1
  ensure
    Game.where(court_id: court&.id).delete_all
    court&.destroy
    City.where(id: city_ids).delete_all if city_ids
  end

  test "index renders location filters stimulus payload for client-side city updates" do
    city_ids = []
    city_ids << City.create!(name: "Kitzbuhel", country_code: "AT", population: 8_000).id
    city_ids << City.create!(name: "Yekaterinburg", country_code: "RU", population: 1_500_000).id
    Court.create!(name: "Kitz Court", city_name: "Kitzbuhel", moderation_status: "approved", approved_at: Time.current)
    Court.create!(name: "Ekb Court", city_name: "Yekaterinburg", moderation_status: "approved", approved_at: Time.current)

    get root_url

    assert_response :success
    assert_includes response.body, 'data-controller="location-filters"'
    assert_includes response.body, "Kitzbuhel"
    assert_includes response.body, "Yekaterinburg"
  ensure
    Court.where(name: [ "Kitz Court", "Ekb Court" ]).delete_all
    City.where(id: city_ids).delete_all if city_ids
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
