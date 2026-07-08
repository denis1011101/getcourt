require "test_helper"

class ParticipationsControllerTest < ActionDispatch::IntegrationTest
  test "owner creates guest participation" do
    post session_url, params: { email: "guest_owner@example.com" }
    owner = User.find_by!(email: "guest_owner@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.tomorrow, time: "10:00")

    assert_difference("Participation.count", 1) do
      post create_guest_game_participations_url(game), params: { guest_name: "  Alex Guest  " }
    end

    assert_redirected_to game_path(game)
    participation = game.participations.order(:id).last
    assert participation.guest?
    assert participation.approved?
    assert_equal "Alex Guest", participation.guest_name
  end

  test "non owner cannot create guest participation" do
    owner = User.create!(email: "guest_non_owner_owner@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.tomorrow, time: "10:00")
    post session_url, params: { email: "guest_non_owner@example.com" }

    assert_no_difference("Participation.count") do
      post create_guest_game_participations_url(game), params: { guest_name: "Alex Guest" }
    end

    assert_response :forbidden
  end

  test "blank guest name redirects with alert" do
    post session_url, params: { email: "guest_blank_owner@example.com" }
    owner = User.find_by!(email: "guest_blank_owner@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.tomorrow, time: "10:00")

    assert_no_difference("Participation.count") do
      post create_guest_game_participations_url(game), params: { guest_name: "   " }
    end

    assert_redirected_to game_path(game)
    assert_equal "Guest name can't be blank.", flash[:alert]
  end

  test "owner removes guest participation" do
    post session_url, params: { email: "guest_destroy_owner@example.com" }
    owner = User.find_by!(email: "guest_destroy_owner@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.tomorrow, time: "10:00")
    participation = Participation.create!(game: game, guest_name: "Alex Guest", status: "approved")

    assert_difference("Participation.count", -1) do
      delete game_participation_url(game, participation)
    end

    assert_redirected_to game_path(game)
  end

  test "stranger cannot remove guest participation" do
    owner = User.create!(email: "guest_destroy_stranger_owner@example.com")
    game = Game.create!(court: courts(:one), user: owner, date: Date.tomorrow, time: "10:00")
    participation = Participation.create!(game: game, guest_name: "Alex Guest", status: "approved")
    post session_url, params: { email: "guest_destroy_stranger@example.com" }

    assert_no_difference("Participation.count") do
      delete game_participation_url(game, participation)
    end

    assert_response :forbidden
  end
end
