require "test_helper"

class Api::V1::GamesControllerTest < ActionDispatch::IntegrationTest
  test "lists upcoming games on approved courts" do
    get api_v1_games_url

    assert_response :success
    body = JSON.parse(response.body)
    ids = body["games"].map { |game| game["id"] }

    assert_includes ids, games(:feed_upcoming).id
    # Корт на модерации наружу не отдаём.
    assert_not_includes ids, games(:one).id
  end

  test "does not leak anything about the people in the game" do
    player = User.create!(
      name: "Api Leak Probe",
      email: "api-leak-probe@example.com",
      telegram_chat_id: 987_654,
      telegram_username: "apileakprobe"
    )
    games(:feed_upcoming).participations.create!(user: player)

    get api_v1_games_url
    body = response.body

    assert_includes JSON.parse(body)["games"].first["players"].keys, "taken"
    assert_not_includes body, player.email
    assert_not_includes body, player.name
    assert_not_includes body, player.telegram_username
    assert_not_includes body, player.telegram_chat_id.to_s
  end

  test "filters by sport, city and free spots" do
    get api_v1_games_url, params: { sport: "nothing-like-this" }
    assert_empty JSON.parse(response.body)["games"]

    get api_v1_games_url, params: { urgent: "true" }
    ids = JSON.parse(response.body)["games"].map { |game| game["id"] }
    assert_equal [ games(:feed_urgent).id ], ids

    game = games(:feed_upcoming)
    game.update!(players_count: 1)
    game.participations.create!(user: users(:two))

    get api_v1_games_url, params: { with_spots: "true" }
    ids = JSON.parse(response.body)["games"].map { |game| game["id"] }
    assert_not_includes ids, game.id
  end

  test "caps the number of games it will hand out" do
    get api_v1_games_url, params: { limit: 10_000 }

    assert_response :success
    assert_operator JSON.parse(response.body)["games"].size, :<=, Games::Search::MAX_LIMIT
  end

  test "serves a single game and 404s on a court still in moderation" do
    get api_v1_game_url(games(:feed_upcoming))

    assert_response :success
    assert_equal games(:feed_upcoming).id, JSON.parse(response.body)["game"]["id"]

    get api_v1_game_url(games(:one))
    assert_response :not_found
  end
end
