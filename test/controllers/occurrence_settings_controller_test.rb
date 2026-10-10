require "test_helper"

class OccurrenceSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7), recurring: true,
                         kind: "training", players_count: 4, prebooking_enabled: true)
  end

  test "organizer sets kind, coach and court for one date and resets it" do
    users(:one).update!(email: "occurrence-owner@example.com")
    post session_url, params: { email: users(:one).email }

    post game_occurrence_settings_url(@game, date: "2026-09-14"),
         params: { occurrence_setting: { kind: "training", with_coach: "1", court_id: courts(:two).id, players_count: "2" } }
    setting = @game.occurrence_settings.find_by!(date: Date.new(2026, 9, 14))
    assert_equal [ nil, true, courts(:two).id, 2 ], [ setting.kind, setting.with_coach, setting.court_id, setting.players_count ]

    post game_occurrence_settings_url(@game, date: "2026-09-14"), params: { occurrence_setting: { court_id: "none" } }
    assert_equal [ nil, true ], setting.reload.then { [ it.court_id, it.without_court ] }

    post game_occurrence_settings_url(@game, date: "2026-09-14"), params: { reset: "1" }
    assert_not @game.occurrence_settings.exists?
  end

  test "other players cannot change the date" do
    users(:two).update!(email: "occurrence-stranger@example.com")
    post session_url, params: { email: users(:two).email }

    post game_occurrence_settings_url(@game, date: "2026-09-14"), params: { occurrence_setting: { kind: "game" } }

    assert_response :forbidden
    assert_not @game.occurrence_settings.exists?
  end

  # Форма шлёт тип и галку тренера всегда: если всё как в серии, пустой
  # записи остаться не должно.
  test "submitting the series defaults leaves no setting behind" do
    users(:one).update!(email: "occurrence-defaults@example.com")
    post session_url, params: { email: users(:one).email }

    post game_occurrence_settings_url(@game, date: "2026-09-14"),
         params: { occurrence_setting: { kind: "training", with_coach: "0", court_id: "", players_count: "" } }

    assert_not @game.occurrence_settings.exists?
  end

  test "session form renders without missing translations" do
    users(:one).update!(email: "occurrence-i18n@example.com")
    post session_url, params: { email: users(:one).email }

    travel_to Time.zone.local(2026, 9, 1, 12, 0) do
      get game_url(@game)
    end

    assert_response :success
    assert_select "[data-testid=occurrence-setting]"
    assert_no_match(/translation missing/i, response.body)
  end

  # Свои места на дату: в серии на двоих занятие на четверых пускает третьего.
  test "booking honours the per-date capacity" do
    series = Game.create!(court: courts(:one), user: users(:one), date: Date.new(2026, 9, 7), recurring: true,
                          players_count: 2, prebooking_enabled: true)
    date = Date.new(2026, 9, 21)
    series.occurrence_settings.create!(date: date, players_count: 4)
    series.prebookings.where(date: date, slot_index: [ 1, 2 ]).each_with_index { |slot, i| slot.update!(user: [ users(:one), users(:two) ][i]) }
    third = series.prebookings.find_by!(date: date, slot_index: 3)

    booker = User.create!(email: "per-date-capacity@example.com", name: "Third")
    post session_url, params: { email: booker.email }
    travel_to Time.zone.local(2026, 9, 1, 12, 0) do
      post book_game_prebooking_url(series, third)
    end

    assert_not_equal 403, response.status
    assert third.reload.user_id.present?
  end
end
