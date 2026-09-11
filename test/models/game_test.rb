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

  # Серия по понедельникам в 18:00: состав понедельника уступает место
  # следующему занятию в четверг в 20:00 — посередине между ними.
  test "the card keeps the played occurrence until the reset moment" do
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      date: Date.new(2026, 8, 31),
      time: "18:00",
      recurring: true
    )

    travel_to Time.zone.local(2026, 9, 10, 19, 59) do
      assert_equal Date.new(2026, 9, 7), game.display_date_for_show
      assert game.started_for_ui?, "stats should be unlocked while the played occurrence is still shown"
    end
  end

  test "the card moves on to the next occurrence once the reset has happened" do
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      date: Date.new(2026, 8, 31),
      time: "18:00",
      recurring: true
    )

    travel_to Time.zone.local(2026, 9, 10, 20, 0) do
      assert_equal Date.new(2026, 9, 7), game.display_date_for_show,
                   "момент настал, но состав ещё прежний — карточке рано переезжать"

      game.mark_participations_reset!(Date.new(2026, 9, 14))

      assert_equal Date.new(2026, 9, 14), game.display_date_for_show
      assert_not game.started_for_ui?, "stats should be locked until the next game starts"
    end
  end

  test "prebooking_horizon_dates returns weekly date sequence" do
    game = Game.new(court: courts(:one), user: users(:one), date: Date.current - 14.days, recurring: true)

    dates = game.prebooking_horizon_dates(3)

    assert_equal 3, dates.size
    assert_equal 7, (dates[1] - dates[0]).to_i
    assert_equal 7, (dates[2] - dates[1]).to_i
  end
  # Календарь предзаписи листается по месяцам: показываем занятия месяца
  # начиная с сегодняшнего дня — включая отменённое, которое ещё можно вернуть.
  test "prebooking_dates_in lists this month's sessions from today on" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 8, 31), recurring: true, prebooking_enabled: true)

    travel_to Time.zone.local(2026, 9, 12, 12, 0) do
      game.prebooking_cancellations.create!(date: Date.new(2026, 9, 14), user: users(:one))

      assert_equal [ Date.new(2026, 9, 14), Date.new(2026, 9, 21), Date.new(2026, 9, 28) ],
                   game.prebooking_dates_in(Date.new(2026, 9, 1))
      assert_equal [ Date.new(2026, 10, 5), Date.new(2026, 10, 12), Date.new(2026, 10, 19), Date.new(2026, 10, 26) ],
                   game.prebooking_dates_in(Date.new(2026, 10, 1))
    end
  end

  # Отменили всё, что оставалось, — календарь всё равно нужен: вернуть дату
  # можно только из него.
  test "a series with every remaining session cancelled keeps its calendar" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7), players_count: 2,
                        occurrence_dates: %w[2026-09-07 2026-09-14], prebooking_enabled: true)

    travel_to Time.zone.local(2026, 9, 12, 12, 0) do
      game.prebooking_cancellations.create!(date: Date.new(2026, 9, 14), user: users(:one))

      assert_nil game.next_date
      assert_equal Date.new(2026, 9, 1), game.prebooking_month
      assert_equal [ Date.new(2026, 9, 14) ], game.prebooking_dates_in(Date.new(2026, 9, 1))
    end
  end

  # Листать можно от месяца ближайшего занятия на год вперёд, у конечной серии
  # — до месяца последней даты; просьба показать что-то за границей возвращает
  # ближайший допустимый месяц.
  test "prebooking months run from the next session up to a year ahead" do
    endless = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 8, 31), recurring: true)
    finite = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7),
                          occurrence_dates: %w[2026-09-07 2026-11-10])

    travel_to Time.zone.local(2026, 9, 12, 12, 0) do
      assert_equal Date.new(2026, 9, 1)..Date.new(2027, 8, 1), endless.prebooking_month_range
      assert_equal Date.new(2027, 8, 1), endless.prebooking_month("2030-01")
      assert_equal Date.new(2026, 9, 1), endless.prebooking_month("мусор")

      assert_equal Date.new(2026, 11, 1)..Date.new(2026, 11, 1), finite.prebooking_month_range
    end
  end

  test "prebooking horizon is capped" do
    game = Game.new(court: courts(:one), user: users(:one), date: Date.current, recurring: true)

    assert_equal Game::MAX_PREBOOKING_HORIZON, game.prebooking_horizon_dates(10_000).size
  end

  test "recurring game shows the occurrence that just passed until participations are reset" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 8, 31), time: "18:00", recurring: true)
    played = Date.new(2026, 9, 7)

    travel_to Time.zone.local(2026, 9, 8, 0, 1) do
      assert_equal played + 1.week, game.next_date
      assert_equal played, game.display_date_for_show, "card must not jump to next week at midnight"
    end

    travel_to Time.zone.local(2026, 9, 10, 20, 0) do
      game.mark_participations_reset!(played + 1.week)

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

  test "chat stays open until the weekly reset, not for a fixed day" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 3), kind: "game")

    # Среда: игра в четверг, разберёт её состав ближайшая суббота.
    travel_to Time.zone.local(2026, 9, 2, 21, 0) do
      assert_equal Time.zone.local(2026, 9, 5, 4, 0), Game::OccurrenceCycle.next_weekly_reset_at
      assert_equal Time.zone.local(2026, 9, 5, 4, 0), game.chat_open_until
      assert game.chat_open?
    end
  ensure
    game&.destroy
  end

  # Ближайшая суббота ничего не делает с составом игры, назначенной после неё:
  # чистка сносит только прошедшие разовые игры, сброс — только отыгранные серии.
  test "a game scheduled beyond the coming reset keeps its chat until its own" do
    one_off = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 20), kind: "game")
    # Серия по воскресеньям: её состав уступит место следующему в среду вечером.
    series = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 6), time: "18:00", recurring: true, kind: "game")

    travel_to Time.zone.local(2026, 9, 2, 21, 0) do
      assert_equal Time.zone.local(2026, 9, 26, 4, 0), one_off.chat_open_until
      assert_equal Time.zone.local(2026, 9, 9, 20, 0), series.chat_open_until
      assert one_off.chat_open?
      assert series.chat_open?
    end
  ensure
    [ one_off, series ].compact.each(&:destroy)
  end

  test "chat closes once the cleanup that removes the game has passed" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 8, 25), kind: "game")

    travel_to Time.zone.local(2026, 9, 2, 21, 0) do
      assert_nil game.chat_open_until
      assert_not game.chat_open?
    end
  ensure
    game&.destroy
  end

  test "the chat window rolls over to the next week right at the reset" do
    travel_to Time.zone.local(2026, 9, 5, 3, 59) do
      assert_equal Time.zone.local(2026, 9, 5, 4, 0), Game::OccurrenceCycle.next_weekly_reset_at
    end

    travel_to Time.zone.local(2026, 9, 5, 4, 0) do
      assert_equal Time.zone.local(2026, 9, 12, 4, 0), Game::OccurrenceCycle.next_weekly_reset_at
    end
  end

  # Календарь в форме даёт отметить несколько дней: игра остаётся одной, а её
  # дата переезжает с занятия на занятие.
  test "a series with several weekdays moves to the nearest of them" do
    # 7 сентября 2026 — понедельник, серия идёт по понедельникам и четвергам.
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7),
                        recurring: true, recurrence_days: [ 1, 4 ], kind: "game")

    assert game.occurrence_date?(Date.new(2026, 9, 10))
    assert_not game.occurrence_date?(Date.new(2026, 9, 9))

    travel_to Time.zone.local(2026, 9, 8, 12, 0) do
      assert_equal Date.new(2026, 9, 10), game.next_date
    end

    travel_to Time.zone.local(2026, 9, 11, 12, 0) do
      assert_equal Date.new(2026, 9, 14), game.next_date
      assert_equal Date.new(2026, 9, 10), game.previous_occurrence_before_next_date
    end
  ensure
    game&.destroy
  end

  test "prebooking dates follow every weekday of the series" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7),
                        recurring: true, recurrence_days: [ 1, 4 ], prebooking_enabled: true, kind: "game")

    travel_to Time.zone.local(2026, 9, 7, 9, 0) do
      assert_equal [ Date.new(2026, 9, 7), Date.new(2026, 9, 10), Date.new(2026, 9, 14), Date.new(2026, 9, 17) ],
                   game.prebooking_horizon_dates(4)
    end
  ensure
    game&.destroy
  end

  # Серии, заведённые до мультивыбора, живут с пустым расписанием: их день
  # недели — день их же даты.
  test "an empty schedule still means weekly on the day of the date" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7), recurring: true, kind: "game")

    assert_equal [ 1 ], game.recurrence_weekdays
    assert game.occurrence_date?(Date.new(2026, 9, 14))
    assert_not game.occurrence_date?(Date.new(2026, 9, 10))
  ensure
    game&.destroy
  end

  # Дату переносят и из телеграм-бота, где выбирают один день: расписание,
  # оставшееся от календаря, там уже не про эту серию.
  test "moving the date off the schedule leaves the weekday of the new date" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7),
                        recurring: true, recurrence_days: [ 1, 4 ], kind: "game")

    game.update!(date: Date.new(2026, 9, 9))

    assert_equal [ 3 ], game.recurrence_days
  ensure
    game&.destroy
  end

  test "a one-off game keeps no schedule" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7),
                        recurring: false, recurrence_days: [ 1, 4 ], kind: "game")

    assert_equal [], game.recurrence_days
    assert_equal [ Date.new(2026, 9, 7) ], game.recurrence_seed_dates
  ensure
    game&.destroy
  end

  test "the form calendar shows one date per weekday of the series" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7),
                        recurring: true, recurrence_days: [ 1, 4 ], kind: "game")

    assert_equal [ Date.new(2026, 9, 7), Date.new(2026, 9, 10) ], game.recurrence_seed_dates
  ensure
    game&.destroy
  end

  # Час занятия и «20:00» смены состава — это часы там, где выходят на корт.
  # Сервер и открытая страница бывают в других поясах, и разница в два часа
  # сдвинула бы сброс на время, когда игра ещё идёт.
  test "the cycle is anchored to the time zone of the game owner" do
    owner = User.create!(email: "moscow-owner@example.com", timezone: "Europe/Moscow")
    game = Game.create!(court: courts(:one), user: owner, date: Date.new(2026, 9, 7), time: "18:00",
                        recurring: true, kind: "game")

    Time.use_zone("Asia/Yekaterinburg") do
      travel_to Time.zone.local(2026, 9, 6, 12, 0) do
        assert_equal game.start_at_for_ui, game.occurrence_starts_at(game.date),
                     "начало занятия считаем так же, как его показывает карточка"

        reset_at = game.occurrence_cycle.reset_at(game.date).in_time_zone("Europe/Moscow")

        assert_equal Date.new(2026, 9, 10), reset_at.to_date
        assert_equal 20, reset_at.hour, "восемь вечера — в поясе игры, а не вызывающего кода"
      end
    end

    # Та же запись, прочитанная из другого окружения, начинается в тот же миг:
    # колонка time зонозависимая, и часы с неё надо снимать в поясе игры.
    from_moscow = Time.use_zone("Europe/Moscow") { Game.find(game.id).occurrence_starts_at(game.date) }
    from_yekaterinburg = Time.use_zone("Asia/Yekaterinburg") { Game.find(game.id).occurrence_starts_at(game.date) }

    assert_equal from_moscow, from_yekaterinburg
  ensure
    game&.destroy
    owner&.destroy
  end

  # Чат живёт столько же, сколько состав: у серии «ср + чт» состав среды
  # уступает место четвергу в тот же вечер, а не через несколько дней.
  test "the chat of a series with adjacent days closes on the evening of the same day" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 9), time: "18:00",
                        recurring: true, recurrence_days: [ 3, 4 ], kind: "game")

    travel_to Time.zone.local(2026, 9, 9, 19, 30) do
      assert_equal Time.zone.local(2026, 9, 9, 20, 0), game.chat_open_until
    end
  ensure
    game&.destroy
  end

  # Снятый день уносит с собой не только брони тренера: слот на несуществующем
  # занятии остался бы в календаре предзаписи, и на него продолжали бы
  # записываться.
  test "dropping a date from the schedule clears its bookings and cancellations" do
    player = User.create!(email: "dropped-date-player@example.com")
    game = Game.create!(court: courts(:one), user: users(:one), time: "18:00", kind: "game",
                        date: Date.new(2026, 9, 7), occurrence_dates: %w[2026-09-07 2026-09-10 2026-09-14],
                        players_count: 2, prebooking_enabled: true)
    game.prebookings.create!(date: Date.new(2026, 9, 10), slot_index: 1, user: player)
    game.prebooking_cancellations.create!(date: Date.new(2026, 9, 10), user: users(:one))
    kept = game.prebookings.create!(date: Date.new(2026, 9, 7), slot_index: 1, user: player)

    game.update!(occurrence_dates: %w[2026-09-07 2026-09-14])

    assert_empty game.prebookings.reload.where(date: Date.new(2026, 9, 10))
    assert_empty game.prebooking_cancellations.reload
    assert_equal kept, game.prebookings.find_by(date: Date.new(2026, 9, 7), slot_index: 1)
  end

  test "a coach booking on a weekday dropped from the calendar goes with it" do
    coach = User.create!(email: "coach-dropped-weekday@example.com", coach: true)
    game = Game.create!(court: courts(:one), user: users(:one), coach: coach, with_coach: true,
                        recurring: true, recurrence_days: [ 1, 4 ], date: Date.new(2026, 9, 7))
    game.update!(coach_invitation_status: "accepted")

    travel_to Time.zone.local(2026, 9, 7, 9, 0) do
      game.coach_prebookings.create!(coach: coach, date: Date.new(2026, 9, 10))

      # Так снимает день сам календарь: занятие уходит из расписания, а не из
      # правила недельного повтора.
      assert_difference -> { game.coach_prebookings.count }, -1 do
        game.update!(occurrence_dates: [ "2026-09-07" ], recurrence_days: [ 1 ])
      end
    end
  ensure
    coach&.destroy
  end

  # Расписание из самих отмеченных дат: «пн и чт на этой неделе, пн и ср на
  # следующей» в дни недели не укладывается.
  test "an irregular schedule happens exactly on the ticked dates" do
    game = Game.create!(court: courts(:one), user: users(:one), time: "18:00", kind: "game",
                        date: Date.new(2026, 9, 7),
                        occurrence_dates: %w[2026-09-07 2026-09-10 2026-09-14 2026-09-16])

    assert game.series?, "четыре занятия — это серия, даже без галок повтора"
    assert game.occurrence_date?(Date.new(2026, 9, 16))
    assert_not game.occurrence_date?(Date.new(2026, 9, 17)), "четверг следующей недели не отмечали"

    travel_to Time.zone.local(2026, 9, 11, 12, 0) do
      assert_equal Date.new(2026, 9, 14), game.next_date
      assert_equal Date.new(2026, 9, 10), game.previous_occurrence_before_next_date
    end

    # После последней отметки серия заканчивается: повтора у неё нет.
    travel_to Time.zone.local(2026, 9, 17, 12, 0) do
      assert_nil game.next_date
    end

    assert_equal Date.new(2026, 9, 16), game.reload.ends_on
  end

  # Отыгранная серия не должна «находить» занятие там, где его нет: у
  # расписания из отмеченных дат последнее занятие может быть месяц назад.
  test "a finished schedule keeps its last session as the current one" do
    game = Game.create!(court: courts(:one), user: users(:one), time: "18:00", kind: "game",
                        date: Date.new(2026, 9, 7), occurrence_dates: %w[2026-09-07 2026-09-10])

    # 5 октября — понедельник, но серия закончилась 10 сентября.
    travel_to Time.zone.local(2026, 10, 5, 12, 0) do
      assert_equal Date.new(2026, 9, 10), game.display_date_for_show
      assert_nil game.chat_open_until
      assert_not game.participations_reset_due?
    end
  end

  # Записываться в отыгранную серию некуда: горизонт начинался заново с первой
  # даты расписания и предлагал брони на прошедшие занятия.
  test "a finished schedule offers no prebooking dates" do
    game = Game.create!(court: courts(:one), user: users(:one), time: "18:00", kind: "game",
                        date: Date.new(2026, 9, 7), occurrence_dates: %w[2026-09-07 2026-09-10],
                        prebooking_enabled: true)

    travel_to Time.zone.local(2026, 9, 17, 12, 0) do
      assert_empty game.prebooking_horizon_dates(3)
      assert_nil game.prebooking_month
    end
  end

  test "the weekly box carries the schedule on by weekdays" do
    game = Game.create!(court: courts(:one), user: users(:one), time: "18:00", kind: "game", recurring: true,
                        date: Date.new(2026, 9, 7), occurrence_dates: %w[2026-09-07 2026-09-10])

    assert game.occurrence_date?(Date.new(2026, 9, 14))
    assert game.occurrence_date?(Date.new(2026, 9, 17))
    assert_not game.occurrence_date?(Date.new(2026, 9, 15))
    assert_nil game.reload.ends_on, "бесконечная серия не заканчивается"
  end

  test "the monthly box carries the schedule on by days of the month" do
    game = Game.create!(court: courts(:one), user: users(:one), time: "18:00", kind: "game", recurring_monthly: true,
                        date: Date.new(2026, 9, 7), occurrence_dates: %w[2026-09-07 2026-09-10])

    assert game.occurrence_date?(Date.new(2026, 10, 7))
    assert game.occurrence_date?(Date.new(2026, 11, 10))
    assert_not game.occurrence_date?(Date.new(2026, 10, 8))

    travel_to Time.zone.local(2026, 9, 11, 12, 0) do
      assert_equal Date.new(2026, 10, 7), game.next_date
    end
  end

  # Предзапись раньше зависела от галки недельного повтора: у расписания из
  # нескольких дат она нужна ровно так же.
  test "prebooking is allowed for a schedule of several dates" do
    game = Game.new(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7),
                    occurrence_dates: %w[2026-09-07 2026-09-10], prebooking_enabled: true)

    assert game.valid?, game.errors.full_messages.to_sentence
  end

  test "prebooking still needs more than one occurrence" do
    game = Game.new(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7), prebooking_enabled: true)

    assert_not game.valid?
    assert_includes game.errors[:prebooking_enabled], "can be enabled only for repeating (weekly) games"
  end
end
