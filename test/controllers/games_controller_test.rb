require "test_helper"

class GamesControllerTest < ActionDispatch::IntegrationTest
  test "index is available without authentication" do
    get root_url

    assert_response :success
  end

  test "index loads featured match so the wallchart banner links to its event" do
    travel_to ApplicationHelper::WALLCHART_BANNER_UNTIL - 1.day do
      featured_match = FeaturedMatch.create!(
        tournament_label: "Roland Garros Final",
        player_left_name: "M. Andreeva",
        player_right_name: "M. Kostyuk",
        starts_at: 1.day.from_now,
        active: true
      )

      get root_url

      assert_response :success
      assert_equal featured_match, @controller.instance_variable_get(:@featured_match)
      assert_includes @response.body, event_path(featured_match)
      assert_not_includes @response.body, "featured-match-banner"
      assert_not_includes @response.body, "wallchart26.com"
    end
  end

  test "wallchart banner opts out of turbo prefetch to avoid inflating event views" do
    travel_to ApplicationHelper::WALLCHART_BANNER_UNTIL - 1.day do
      FeaturedMatch.create!(
        tournament_label: "Roland Garros Final",
        player_left_name: "M. Andreeva",
        player_right_name: "M. Kostyuk",
        starts_at: 1.day.from_now,
        active: true
      )

      get root_url

      assert_response :success
      assert_select "a[data-turbo-prefetch='false']"
    end
  end

  test "index loads featured match on the exact wallchart cutoff date" do
    travel_to ApplicationHelper::WALLCHART_BANNER_UNTIL do
      featured_match = FeaturedMatch.create!(
        tournament_label: "Roland Garros Final",
        player_left_name: "M. Andreeva",
        player_right_name: "M. Kostyuk",
        starts_at: 1.day.from_now,
        active: true
      )

      get root_url

      assert_response :success
      assert_equal featured_match, @controller.instance_variable_get(:@featured_match)
      assert_includes @response.body, "featured-match-banner"
      assert_not_includes @response.body, "wallchart26.com"
      assert_select "a[data-turbo-prefetch='false']"
    end
  end

  test "show renders win chances once two players carry a rating" do
    owner = User.create!(email: "chances_owner@example.com", name: "Chances Owner")
    rival = User.create!(email: "chances_rival@example.com", name: "Chances Rival")
    owner.create_player_statistic!(singles_rating: 1600.0)
    rival.create_player_statistic!(singles_rating: 1400.0)

    game = Game.create!(court: courts(:one), user: owner, date: Date.yesterday, time: "10:00")
    [ owner, rival ].each { |user| Participation.create!(game: game, user: user, status: "approved") }

    get game_url(game)

    assert_response :success
    assert_select "[data-testid=?]", "game-win-chances"
    assert_includes @response.body, "Chances Owner"
  end

  test "show explains the win chances when nobody has a rating" do
    owner = User.create!(email: "no_chances_owner@example.com", name: "No Chances Owner")
    rival = User.create!(email: "no_chances_rival@example.com", name: "No Chances Rival")

    game = Game.create!(court: courts(:one), user: owner, date: Date.yesterday, time: "10:00")
    [ owner, rival ].each { |user| Participation.create!(game: game, user: user, status: "approved") }

    get game_url(game)

    assert_response :success
    assert_select "[data-testid=?]", "game-win-chances"
    assert_select "[data-testid=?]", "game-win-chances-pending" do |elements|
      assert_includes elements.first.text, I18n.t("games.show.win_chances.pending.not_enough_ratings")
    end
    assert_includes @response.body, I18n.t("games.show.win_chances.preview.splits")
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

  test "create rejects surface or environment not offered by the court" do
    post session_url, params: { email: "games_surface_user@example.com" }
    court = Court.create!(name: "Clay outdoor", surfaces: %w[clay], outdoor: true, indoor: false)

    assert_no_difference("Game.count") do
      post games_url, params: {
        game: {
          court_id: court.id,
          date: Date.current + 1.day,
          time: "18:00",
          surface: "hard",
          environment: "indoor"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create accepts surface and environment offered by the court" do
    post session_url, params: { email: "games_surface_ok_user@example.com" }
    court = Court.create!(name: "Clay outdoor ok", surfaces: %w[clay], outdoor: true, indoor: false)

    assert_difference("Game.count", 1) do
      post games_url, params: {
        game: {
          court_id: court.id,
          date: Date.current + 1.day,
          time: "18:00",
          surface: "clay",
          environment: "outdoor"
        }
      }
    end

    game = Game.order(:id).last
    assert_equal "clay", game.surface
    assert_equal "outdoor", game.environment
  end

  test "new form shows players search option" do
    post session_url, params: { email: "games_form_user@example.com" }

    get new_game_url

    assert_response :success
    assert_includes response.body, "Players search"
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

  test "results summary shows total games count instead of current page size" do
    initial_count = Game.count
    11.times { |i| Game.create!(court: courts(:one), user: users(:one), date: Date.current + (i + 3).days, time: "10:00") }

    get root_url

    assert_response :success
    assert_select "[data-testid='results-summary']", text: /#{initial_count + 11} games available/
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

  test "index db path orders upcoming games before past games" do
    court = Court.create!(name: "Ordering Court", moderation_status: "approved", city_name: "Ordertown")
    past_game = Game.create!(court: court, user: users(:one), date: Date.current - 2.days, time: "10:00")
    future_game = Game.create!(court: court, user: users(:one), date: Date.current + 2.days, time: "10:00")
    recurring_game = Game.create!(court: court, user: users(:one), recurring: true, date: Date.current - 10.days, time: "09:00")

    get root_url

    assert_response :success
    game_ids = assigns(:games).map(&:id)
    assert_operator game_ids.index(future_game.id), :<, game_ids.index(past_game.id)
    assert_operator game_ids.index(recurring_game.id), :<, game_ids.index(past_game.id)
  ensure
    past_game&.destroy
    future_game&.destroy
    recurring_game&.destroy
    court&.destroy
  end

  test "index sorts local city games by proximity to user city coordinates" do
    city = City.create!(
      name: "Testville",
      country_code: "TV",
      latitude: 55.0,
      longitude: 37.0,
      population: 100_000
    )
    near_court = Court.create!(name: "Near Testville Court", moderation_status: "approved", city_name: "Testville", coordinates: "55.01,37.01")
    far_court = Court.create!(name: "Far Testville Court", moderation_status: "approved", city_name: "Testville", coordinates: "56.00,38.00")
    far_game = Game.create!(court: far_court, user: users(:one), date: Date.current + 1.day, time: "10:00")
    near_game = Game.create!(court: near_court, user: users(:one), date: Date.current + 1.day, time: "11:00")

    post session_url, params: { email: "testville_player@example.com" }
    User.find_by!(email: "testville_player@example.com").update_column(:city_name, "Testville")
    get root_url

    assert_response :success
    game_ids = assigns(:games).map(&:id)
    assert_operator game_ids.index(near_game.id), :<, game_ids.index(far_game.id)
  ensure
    far_game&.destroy
    near_game&.destroy
    far_court&.destroy
    near_court&.destroy
    city&.destroy
  end

  test "index city sort keeps local upcoming games before local past games" do
    city = City.create!(
      name: "Timeville",
      country_code: "TV",
      latitude: 55.0,
      longitude: 37.0,
      population: 100_000
    )
    court = Court.create!(name: "Timeville Court", moderation_status: "approved", city_name: "Timeville", coordinates: "55.00,37.00")
    past_game = Game.create!(court: court, user: users(:one), date: Date.current - 1.day, time: "10:00")
    future_game = Game.create!(court: court, user: users(:one), date: Date.current + 1.day, time: "10:00")

    post session_url, params: { email: "timeville_player@example.com" }
    User.find_by!(email: "timeville_player@example.com").update_column(:city_name, "Timeville")
    get root_url

    assert_response :success
    game_ids = assigns(:games).map(&:id)
    assert_operator game_ids.index(future_game.id), :<, game_ids.index(past_game.id)
  ensure
    past_game&.destroy
    future_game&.destroy
    court&.destroy
    city&.destroy
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

    get games_browse_url(country_slug: "russia", city_slug: "yekaterinburg", host: "ru.getcourt.co")

    assert_response :success
    assert_select "title", text: "Теннисные игры в Yekaterinburg, Russia — GetCourt"
    assert_select "meta[name='description'][content='Найдите игры в теннис, падел, настольный теннис и сквош в Yekaterinburg, Russia. Присоединяйтесь к матчу или создайте свой на GetCourt.']", count: 1
    assert_select "link[rel='canonical'][href='https://ru.getcourt.co/games/russia/yekaterinburg']", count: 1
    assert_select "link[rel='alternate'][hreflang='en'][href='https://getcourt.co/games/russia/yekaterinburg']", count: 1
    assert_select "link[rel='alternate'][hreflang='ru'][href='https://ru.getcourt.co/games/russia/yekaterinburg']", count: 1
    assert_select "link[rel='alternate'][hreflang='es'][href='https://es.getcourt.co/games/russia/yekaterinburg']", count: 1
    assert_select "link[rel='alternate'][hreflang='x-default'][href='https://getcourt.co/games/russia/yekaterinburg']", count: 1
    assert_select "meta[property='og:image'][content='https://ru.getcourt.co/og-image.png']", count: 1
  ensure
    Game.where(court_id: court&.id).delete_all
    court&.destroy
    City.where(id: city_ids).delete_all if city_ids
  end

  test "main english domain is canonical and has hreflang alternates" do
    get root_url(host: "getcourt.co")

    assert_response :success
    assert_select "link[rel='canonical'][href='https://getcourt.co/']", count: 1
    assert_select "link[rel='alternate'][hreflang='en'][href='https://getcourt.co/']", count: 1
    assert_select "link[rel='alternate'][hreflang='ru'][href='https://ru.getcourt.co/']", count: 1
    assert_select "link[rel='alternate'][hreflang='es'][href='https://es.getcourt.co/']", count: 1
    assert_select "link[rel='alternate'][hreflang='x-default'][href='https://getcourt.co/']", count: 1
  end

  test "en subdomain canonicalizes to main domain" do
    get root_url(host: "en.getcourt.co")

    assert_response :success
    assert_select "link[rel='canonical'][href='https://getcourt.co/']", count: 1
  end

  test "spanish locale subdomain is indexable" do
    get root_url(host: "es.getcourt.co")

    assert_response :success
    assert_select "html[lang='es']", count: 1
    assert_select "meta[name='robots'][content='index, follow']", count: 1
  end

  test "unsupported locale subdomain is noindex" do
    get root_url(host: "it.getcourt.co")

    assert_response :success
    assert_select "link[rel='canonical'][href='https://getcourt.co/']", count: 1
    assert_select "meta[name='robots'][content='noindex, follow']", count: 1
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

  test "index renders english country names for georgia and monaco in filters" do
    city_ids = []
    city_ids << City.create!(name: "Tbilisi", country_code: "GE", population: 1_100_000).id
    city_ids << City.create!(name: "Monaco", country_code: "MC", population: 38_000).id
    Court.create!(name: "Tbilisi Court", city_name: "Tbilisi", moderation_status: "approved", approved_at: Time.current)
    Court.create!(name: "Monte Carlo Court", city_name: "Monaco", moderation_status: "approved", approved_at: Time.current)

    get root_url

    assert_response :success
    assert_select "select[name='country'] option", text: "Georgia"
    assert_select "select[name='country'] option", text: "Monaco"
  ensure
    Court.where(name: [ "Tbilisi Court", "Monte Carlo Court" ]).delete_all
    City.where(id: city_ids).delete_all if city_ids
  end

  test "index prefers japan over haiti for koto in filters" do
    city_ids = []
    city_ids << City.create!(name: "Koto", country_code: "JP", population: 500_000).id
    city_ids << City.create!(name: "Koto", country_code: "HT", population: 600_000).id
    Court.create!(name: "Koto Court", city_name: "Koto", moderation_status: "approved", approved_at: Time.current)

    get root_url

    assert_response :success
    assert_select "select[name='country'] option", text: "Japan"
    assert_select "select[name='country'] option", text: "Haiti", count: 0
  ensure
    Court.where(name: "Koto Court").delete_all
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

  test "owner can save a comment and it is rendered escaped on the game page" do
    post session_url, params: { email: "comment_owner@example.com" }
    owner = User.find_by!(email: "comment_owner@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.current + 2.days, time: "10:00")

    patch game_url(game), params: {
      game: {
        court_id: game.court_id,
        date: game.date,
        time: "10:00",
        comment: "Balls are on me\n<b>entrance from the yard</b>"
      }
    }

    assert_redirected_to game_path(game)
    assert_equal "Balls are on me\n<b>entrance from the yard</b>", game.reload.comment

    get game_url(game)

    assert_response :success
    assert_select '[data-testid="game-comment"]', 1
    assert_includes @response.body, "&lt;b&gt;entrance from the yard&lt;/b&gt;"
    assert_not_includes @response.body, "<b>entrance from the yard</b>"
  end

  test "game form offers the comment field" do
    post session_url, params: { email: "comment_form_user@example.com" }

    get new_game_url

    assert_response :success
    assert_select "textarea[name='game[comment]'][maxlength='500']", 1
  end

  test "index card shows the comment as a single truncated line" do
    owner = User.create!(email: "comment_card_owner@example.com")
    Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.current + 2.days,
      time: "10:00",
      comment: "#{'a' * 200}\nsecond line"
    )

    get root_url

    assert_response :success
    assert_select '[data-testid="game-card-comment"]', 1 do |elements|
      text = elements.first.text.strip
      assert_operator text.length, :<=, 80
      assert_includes text, "..."
    end
  end

  test "owner can toggle players search on and off" do
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

  test "non-owner cannot toggle players search" do
    owner = User.create!(email: "owner_forbidden_urgent@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.current + 2.days, time: "10:00")

    post session_url, params: { email: "stranger_forbidden_urgent@example.com" }
    post toggle_urgent_player_search_game_url(game)

    assert_response :forbidden
    assert_not game.reload.urgent_player_search?
  end

  test "owner sees onboarding checklist with the correct actions" do
    owner = User.create!(email: "onboarding_owner@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.current + 2.days, time: "10:00", players_count: 4)
    post session_url, params: { email: owner.email }

    get game_url(game)

    assert_response :success
    assert_select '[data-testid="game-onboarding"]', 1
    assert_select '[data-testid="onboarding-join"] form[action=?][method="post"][data-turbo="false"]', game_participations_path(game)
    assert_select '[data-testid="onboarding-city"] a[href=?]', profile_account_path
    assert_select '[data-testid="onboarding-telegram"] a[href=?]', notifications_account_path
    assert_select '[data-testid="onboarding-player_search"] form[action=?][method="post"]', toggle_urgent_player_search_game_path(game)
  end

  test "player search onboarding item also offers inviting players by telegram username" do
    owner = User.create!(email: "onboarding_invite_owner@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.current + 2.days, time: "10:00", players_count: 4)
    post session_url, params: { email: owner.email }

    get game_url(game)

    assert_response :success
    assert_select '[data-testid="onboarding-player_search"] form[action=?][method="post"]', game_invitations_path(game)
    assert_select '[data-testid="onboarding-player_search"] input[name="usernames"]', 1
  end

  test "completed onboarding checklist is hidden" do
    owner = User.create!(
      email: "onboarding_complete@example.com",
      city_name: "Madrid",
      telegram_chat_id: 123_456
    )
    game = Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.current + 2.days,
      time: "10:00",
      players_count: 4,
      urgent_player_search: true
    )
    game.participations.create!(user: owner, status: "approved")
    post session_url, params: { email: owner.email }

    get game_url(game)

    assert_response :success
    assert_select '[data-testid="game-onboarding"]', 0
  end

  test "player search onboarding item is omitted for full and past games" do
    owner = User.create!(email: "onboarding_search_irrelevant@example.com")
    participant = User.create!(email: "onboarding_full_participant@example.com")
    full_game = Game.create!(court: courts(:one), user: owner, date: Date.current + 2.days, time: "10:00", players_count: 1)
    full_game.participations.create!(user: participant, status: "approved")
    past_game = Game.create!(court: courts(:one), user: owner, date: Date.current - 1.day, time: "10:00", players_count: 4)
    post session_url, params: { email: owner.email }

    get game_url(full_game)
    assert_response :success
    assert_select '[data-testid="game-onboarding"]', 1
    assert_select '[data-testid="onboarding-player_search"]', 0

    get game_url(past_game)
    assert_response :success
    assert_select '[data-testid="game-onboarding"]', 1
    assert_select '[data-testid="onboarding-player_search"]', 0
  end

  test "organizer contact is visible only to admins and never leaks to public HTML" do
    owner = User.create!(
      email: "private_organizer@example.com",
      name: "Private Organizer",
      city_name: "Yekaterinburg",
      telegram_username: "private_organizer",
      telegram_chat_id: 987_654,
      registration_source: "email"
    )
    game = Game.create!(court: courts(:one), user: owner, date: Date.current + 2.days, time: "10:00")

    get game_url(game)
    assert_response :success
    assert_select '[data-testid="game-organizer-admin"]', 0
    assert_select '[data-testid="game-onboarding"]', 0
    assert_not_includes response.body, owner.email

    other_user = User.create!(email: "organizer_contact_other@example.com")
    post session_url, params: { email: other_user.email }
    get game_url(game)
    assert_response :success
    assert_select '[data-testid="game-organizer-admin"]', 0
    assert_select '[data-testid="game-onboarding"]', 0
    assert_not_includes response.body, owner.email

    delete sign_out_url
    post session_url, params: { email: owner.email }
    get game_url(game)
    assert_response :success
    assert_select '[data-testid="game-organizer-admin"]', 0

    delete sign_out_url
    admin = User.create!(email: "organizer_contact_admin@example.com", admin: true)
    post session_url, params: { email: admin.email }
    get game_url(game)
    assert_response :success
    assert_select '[data-testid="game-organizer-admin"]', 1
    assert_includes response.body, owner.email
    assert_select "a[href=?]", "mailto:#{owner.email}"
    assert_select "a[href=?]", "https://t.me/private_organizer"
  end
  test "creating a game with a coach sends a role-specific invitation" do
    coach = User.create!(
      email: "invited-coach@example.com",
      name: "Coach",
      coach: true,
      telegram_chat_id: 91_001,
      notification_channel: "telegram"
    )
    post session_url, params: { email: "coach-game-owner@example.com" }

    calls = []
    stub_singleton(Telegram::Api, :send_with_buttons, ->(*args) { calls << args; { "ok" => true } }) do
      post games_url, params: {
        game: {
          court_id: courts(:one).id,
          date: Date.current + 1.day,
          time: "18:00",
          recurring: "1",
          with_coach: "1",
          coach_id: coach.id
        }
      }
    end

    game = Game.order(:id).last
    assert_equal coach, game.coach
    assert_equal "pending", game.coach_invitation_status
    assert_equal "game:coach_accept:#{game.id}", calls.first.third.first.first[:callback_data]
  ensure
    coach&.destroy
  end

  test "selected coach can accept invitation on the game page" do
    coach = User.create!(email: "accept-coach@example.com", coach: true)
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      coach: coach,
      coach_invitation_status: "pending",
      with_coach: true,
      recurring: true,
      date: Date.current
    )
    post session_url, params: { email: coach.email }

    post accept_coach_invitation_game_url(game)

    assert_redirected_to game_path(game)
    assert game.reload.coach_accepted?
  ensure
    coach&.destroy
  end
end
