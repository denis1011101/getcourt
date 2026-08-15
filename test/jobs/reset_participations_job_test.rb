require "test_helper"

class ResetParticipationsJobTest < ActiveJob::TestCase
  setup do
    @owner = users(:one)
    @player = User.create!(email: "reset-player@example.com", notification_channel: "email", locale: "en")
  end

  # Регрессия: пока у задачи не было расписания, это не всплывало. С расписанием
  # в recurring.yml первая же ночь после создания серии вычищала состав игры,
  # которая ещё не состоялась — маркер сброса nil, а next_date в будущем.
  test "keeps the lineup of a series whose first occurrence has not been played" do
    game = Game.create!(
      court: courts(:one),
      user: @owner,
      date: Date.current + 3.days,
      time: "18:00",
      recurring: true
    )
    game.participations.create!(user: @player)

    assert_not game.should_reset_participations?, "серия ещё не отыграна — сбрасывать нечего"

    ResetParticipationsJob.perform_now

    assert_equal 1, game.participations.reload.count
    assert_nil game.reload.last_participations_reset_at
  end

  test "clears the lineup once the previous occurrence has passed" do
    game = Game.create!(
      court: courts(:one),
      user: @owner,
      date: Date.current - 14.days,
      time: "18:00",
      recurring: true
    )
    game.participations.create!(user: @player)

    assert game.should_reset_participations?

    ResetParticipationsJob.perform_now

    assert_empty game.participations.reload
    assert_equal game.next_date, game.reload.last_participations_reset_at
  end
end
