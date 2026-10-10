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
end
