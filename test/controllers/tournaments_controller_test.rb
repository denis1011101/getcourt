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

  test "add_game_result creates game and match for valid score" do
    post session_url, params: { email: @organizer_email }
    assert_difference("Game.count", 1) do
      assert_difference("Match.count", 1) do
        post add_game_result_tournament_url(@tournament), params: {
          user_id: @participant.id,
          score: "6-4 6-3"
        }
      end
    end

    assert_redirected_to tournament_url(@tournament)
  end

  test "add_game_result rejects invalid hours input" do
    post session_url, params: { email: @organizer_email }
    assert_no_difference("Game.count") do
      post add_game_result_tournament_url(@tournament), params: {
        user_id: @participant.id,
        score: "6-4 6-3",
        hours: "abc"
      }
    end

    assert_redirected_to tournament_url(@tournament)
    assert_equal "Enter valid hours (0 or greater).", flash[:alert]
  end

  test "add_game_result is blocked before tournament starts" do
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

    assert_no_difference("Game.count") do
      post add_game_result_tournament_url(future_tournament), params: {
        user_id: @participant.id,
        score: "6-4 6-3",
        hours: "1.0"
      }
    end

    assert_redirected_to tournament_url(future_tournament)
    assert_equal "Statistics available after tournament starts.", flash[:alert]
  end
end
