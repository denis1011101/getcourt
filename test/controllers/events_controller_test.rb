require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
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

  test "show returns not found for unknown slug" do
    get event_url(id: "missing-event")

    assert_response :not_found
  end
end
