require "test_helper"

class CoachPrebookingsControllerTest < ActionDispatch::IntegrationTest
  test "accepted coach can confirm a date without taking a player slot" do
    coach = User.create!(email: "coach-booking-controller@example.com", coach: true)
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      coach: coach,
      with_coach: true,
      recurring: true,
      date: Date.current
    )
    game.update!(coach_invitation_status: "accepted")
    post session_url, params: { email: coach.email }

    assert_difference -> { game.coach_prebookings.count }, 1 do
      assert_no_difference -> { game.prebookings.count } do
        post game_coach_prebookings_url(game), params: { date: game.next_date }
      end
    end

    assert_redirected_to game_path(game)
  ensure
    coach&.destroy
  end

  test "a coach cannot cancel the other coach's confirmation" do
    first = User.create!(email: "booking-owner-coach@example.com", coach: true)
    second = User.create!(email: "booking-other-coach@example.com", coach: true)
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      kind: "training",
      with_coach: true,
      coach: first,
      second_coach: second,
      recurring: true,
      date: Date.current
    )
    game.update!(coach_invitation_status: "accepted", second_coach_invitation_status: "accepted")
    booking = game.coach_prebookings.create!(coach: first, date: game.next_date)
    post session_url, params: { email: second.email }

    assert_no_difference -> { game.coach_prebookings.count } do
      delete game_coach_prebooking_url(game, booking)
    end

    assert_response :not_found
  ensure
    first&.destroy
    second&.destroy
  end

  test "a coach cancels their own confirmation" do
    coach = User.create!(email: "booking-cancelling-coach@example.com", coach: true)
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      kind: "training",
      with_coach: true,
      coach: coach,
      recurring: true,
      date: Date.current
    )
    game.update!(coach_invitation_status: "accepted")
    booking = game.coach_prebookings.create!(coach: coach, date: game.next_date)
    post session_url, params: { email: coach.email }

    assert_difference -> { game.coach_prebookings.count }, -1 do
      delete game_coach_prebooking_url(game, booking)
    end

    assert_redirected_to game_path(game)
  ensure
    coach&.destroy
  end
end
