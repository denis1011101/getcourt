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

  test "add_match accepts a tiebreak score entered on the score board" do
    post session_url, params: { email: @organizer_email }
    @tournament.tournament_participants.find_or_create_by!(user: @organizer) { |p| p.name = @organizer.name }

    assert_difference("TournamentMatch.count", 1) do
      post add_match_tournament_url(@tournament), params: {
        player_a_id: @organizer.id,
        player_b_id: @participant.id,
        score: "7-6(5) 6-4"
      }
    end

    assert_equal "7-6(5) 6-4", TournamentMatch.last.score
    assert_equal "player_a", TournamentMatch.last.result
  end

  test "add match form uses the same score board as games" do
    post session_url, params: { email: @organizer_email }

    get tournament_url(@tournament)

    assert_select "[data-controller='score-board']", 1
    assert_select "form[action=?] input[name='score'][type='hidden']", add_match_tournament_path(@tournament)
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
    assert_equal "Matches can be added after the tournament starts.", flash[:alert]
  end

  # ---- tournament games ---------------------------------------------------

  test "add_match mirrors the match as a game of the tournament" do
    post session_url, params: { email: @organizer_email }
    @tournament.tournament_participants.find_or_create_by!(user: @organizer) { |p| p.name = @organizer.name }

    assert_difference("Game.count", 1) do
      post add_match_tournament_url(@tournament), params: {
        player_a_id: @organizer.id,
        player_b_id: @participant.id,
        score: "6-4 6-3"
      }
    end

    game = Game.last
    assert_equal @tournament, game.tournament
    assert_equal courts(:one), game.court
    assert_equal Date.current, game.date
    assert_equal 2, game.players_count
    assert_equal [ @organizer.id, @participant.id ].sort, game.participations.approved.pluck(:user_id).sort
  end

  test "select_bracket spreads games over the tournament days and skips byes" do
    post session_url, params: { email: @organizer_email }
    tournament = Tournament.create!(user: @organizer, name: "Bracket Cup", players_count: 6,
                                    format: "singles", start_date: Date.current, end_date: Date.current + 3.days)
    tournament.courts << courts(:one)
    6.times do |index|
      player = User.create!(email: "bracket_player_#{index}_#{SecureRandom.hex(4)}@example.com", name: "Bracket Player #{index}")
      tournament.tournament_participants.create!(user: player, name: player.name, status: "approved")
    end

    # 6 players fill an 8-slot bracket: two of them get a bye, so only two first-round games are played.
    assert_difference("Game.count", 2) do
      post select_bracket_tournament_url(tournament)
    end

    games = tournament.games.reload
    assert_equal [ 2, 2 ], games.map { |game| game.participations.count }
    assert_equal games.map(&:date).uniq.size, games.size, "Games should be spread over different days"
    games.each do |game|
      assert_includes (tournament.start_date..tournament.end_date), game.date
    end
  end

  test "tournament games are listed on the tournament page" do
    game = @tournament.create_game!(organizer: @organizer, player_ids: [ @participant.id ])

    get tournament_url(@tournament)

    assert_response :success
    assert_select "a[href=?]", game_path(game)
  end

  test "tournament game form hides the standalone game options and limits date and court" do
    post session_url, params: { email: @organizer_email }
    game = @tournament.create_game!(organizer: @organizer, player_ids: [ @participant.id ])

    get edit_game_url(game)

    assert_response :success
    assert_select "input[name='game[recurring]']", 0
    assert_select "input[name='game[prebooking_enabled]']", 0
    assert_select "input[name='game[with_coach]']", 0
    assert_select "input[name='game[urgent_player_search]']", 0
    assert_select "input[name='game[date]'][min=?]", @tournament.start_date.to_s
    assert_select "select[name='game[court_id]'] option", 1
  end

  test "tournament game keeps the standalone options off and stays inside the tournament" do
    @tournament.update!(end_date: @tournament.start_date + 2.days)
    game = @tournament.create_game!(organizer: @organizer, player_ids: [ @participant.id ])
    other_court = Court.create!(name: "Outside Court #{SecureRandom.hex(4)}")

    game.update(recurring: true, with_coach: true, urgent_player_search: true)
    assert_not game.reload.recurring?
    assert_not game.with_coach?
    assert_not game.urgent_player_search?

    assert_not game.update(date: @tournament.start_date + 30.days)
    assert_includes game.errors[:date], "must be within the tournament dates"

    game.reload
    assert_not game.update(court: other_court)
    assert_includes game.errors[:court_id], "must be one of the tournament courts"
  ensure
    other_court&.destroy
  end

  test "games index can be filtered down to tournament games" do
    tournament_game = @tournament.create_game!(organizer: @organizer, player_ids: [ @participant.id ])
    plain_game = Game.create!(court: courts(:one), user: @organizer, date: Date.current)

    get root_url, params: { tournament_games: "1" }

    assert_response :success
    games = @controller.instance_variable_get(:@games)
    assert_includes games, tournament_game
    assert_not_includes games, plain_game
  end

  test "add_match without a court asks the organizer to add one" do
    post session_url, params: { email: @organizer_email }
    @tournament.tournament_courts.destroy_all
    @tournament.tournament_participants.find_or_create_by!(user: @organizer) { |p| p.name = @organizer.name }

    assert_no_difference([ "Game.count", "TournamentMatch.count" ]) do
      post add_match_tournament_url(@tournament), params: {
        player_a_id: @organizer.id,
        player_b_id: @participant.id,
        score: "6-4 6-3"
      }
    end

    assert_equal "Add a court to the tournament first.", flash[:alert]
  end

  # ---- CRUD ---------------------------------------------------------------

  test "organizer can update the tournament" do
    post session_url, params: { email: @organizer_email }

    patch tournament_url(@tournament), params: { tournament: { name: "Renamed Cup", players_count: 6 } }

    assert_redirected_to tournament_url(@tournament)
    assert_equal "Renamed Cup", @tournament.reload.name
    assert_equal 6, @tournament.players_count
  end

  test "invalid update re-renders the form" do
    post session_url, params: { email: @organizer_email }

    patch tournament_url(@tournament), params: { tournament: { name: "" } }

    assert_response :unprocessable_entity
    assert_equal "Integration Tournament", @tournament.reload.name
  end

  test "non-organizer cannot edit or destroy the tournament" do
    post session_url, params: { email: @participant_email }

    get edit_tournament_url(@tournament)
    assert_redirected_to tournaments_url

    assert_no_difference("Tournament.count") do
      delete tournament_url(@tournament)
    end
  end

  test "organizer can destroy the tournament and its games stay in the games list" do
    post session_url, params: { email: @organizer_email }
    game = @tournament.create_game!(organizer: @organizer, player_ids: [ @participant.id ])

    assert_difference("Tournament.count", -1) do
      delete tournament_url(@tournament)
    end

    assert_redirected_to tournaments_url
    assert_nil game.reload.tournament_id
  end

  # ---- joining ------------------------------------------------------------

  test "join adds an approved participant while there are free spots" do
    user_email = "tournament_joiner_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }

    post join_tournament_url(@tournament)

    participant = @tournament.tournament_participants.find_by(user: User.find_by!(email: user_email))
    assert participant.approved?
  end

  test "organizer can join their own tournament" do
    post session_url, params: { email: @organizer_email }

    get tournament_url(@tournament)
    assert_select "form[action=?]", join_tournament_path(@tournament)

    post join_tournament_url(@tournament)

    assert @tournament.participant_for(@organizer).approved?
  end

  test "organizer joins a full tournament without waiting for approval" do
    @tournament.update!(players_count: 2)
    @tournament.tournament_participants.create!(user: users(:one), name: "Filler", status: "approved")
    assert @tournament.full?

    post session_url, params: { email: @organizer_email }

    post join_tournament_url(@tournament)

    assert @tournament.participant_for(@organizer).approved?
  end

  test "join a full tournament creates a pending request the organizer can approve" do
    @tournament.update!(players_count: 2)
    @tournament.tournament_participants.create!(user: @organizer, name: @organizer.name, status: "approved")

    user_email = "tournament_late_#{SecureRandom.hex(4)}@example.com"
    post session_url, params: { email: user_email }
    post join_tournament_url(@tournament)

    latecomer = User.find_by!(email: user_email)
    participant = @tournament.tournament_participants.find_by(user: latecomer)
    assert participant.pending?

    post session_url, params: { email: @organizer_email }
    patch tournament_participant_url(@tournament, participant)

    assert participant.reload.approved?
  end

  test "organizer can remove a participant" do
    post session_url, params: { email: @organizer_email }
    participant = @tournament.tournament_participants.find_by!(user: @participant)

    assert_difference("TournamentParticipant.count", -1) do
      delete tournament_participant_url(@tournament, participant)
    end
  end
end
