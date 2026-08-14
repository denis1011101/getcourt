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
end
