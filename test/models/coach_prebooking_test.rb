require "test_helper"

class CoachPrebookingTest < ActiveSupport::TestCase
  test "coach booking is separate from player slots" do
    coach = User.create!(email: "coach-booking-model@example.com", coach: true)
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      coach: coach,
      with_coach: true,
      recurring: true,
      date: Date.current
    )
    game.update!(coach_invitation_status: "accepted")

    assert_difference -> { game.coach_prebookings.count }, 1 do
      assert_no_difference -> { game.prebookings.count } do
        game.coach_prebookings.create!(coach: coach, date: game.next_date)
      end
    end
  ensure
    coach&.destroy
  end

  test "rejects a coach who is not accepted for the game" do
    coach = User.create!(email: "coach-booking-pending@example.com", coach: true)
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      coach: coach,
      coach_invitation_status: "pending",
      with_coach: true,
      recurring: true,
      date: Date.current
    )

    booking = game.coach_prebookings.build(coach: coach, date: game.next_date)

    assert_not booking.valid?
    assert booking.errors.added?(:coach, "must be the accepted game coach")
  ensure
    coach&.destroy
  end
end
