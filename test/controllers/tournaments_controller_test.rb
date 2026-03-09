require "test_helper"

class TournamentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @organizer_email = "tournament_owner@example.com"
    @participant_email = "tournament_participant@example.com"
    @organizer = User.find_or_create_by!(email: @organizer_email) { |u| u.name = "Owner" }
    @participant = User.find_or_create_by!(email: @participant_email) { |u| u.name = "Participant" }
    @tournament = Tournament.create!(
      user: @organizer,
      name: "Integration Tournament",
      players_count: 8,
      format: "singles",
      start_date: Date.yesterday
    )
    @tournament.courts << courts(:one)
    @tournament.tournament_participants.create!(user: @participant, name: @participant.name)
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  test "should get index" do
    get tournaments_url
    assert_response :success
  end

  test "should get options" do
    get options_tournaments_url, params: { tournament_id: tournaments(:one).id }
    assert_response :success
  end

  test "should get show" do
    get tournament_url(tournaments(:one))
    assert_response :success
  end

  test "should redirect new when not authenticated" do
    get new_tournament_url
    assert_redirected_to new_session_path
  end

  test "add_match creates tournament match for valid score" do
    post session_url, params: { email: @organizer_email }
    @tournament.tournament_participants.find_or_create_by!(user: @organizer) { |p| p.name = @organizer.name }

    assert_difference("TournamentMatch.count", 1) do
      post add_match_tournament_url(@tournament), params: {
        player_a_id: @organizer.id,
        player_b_id: @participant.id,
        score: "6-4 6-3"
      }
    end

    assert_redirected_to tournament_url(@tournament)
    match = TournamentMatch.last
    assert_equal "6-4 6-3", match.score
    assert_equal "player_a", match.result
  end

  test "add_match rejects missing players" do
    post session_url, params: { email: @organizer_email }
    assert_no_difference("TournamentMatch.count") do
      post add_match_tournament_url(@tournament), params: {
        player_a_id: @participant.id,
        score: "6-4 6-3"
      }
    end

    assert_redirected_to tournament_url(@tournament)
    assert_equal "Select both players.", flash[:alert]
  end

  # ---- city-first ordering ------------------------------------------------

  test "same-city tournament appears before other-city tournament on index" do
    user_email = "tournaments_city_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    city_user = User.find_by!(email: user_email)
    city_user.update_column(:city_name, "Kazan")

    local_court = Court.create!(name: "Kazan Court #{SecureRandom.hex(4)}", city_name: "Kazan")
    other_court = Court.create!(name: "Moscow Court #{SecureRandom.hex(4)}", city_name: "Moscow")

    local_t = Tournament.create!(user: city_user, name: "Local T", players_count: 4,
                                 format: "singles", start_date: Date.tomorrow)
    other_t = Tournament.create!(user: city_user, name: "Other T", players_count: 4,
                                 format: "singles", start_date: Date.tomorrow)
    local_t.courts << local_court
    other_t.courts << other_court

    get tournaments_url

    ts = assigns(:tournaments)
    assert ts.index(local_t) < ts.index(other_t),
           "Same-city tournament should appear before other-city tournament"
  ensure
    TournamentCourt.where(tournament_id: [ local_t&.id, other_t&.id ].compact).delete_all
    local_t&.destroy
    other_t&.destroy
    city_user&.destroy
    local_court&.destroy
    other_court&.destroy
  end

  test "same-city tournament appears before other-city tournament on my_tournaments" do
    user_email = "my_tournaments_city_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    city_user = User.find_by!(email: user_email)
    city_user.update_column(:city_name, "Kazan")

    local_court = Court.create!(name: "My Kazan Court #{SecureRandom.hex(4)}", city_name: "Kazan")
    other_court = Court.create!(name: "My Moscow Court #{SecureRandom.hex(4)}", city_name: "Moscow")

    local_t = Tournament.create!(user: city_user, name: "My Local T", players_count: 4,
                                 format: "singles", start_date: Date.tomorrow)
    other_t = Tournament.create!(user: city_user, name: "My Other T", players_count: 4,
                                 format: "singles", start_date: Date.tomorrow)
    local_t.courts << local_court
    other_t.courts << other_court

    get tournaments_url, params: { my_tournaments: "1" }

    ts = assigns(:tournaments)
    assert ts.index(local_t) < ts.index(other_t),
           "Same-city tournament should appear before other-city tournament in my_tournaments"
  ensure
    TournamentCourt.where(tournament_id: [ local_t&.id, other_t&.id ].compact).delete_all
    local_t&.destroy
    other_t&.destroy
    city_user&.destroy
    local_court&.destroy
    other_court&.destroy
  end

  test "add_match is blocked before tournament starts" do
    post session_url, params: { email: @organizer_email }
    future_tournament = Tournament.create!(
      user: @organizer,
      name: "Future Tournament",
      players_count: 8,
      format: "singles",
      start_date: Date.tomorrow
    )
    future_tournament.courts << courts(:one)
    future_tournament.tournament_participants.create!(user: @participant, name: @participant.name)

    assert_no_difference("TournamentMatch.count") do
      post add_match_tournament_url(future_tournament), params: {
        player_a_id: @organizer.id,
        player_b_id: @participant.id,
        score: "6-4 6-3"
      }
    end

    assert_redirected_to tournament_url(future_tournament)
    assert_equal "Statistics available after tournament starts.", flash[:alert]
  end
end
