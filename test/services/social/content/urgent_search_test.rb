require "test_helper"

class Social::Content::UrgentSearchTest < ActiveSupport::TestCase
  setup do
    @court = Court.create!(name: "Urgent Court", city_name: "Greater London", coordinates: "51.4344, -0.2144")
    @user = User.create!(email: "urgent_content@example.com")
    @game = Game.create!(court: @court, user: @user, date: Date.current + 2, time: "19:00",
                         sport: "Tennis", players_count: 4, urgent_player_search: true)
  end

  test "text carries the sport, city, court and free spots" do
    text = Social::Content::UrgentSearch.new(@game).text(locale: :en)

    assert_includes text, "Tennis"
    assert_includes text, "Greater London"
    assert_includes text, "Urgent Court"
    assert_includes text, "4 spots left"
    assert_includes text, "#GetCourt"
    assert_includes text, "/games/#{@game.id}"
  end

  test "text is truncated to the platform limit" do
    text = Social::Content::UrgentSearch.new(@game).text(locale: :en, limit: 40)

    assert_equal 40, Social::RichText.grapheme_length(text)
  end

  test "a game without a sport does not leave a double space" do
    @game.update!(sport: nil)

    assert_not_includes Social::Content::UrgentSearch.new(@game).text(locale: :en), "  "
  end

  test "geo and calendar come from the court and the schedule" do
    content = Social::Content::UrgentSearch.new(@game)

    assert_in_delta 51.4344, content.geo[:lat], 0.0001
    assert_in_delta(-0.2144, content.geo[:lng], 0.0001)
    assert_equal "Urgent Court, Greater London", content.geo[:label]
    assert_equal 3600, (content.calendar[:ends_at] - content.calendar[:starts_at]).to_i
  end

  test "a court without coordinates gives no geo" do
    @court.update!(coordinates: nil)

    assert_nil Social::Content::UrgentSearch.new(@game.reload).geo
  end

  test "rebuilds from its dedup key and goes unavailable once the search is off" do
    content = Social::Content::UrgentSearch.from_key("game:#{@game.id}")

    assert content.available?

    @game.update!(urgent_player_search: false)
    assert_not Social::Content::UrgentSearch.from_key("game:#{@game.id}").available?
  end

  test "an unknown key builds nothing" do
    assert_nil Social::Content::UrgentSearch.from_key("game:0")
    assert_nil Social::Content::UrgentSearch.from_key("nonsense")
  end
end
