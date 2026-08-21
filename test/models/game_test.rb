require "test_helper"

class GameTest < ActiveSupport::TestCase
  test "is invalid without date" do
    game = Game.new(court: courts(:one), user: users(:one), date: nil)

    assert_not game.valid?
    assert_includes game.errors[:date], "must be present"
  end

  test "prebooking_enabled requires recurring game" do
    game = Game.new(court: courts(:one), user: users(:one), date: Date.current, recurring: false, prebooking_enabled: true)

    assert_not game.valid?
    assert_includes game.errors[:prebooking_enabled], "can be enabled only for repeating (weekly) games"
  end

  test "surface must be available at the selected court" do
    court = Court.create!(name: "Clay only", surfaces: %w[clay])
    game = Game.new(court: court, user: users(:one), date: Date.current, surface: "hard")

    assert_not game.valid?
    assert_includes game.errors[:surface], "is not available at the selected court"

    game.surface = "clay"
    assert game.valid?, game.errors.full_messages.to_sentence
  end

  test "environment must be available at the selected court" do
    court = Court.create!(name: "Outdoor only", outdoor: true, indoor: false)
    game = Game.new(court: court, user: users(:one), date: Date.current, environment: "indoor")

    assert_not game.valid?
    assert_includes game.errors[:environment], "is not available at the selected court"

    game.environment = "outdoor"
    assert game.valid?, game.errors.full_messages.to_sentence
  end

  test "surface and environment may be blank regardless of court options" do
    court = Court.create!(name: "Plain", surfaces: [], outdoor: false, indoor: false)
    game = Game.new(court: court, user: users(:one), date: Date.current, surface: "", environment: "")

    assert game.valid?, game.errors.full_messages.to_sentence
  end

  test "next_date for recurring game moves to nearest upcoming occurrence" do
    game = Game.new(court: courts(:one), user: users(:one), date: Date.current - 14.days, recurring: true)

    assert game.next_date >= Date.current
    assert_equal 0, ((game.next_date - game.date) % 7)
  end

  test "prebooking_required_players uses players_count with fallback" do
    game = games(:one)

    game.players_count = 6
    assert_equal 6, game.prebooking_required_players

    game.players_count = 0
    assert_equal 4, game.prebooking_required_players
  end

  test "next_date skips cancelled recurring occurrence" do
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      date: Date.current,
      recurring: true
    )

    PrebookingCancellation.create!(game: game, user: users(:one), date: Date.current)

    assert_equal Date.current + 7.days, game.next_date
  end

  test "display_date_for_show returns previous occurrence when participations were reset there" do
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      date: Date.current - 21.days,
      recurring: true
    )

    next_date = game.next_date
    previous_date = next_date - 7.days
    game.update_column(:last_participations_reset_at, previous_date)

    assert_equal previous_date, game.display_date_for_show
  end

  test "display_date_for_show returns previous occurrence when not yet reset" do
    # Bug fix: stats should stay unlocked until weekly participations reset happens
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      date: Date.current - 21.days,
      recurring: true
    )

    previous_date = game.next_date - 7.days
    # no reset happened yet (last_participations_reset_at is nil or older)
    assert_nil game.last_participations_reset_at
    assert previous_date < Date.today, "previous occurrence should be in the past"

    assert_equal previous_date, game.display_date_for_show
    assert game.started_for_ui?, "stats should be unlocked while previous occurrence is not reset"
  end

  test "display_date_for_show returns next_date after participations are reset" do
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      date: Date.tomorrow - 21.days,
      recurring: true
    )

    nd = game.next_date
    assert_equal Date.tomorrow, nd
    game.mark_participations_reset!(nd)

    assert_equal nd, game.display_date_for_show
    assert_not game.started_for_ui?, "stats should be locked after reset until next game starts"
  end

  test "prebooking_candidate_dates returns weekly date sequence" do
    game = Game.new(court: courts(:one), user: users(:one), date: Date.current - 14.days, recurring: true)

    dates = game.prebooking_candidate_dates(3)

    assert_equal 3, dates.size
    assert_equal 7, (dates[1] - dates[0]).to_i
    assert_equal 7, (dates[2] - dates[1]).to_i
  end
  test "prebooking_candidate_dates includes booked and cancelled dates outside horizon" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current, recurring: true, prebooking_enabled: true)
    booked_date = game.next_date + 8.weeks
    cancelled_date = game.next_date + 9.weeks
    booked_user = User.create!(email: "booked-outside-horizon@example.com")
    game.prebookings.create!(date: booked_date, slot_index: 1, user: booked_user)
    game.prebooking_cancellations.create!(date: cancelled_date, user: booked_user)

    dates = game.prebooking_candidate_dates(3)

    assert_includes dates, booked_date
    assert_includes dates, cancelled_date
  end

  test "prebooking horizon is capped" do
    game = Game.new(court: courts(:one), user: users(:one), date: Date.current, recurring: true)

    assert_equal Game::MAX_PREBOOKING_HORIZON, game.prebooking_horizon_dates(10_000).size
  end

  test "prebooking_candidate_dates drops occurrences that already passed" do
    game = Game.create!(court: courts(:one), user: users(:one), date: 10.weeks.ago.to_date, recurring: true, prebooking_enabled: true)
    past_date = game.next_date - 4.weeks
    booked_user = User.create!(email: "booked-in-the-past@example.com")
    game.prebookings.create!(date: past_date, slot_index: 1, user: booked_user)
    game.prebooking_cancellations.create!(date: past_date - 1.week, user: booked_user)

    dates = game.prebooking_candidate_dates(3)

    assert_not_includes dates, past_date
    assert_equal game.next_date, dates.first
  end

  test "recurring game shows the occurrence that just passed until participations are reset" do
    game = Game.create!(court: courts(:one), user: users(:one), date: 1.week.ago.to_date, recurring: true)
    played = game.date

    travel_to played + 1.day do
      assert_equal played + 1.week, game.next_date
      assert_equal played, game.display_date_for_show, "card must not jump to next week at midnight"

      game.mark_participations_reset!(game.next_date)

      assert_equal played + 1.week, game.display_date_for_show
    end
  end

  test "stats cycle follows the shown occurrence" do
    game = Game.create!(court: courts(:one), user: users(:one), date: 1.week.ago.to_date, recurring: true)

    travel_to game.date + 1.day do
      assert_equal game.display_date_for_show.beginning_of_day, game.current_cycle_start
    end
  end

  test "coach bookings are dropped when the game moves to another day" do
    coach = User.create!(email: "coach-moved-game@example.com", coach: true)
    game = Game.create!(court: courts(:one), user: users(:one), coach: coach, with_coach: true, recurring: true, date: Date.current)
    game.update!(coach_invitation_status: "accepted")
    game.coach_prebookings.create!(coach: coach, date: game.next_date)

    assert_difference -> { game.coach_prebookings.count }, -1 do
      game.update!(date: game.date + 1.day)
    end
  ensure
    coach&.destroy
  end

  test "coach bookings are dropped when the game stops repeating" do
    coach = User.create!(email: "coach-one-off-again@example.com", coach: true)
    game = Game.create!(court: courts(:one), user: users(:one), coach: coach, with_coach: true, recurring: true, date: Date.current)
    game.update!(coach_invitation_status: "accepted")
    game.coach_prebookings.create!(coach: coach, date: game.next_date)

    game.update!(recurring: false)

    assert_empty game.coach_prebookings.reload
  ensure
    coach&.destroy
  end

  test "a game with a coach is a training" do
    coach = User.create!(email: "kind-training-coach@example.com", coach: true)
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current, with_coach: true, coach: coach)

    assert game.training?
    assert_equal "pending", game.coach_invitation_status
  ensure
    coach&.destroy
  end

  test "a game without a coach keeps its kind and drops the selected coaches" do
    coach = User.create!(email: "kind-plain-coach@example.com", coach: true)
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current, with_coach: true, coach: coach)

    game.update!(kind: "game", with_coach: false)

    assert_equal "game", game.kind
    assert_nil game.coach_id
    assert_nil game.coach_invitation_status
  ensure
    coach&.destroy
  end

  test "a training invites both coaches" do
    first = User.create!(email: "first-training-coach@example.com", coach: true)
    second = User.create!(email: "second-training-coach@example.com", coach: true)
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current,
                        kind: "training", with_coach: true, coach: first, second_coach: second)

    assert_equal [ first, second ], game.coaches
    assert_equal "pending", game.second_coach_invitation_status
    assert_equal :second_coach, game.coach_slot_for(second)
  ensure
    first&.destroy
    second&.destroy
  end

  test "the same person cannot take both coach slots" do
    coach = User.create!(email: "twice-picked-coach@example.com", coach: true)
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current,
                        kind: "training", with_coach: true, coach: coach, second_coach: coach)

    assert_equal [ coach ], game.coaches
    assert_nil game.second_coach_id
  ensure
    coach&.destroy
  end

  test "a second coach picked alone becomes the only coach" do
    coach = User.create!(email: "lonely-second-coach@example.com", coach: true)
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current,
                        kind: "training", with_coach: true, second_coach: coach)

    assert_equal coach, game.coach
    assert_nil game.second_coach_id
    assert_equal "pending", game.coach_invitation_status
  ensure
    coach&.destroy
  end

  test "each coach answers their own invitation" do
    first = User.create!(email: "answering-first-coach@example.com", coach: true)
    second = User.create!(email: "answering-second-coach@example.com", coach: true)
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current,
                        kind: "training", with_coach: true, coach: first, second_coach: second)

    game.answer_coach_invitation!(second, "accepted")

    assert_equal [ second ], game.accepted_coaches
    assert game.accepted_coach?(second)
    assert_not game.accepted_coach?(first)
    assert_not game.answer_coach_invitation!(users(:one), "accepted")
  ensure
    first&.destroy
    second&.destroy
  end

  test "bookings of a dropped second coach are removed" do
    first = User.create!(email: "kept-coach@example.com", coach: true)
    second = User.create!(email: "dropped-second-coach@example.com", coach: true)
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current, recurring: true,
                        kind: "training", with_coach: true, coach: first, second_coach: second)
    game.update!(coach_invitation_status: "accepted", second_coach_invitation_status: "accepted")
    game.coach_prebookings.create!(coach: first, date: game.next_date)
    game.coach_prebookings.create!(coach: second, date: game.next_date)

    assert_difference -> { game.coach_prebookings.count }, -1 do
      game.update!(second_coach: nil)
    end

    assert_equal [ first.id ], game.coach_prebookings.reload.map(&:coach_id)
  ensure
    first&.destroy
    second&.destroy
  end

  test "a tournament game is never a training" do
    coach = User.create!(email: "tournament-coach@example.com", coach: true)
    tournament = Tournament.create!(name: "Kind cup", user: users(:one),
                                    start_date: Date.current, end_date: Date.current + 1.day)
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current, tournament: tournament,
                        kind: "training", with_coach: true, coach: coach)

    assert_equal "game", game.kind
    assert_not game.with_coach?
    assert_nil game.coach_id
  ensure
    coach&.destroy
  end

  test "the training plan keeps the order the blocks were picked in" do
    coach = User.create!(email: "plan-order-coach@example.com", coach: true)
    warmup = coach.training_blocks.create!(title: "Разминка")
    serve = coach.training_blocks.create!(title: "Подача")
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current,
                        kind: "training", with_coach: true, coach: coach)

    game.replace_training_plan!([ serve.id, warmup.id ])

    assert_equal [ serve, warmup ], game.training_blocks.to_a
    assert_equal [ 0, 1 ], game.game_training_blocks.map(&:position)
  ensure
    game&.destroy
    coach&.destroy
  end

  test "replacing the plan drops the blocks left out of it" do
    coach = User.create!(email: "plan-replace-coach@example.com", coach: true)
    warmup = coach.training_blocks.create!(title: "Разминка")
    serve = coach.training_blocks.create!(title: "Подача")
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current,
                        kind: "training", with_coach: true, coach: coach)
    game.replace_training_plan!([ warmup.id, serve.id ])

    game.replace_training_plan!([ serve.id ])

    assert_equal [ serve ], game.training_blocks.to_a
    # Блок остаётся в библиотеке тренера, из плана уходит только связь.
    assert_equal 2, coach.training_blocks.count
  ensure
    game&.destroy
    coach&.destroy
  end

  test "turning a training back into a game drops its plan" do
    coach = User.create!(email: "plan-dropped-coach@example.com", coach: true)
    block = coach.training_blocks.create!(title: "Разминка")
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current,
                        kind: "training", with_coach: true, coach: coach)
    game.replace_training_plan!([ block.id ])

    game.update!(kind: "game", with_coach: false)

    assert_empty game.training_blocks.reload
    assert_equal 1, coach.training_blocks.count
  ensure
    game&.destroy
    coach&.destroy
  end

  test "a game with recorded scores cannot become a training" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current, time: "10:00")
    Match.create!(user: users(:one), game: game, mode: "singles", outcome: "win", played_at: Time.current, score: "6:4")

    game.kind = "training"

    assert_not game.valid?
    assert_includes game.errors.full_messages.join, "recorded scores"
  ensure
    game&.destroy
  end

  test "checking with_coach on a scored game is refused too" do
    coach = User.create!(email: "scored-game-coach@example.com", coach: true)
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current, time: "10:00")
    Match.create!(user: users(:one), game: game, mode: "singles", outcome: "win", played_at: Time.current, score: "6:4")

    assert_not game.update(with_coach: true, coach: coach)
    assert_equal "game", game.reload.kind
  ensure
    game&.destroy
    coach&.destroy
  end

  test "a training without scores still accepts new blocks" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.current, time: "10:00")

    assert game.update(kind: "training")
  ensure
    game&.destroy
  end
end
