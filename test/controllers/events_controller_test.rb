require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  BROWSER_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze

  test "show renders existing featured match" do
    match = FeaturedMatch.create!(
      tournament_label: "Madrid Open Final",
      player_left_name: "J. Sinner",
      player_right_name: "A. Zverev",
      starts_at: 1.day.from_now,
      description: "Final preview."
    )

    get event_url(match)

    assert_response :success
    assert_select "title", "#{match.seo_title} | GetCourt"
    assert_select "meta[property='og:type'][content='website']"
    assert_includes response.body, "Final preview."
  end

  test "show links to the game only while the game still describes the event" do
    game = Game.create!(user: users(:one), court: courts(:one), date: Date.yesterday, recurring: false)
    match = FeaturedMatch.create!(
      tournament_label: "Yard Tournament",
      player_left_name: "Andrey",
      player_right_name: "Roman",
      starts_at: Time.zone.yesterday.change(hour: 17),
      game: game
    )

    get event_url(match)

    assert_response :success
    assert_select "a[href=?]", game_path(game)

    # Пятничная чистка сносит прошедшую разовую игру — ссылке вести уже некуда.
    game.destroy

    get event_url(match)

    assert_response :success
    assert_select "a[href=?]", game_path(game), false
  end

  test "show returns not found for unknown slug" do
    get event_url(id: "missing-event")

    assert_response :not_found
  end

  test "show tracks a wallchart_event_viewed for the promo final" do
    travel_to ApplicationHelper::WALLCHART_BANNER_UNTIL - 1.day do
      match = FeaturedMatch.create!(
        tournament_label: "World Cup 2026 Final",
        player_left_name: "Finalist 1",
        player_right_name: "Finalist 2",
        starts_at: 1.day.from_now,
        active: true
      )

      assert_difference -> { Ahoy::Event.where(name: "wallchart_event_viewed").count }, 1 do
        get event_url(match), headers: { "User-Agent" => BROWSER_UA }
      end

      event = Ahoy::Event.where(name: "wallchart_event_viewed").last
      assert_equal ApplicationHelper::WALLCHART_CAMPAIGN, event.properties["campaign"]
      assert_equal match.slug, event.properties["event_slug"]
    end
  end

  test "show does not track wallchart_event_viewed for prefetch requests" do
    travel_to ApplicationHelper::WALLCHART_BANNER_UNTIL - 1.day do
      match = FeaturedMatch.create!(
        tournament_label: "World Cup 2026 Final",
        player_left_name: "Finalist 1",
        player_right_name: "Finalist 2",
        starts_at: 1.day.from_now,
        active: true
      )

      assert_no_difference -> { Ahoy::Event.count } do
        get event_url(match), headers: { "User-Agent" => BROWSER_UA, "Sec-Purpose" => "prefetch" }
      end
    end
  end

  test "show does not track for a match that is not the promo final" do
    match = FeaturedMatch.create!(
      tournament_label: "Madrid Open Final",
      player_left_name: "J. Sinner",
      player_right_name: "A. Zverev",
      starts_at: 1.day.from_now,
      active: false
    )

    assert_no_difference -> { Ahoy::Event.count } do
      get event_url(match), headers: { "User-Agent" => BROWSER_UA }
    end
  end

  test "show renders wallchart click-tracking hooks on the promo links" do
    travel_to ApplicationHelper::WALLCHART_BANNER_UNTIL - 1.day do
      match = FeaturedMatch.create!(
        tournament_label: "World Cup 2026 Final",
        player_left_name: "Finalist 1",
        player_right_name: "Finalist 2",
        starts_at: 1.day.from_now,
        active: true
      )

      get event_url(match), headers: { "User-Agent" => BROWSER_UA }

      assert_response :success
      assert_select "a[data-wallchart-analytics-click-event-value='wallchart_prediction_clicked']"
      assert_select "a[data-wallchart-analytics-click-event-value='wallchart_map_clicked']"
    end
  end
end
