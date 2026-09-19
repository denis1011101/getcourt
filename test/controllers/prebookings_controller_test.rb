require "test_helper"

class PrebookingsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "should redirect book when not authenticated" do
    post book_game_prebooking_url(games(:one), prebookings(:one))
    assert_redirected_to new_session_path
  end

  test "should redirect cancel when not authenticated" do
    post cancel_game_prebooking_url(games(:one), prebookings(:one))
    assert_redirected_to new_session_path
  end
  # Слот мог остаться от даты, которую убрали из расписания: игры в этот день
  # уже не будет, и записываться туда не на что.
  test "booking a date outside the schedule is refused" do
    game = Game.create!(
      court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7), time: "18:00",
      occurrence_dates: %w[2026-09-07 2026-09-10], players_count: 2, prebooking_enabled: true
    )
    stale = game.prebookings.create!(date: Date.new(2026, 9, 14), slot_index: 1)

    users(:two).update!(email: "outside-schedule@example.com")
    post session_url, params: { email: users(:two).email }
    post book_game_prebooking_url(game, stale)

    assert_response :forbidden
    assert_nil stale.reload.user_id
  end

  # Сброс на занятие прошёл, состав собран — бронь на эту дату джоба уже не
  # заберёт, так что и с открытой заранее страницы её принимать нельзя.
  test "booking a date whose roster is already assembled is refused" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7), recurring: true, players_count: 2, prebooking_enabled: true)
    slot = game.prebookings.create!(date: Date.new(2026, 9, 14), slot_index: 1)
    game.mark_participations_reset!(Date.new(2026, 9, 14))

    users(:two).update!(email: "roster-assembled@example.com")
    post session_url, params: { email: users(:two).email }
    travel_to Time.zone.local(2026, 9, 12, 12, 0) do
      post book_game_prebooking_url(game, slot)
    end

    assert_response :forbidden
    assert_nil slot.reload.user_id
  end

  # Джоба переносит в состав только одобренные заявки; ждавшую одобрения после
  # сброса одобрять поздно — подтверждение придёт, а места в составе не будет.
  test "approving a request for a date whose roster is already assembled is refused" do
    game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7), recurring: true, players_count: 2, prebooking_enabled: true)
    request = game.prebookings.create!(date: Date.new(2026, 9, 14), slot_index: 1, user: users(:two), status: "pending")
    game.mark_participations_reset!(Date.new(2026, 9, 14))

    users(:one).update!(email: "roster-approve@example.com")
    post session_url, params: { email: users(:one).email }
    assert_no_enqueued_emails do
      post approve_game_prebooking_url(game, request)
    end

    assert_response :forbidden
    assert_equal "pending", request.reload.status
  end

  # Серия по понедельникам с 7 сентября; смотрим 8-го: в сентябре впереди 14,
  # 21 и 28, в октябре — 5, 12, 19 и 26. Даты прибиты: число карточек в месяце
  # зависит от календаря.
  SEPTEMBER = Time.zone.local(2026, 9, 8, 12, 0)

  test "more creates the slots of the month it shows" do
    travel_to SEPTEMBER do
      game = recurring_prebooking_game(users(:one))
      users(:two).update!(email: "expanded-prebooking@example.com")
      post session_url, params: { email: users(:two).email }

      # Четыре октябрьских понедельника по два слота.
      assert_difference -> { game.prebookings.count }, 8 do
        get more_game_prebookings_url(game, month: "2026-10")
      end

      assert_response :success
      assert_select "turbo-frame#prebookings-#{game.id}"
      assert_select "[data-testid=?]", "prebooking-month", text: /October 2026/
    end
  end

  test "more renders a card per date and shows who took a slot" do
    travel_to SEPTEMBER do
      owner = users(:one)
      owner.update!(email: "prebooking-calendar@example.com", name: "Calendar Owner")
      game = recurring_prebooking_game(owner)

      post session_url, params: { email: owner.email }
      get more_game_prebookings_url(game, month: "2026-09")

      assert_response :success
      assert_select "[data-testid=?]", "prebooking-day", 3

      post book_game_prebooking_url(game, first_slot(game))
      get more_game_prebookings_url(game, month: "2026-09")

      assert_select "[data-testid=?]", "prebooking-day" do |cards|
        assert_match owner.name, cards.first.to_s
        assert_match "1/2", cards.first.to_s
      end
    end
  end

  test "more draws a month grid where only game dates lead to their card" do
    travel_to SEPTEMBER do
      owner = users(:one)
      owner.update!(email: "prebooking-grid@example.com")
      game = recurring_prebooking_game(owner)

      post session_url, params: { email: owner.email }
      get more_game_prebookings_url(game, month: "2026-09")

      assert_select "[data-testid=?]", "prebooking-calendar"
      assert_select "[data-testid=?]", "calendar-day", { minimum: 28 }

      game_date = game.prebooking_dates_in(Date.new(2026, 9, 1)).first
      assert_select "a[data-testid=?][href=?]", "calendar-day", "#prebooking-#{game_date.iso8601}"
      assert_select "#prebooking-#{game_date.iso8601}"

      # Соседний день игрой не занят, поэтому он просто серая клетка без ссылки.
      assert_select "a[href=?]", "#prebooking-#{(game_date + 1).iso8601}", 0
      assert_match I18n.t("games.prebookings.legend_no_game"), response.body
    end
  end

  # Листание — стрелками в шапке календаря, как в форме игры: назад от месяца
  # ближайшего занятия нельзя, вперёд — до конца серии или на год.
  test "more pages through months with arrows inside the frame" do
    travel_to SEPTEMBER do
      owner = users(:one)
      owner.update!(email: "prebooking-arrows@example.com")
      game = recurring_prebooking_game(owner)

      post session_url, params: { email: owner.email }
      get more_game_prebookings_url(game, month: "2026-09")

      assert_select "[data-testid=?]", "prebooking-previous-month", 0
      assert_select "a[data-testid=?][href=?]", "prebooking-next-month", more_game_prebookings_path(game, month: "2026-10")

      # За год вперёд не пускаем: просьба показать 2030-й возвращает последний
      # доступный месяц.
      get more_game_prebookings_url(game, month: "2030-01")

      assert_select "[data-testid=?]", "prebooking-month", text: /August 2027/
      assert_select "[data-testid=?]", "prebooking-next-month", 0
      assert_select "a[data-testid=?][href=?]", "prebooking-previous-month", more_game_prebookings_path(game, month: "2027-07")
    end
  end

  test "more shows a cancelled date without booking buttons" do
    travel_to SEPTEMBER do
      owner = users(:one)
      owner.update!(email: "prebooking-cancelled-date@example.com")
      game = recurring_prebooking_game(owner)

      post session_url, params: { email: owner.email }
      get more_game_prebookings_url(game, month: "2026-09")

      date = game.prebooking_dates_in(Date.new(2026, 9, 1)).second
      slot = game.prebookings.find_by!(date: date, slot_index: 1)
      PrebookingCancellation.create!(game: game, user: owner, date: date)

      get more_game_prebookings_url(game, month: "2026-09")

      assert_select "[data-testid=?]", "prebooking-day" do |cards|
        assert_match I18n.t("games.prebookings.cancelled"), cards[1].to_s
      end
      assert_select "form[action=?]", book_game_prebooking_path(game, slot), 0
    end
  end

  # Организатор записывает человека сам: договорились вне сайта. Заявку
  # подтверждать нечего, а человек узнаёт о записи из уведомления.
  test "assign books a chosen player into the slot and tells them" do
    travel_to SEPTEMBER do
      owner = users(:one)
      owner.update!(email: "prebooking-assign@example.com")
      game = recurring_prebooking_game(owner)
      player = User.create!(email: "prebooking-assigned@example.com", name: "Assigned Player", notification_channel: "email", locale: "en")

      post session_url, params: { email: owner.email }
      slot = first_slot(game)

      assert_enqueued_emails 1 do
        post assign_game_prebooking_url(game, slot), params: { user_id: player.id }
      end

      assert_redirected_to game_path(game)
      slot.reload
      assert_equal player, slot.user
      assert slot.approved?
      assert_equal I18n.t("games.prebookings.assigned", name: "Assigned Player (prebooking-assigned@example.com)"), flash[:notice]
    end
  end

  test "assign is for the organizer or an admin only" do
    travel_to SEPTEMBER do
      game = recurring_prebooking_game(users(:one))
      stranger = users(:two)
      stranger.update!(email: "prebooking-assign-stranger@example.com")
      player = User.create!(email: "prebooking-assign-target@example.com", name: "Target")

      post session_url, params: { email: stranger.email }
      slot = first_slot(game)
      post assign_game_prebooking_url(game, slot), params: { user_id: player.id }

      assert_response :forbidden
      assert_nil slot.reload.user_id
    end
  end

  test "assign refuses a taken slot, a second slot on the same date and an unknown player" do
    travel_to SEPTEMBER do
      owner = users(:one)
      owner.update!(email: "prebooking-assign-twice@example.com")
      game = recurring_prebooking_game(owner)
      player = User.create!(email: "prebooking-assign-twice-player@example.com", name: "Twice")

      post session_url, params: { email: owner.email }
      slot = first_slot(game)
      second = game.prebookings.find_by!(date: slot.date, slot_index: 2)

      post assign_game_prebooking_url(game, slot), params: { user_id: player.id }
      post assign_game_prebooking_url(game, slot), params: { user_id: users(:two).id }
      assert_equal "Slot already taken.", flash[:alert]
      assert_equal player, slot.reload.user

      post assign_game_prebooking_url(game, second), params: { user_id: player.id }
      assert_equal I18n.t("games.prebookings.assign_already_booked", name: "Twice (prebooking-assign-twice-player@example.com)"), flash[:alert]
      assert_nil second.reload.user_id

      post assign_game_prebooking_url(game, second), params: { user_id: 0 }
      assert_equal I18n.t("games.prebookings.assign_no_user"), flash[:alert]
      assert_nil second.reload.user_id
    end
  end

  # Поле записи видит только организатор, и только пока в дне есть свободный
  # слот: ведёт оно в первый свободный.
  test "more shows the organizer a player picker for the first free slot" do
    travel_to SEPTEMBER do
      owner = users(:one)
      owner.update!(email: "prebooking-picker@example.com")
      game = recurring_prebooking_game(owner)

      post session_url, params: { email: owner.email }
      get more_game_prebookings_url(game, month: "2026-09")

      slot = first_slot(game)
      assert_select "form[data-testid=?][action=?]", "prebooking-assign", assign_game_prebooking_path(game, slot) do
        assert_select "[data-testid=?] input[name=user_id]", "user-picker"
      end

      post assign_game_prebooking_url(game, slot), params: { user_id: users(:two).id }
      get more_game_prebookings_url(game, month: "2026-09")

      second = game.prebookings.find_by!(date: slot.date, slot_index: 2)
      assert_select "form[data-testid=?][action=?]", "prebooking-assign", assign_game_prebooking_path(game, second)

      users(:two).update!(email: "prebooking-picker-guest@example.com")
      post session_url, params: { email: users(:two).email }
      get more_game_prebookings_url(game, month: "2026-09")

      assert_select "form[data-testid=?]", "prebooking-assign", 0
    end
  end

  private

  def recurring_prebooking_game(owner)
    Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.new(2026, 9, 7),
      recurring: true,
      prebooking_enabled: true,
      players_count: 2
    )
  end

  # Слоты заводятся лениво, когда месяц кто-то открыл, — здесь заводим сами.
  def first_slot(game)
    dates = game.prebooking_dates_in(Date.new(2026, 9, 1))
    game.ensure_prebookings_for_dates(dates)
    game.prebookings.find_by!(date: dates.first, slot_index: 1)
  end
end
