require "test_helper"

class PrebookingsControllerTest < ActionDispatch::IntegrationTest
  test "should redirect book when not authenticated" do
    post book_game_prebooking_url(games(:one), prebookings(:one))
    assert_redirected_to new_session_path
  end

  test "should redirect cancel when not authenticated" do
    post cancel_game_prebooking_url(games(:one), prebookings(:one))
    assert_redirected_to new_session_path
  end
  test "more lazily creates slots for expanded horizon" do
    game = Game.create!(
      court: courts(:one),
      user: users(:one),
      date: Date.current,
      recurring: true,
      prebooking_enabled: true,
      players_count: 2
    )

    users(:two).update!(email: "expanded-prebooking@example.com")
    post session_url, params: { email: users(:two).email }

    assert_difference -> { game.prebookings.count }, 12 do
      get more_game_prebookings_url(game, horizon: 6)
    end

    assert_response :success
    assert_select "turbo-frame#prebookings-#{game.id}"
  end

  test "more renders a card per date and shows who took a slot" do
    owner = users(:one)
    owner.update!(email: "prebooking-calendar@example.com", name: "Calendar Owner")
    game = recurring_prebooking_game(owner)

    post session_url, params: { email: owner.email }
    get more_game_prebookings_url(game, horizon: 3)

    assert_response :success
    assert_select "[data-testid=?]", "prebooking-day", 3

    post book_game_prebooking_url(game, first_slot(game))
    get more_game_prebookings_url(game, horizon: 3)

    assert_select "[data-testid=?]", "prebooking-day" do |cards|
      assert_match owner.name, cards.first.to_s
      assert_match "1/2", cards.first.to_s
    end
  end

  test "more draws a month grid where only game dates lead to their card" do
    owner = users(:one)
    owner.update!(email: "prebooking-grid@example.com")
    game = recurring_prebooking_game(owner)

    post session_url, params: { email: owner.email }
    get more_game_prebookings_url(game, horizon: 3)

    assert_select "[data-testid=?]", "prebooking-calendar"
    assert_select "[data-testid=?]", "calendar-day", { minimum: 28 }

    game_date = game.prebooking_candidate_dates(3).first
    assert_select "a[data-testid=?][href=?]", "calendar-day", "#prebooking-#{game_date.iso8601}"
    assert_select "#prebooking-#{game_date.iso8601}"

    # Соседний день игрой не занят, поэтому он просто серая клетка без ссылки.
    assert_select "a[href=?]", "#prebooking-#{(game_date + 1).iso8601}", 0
    assert_match I18n.t("games.prebookings.legend_no_game"), response.body
  end

  test "more shows a cancelled date without booking buttons" do
    owner = users(:one)
    owner.update!(email: "prebooking-cancelled-date@example.com")
    game = recurring_prebooking_game(owner)

    post session_url, params: { email: owner.email }
    get more_game_prebookings_url(game, horizon: 3)

    # Отменяем не ближайшую дату, а следующую: ближайшая после отмены уезжает
    # из горизонта вместе с самим занятием.
    date = game.prebooking_candidate_dates(3).second
    slot = game.prebookings.find_by!(date: date, slot_index: 1)
    PrebookingCancellation.create!(game: game, user: owner, date: date)

    get more_game_prebookings_url(game, horizon: 3)

    assert_select "[data-testid=?]", "prebooking-day" do |cards|
      assert_match I18n.t("games.prebookings.cancelled"), cards[1].to_s
    end
    assert_select "form[action=?]", book_game_prebooking_path(game, slot), 0
  end

  private

  def recurring_prebooking_game(owner)
    Game.create!(
      court: courts(:one),
      user: owner,
      date: Date.current,
      recurring: true,
      prebooking_enabled: true,
      players_count: 2
    )
  end

  def first_slot(game)
    game.prebookings.find_by!(date: game.prebooking_candidate_dates(3).first, slot_index: 1)
  end
end
