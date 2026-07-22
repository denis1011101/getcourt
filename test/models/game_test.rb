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
end
