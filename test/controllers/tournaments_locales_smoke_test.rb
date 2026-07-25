require "test_helper"

class TournamentsLocalesSmokeTest < ActionDispatch::IntegrationTest
  setup do
    @organizer = User.find_or_create_by!(email: "locale_owner@example.com") { |u| u.name = "Owner" }
    @tournament = Tournament.create!(user: @organizer, name: "Locale Cup", players_count: 4,
                                     format: "doubles", tournament_type: "round_robin",
                                     start_date: Date.yesterday, time: "10:00")
    @tournament.courts << courts(:one)
    @tournament.tournament_participants.create!(user: @organizer, name: @organizer.name, status: "approved")
    @tournament.create_game!(organizer: @organizer, player_ids: [ @organizer.id ])
  end

  %w[en ru es].each do |locale|
    test "tournament pages are fully translated in #{locale}" do
      post session_url, params: { email: @organizer.email }
      get set_locale_url(locale: locale)

      [
        tournaments_url,
        tournament_url(@tournament),
        new_tournament_url,
        edit_tournament_url(@tournament),
        options_tournaments_url(tournament_id: @tournament.id),
        root_url(tournament_games: "1"),
        game_url(@tournament.games.first)
      ].each do |url|
        get url

        assert_response :success, "#{url} did not render in #{locale}"
        assert_no_match(/translation missing/i, @response.body, "#{url} has a missing translation in #{locale}")
      end
    end
  end
end
