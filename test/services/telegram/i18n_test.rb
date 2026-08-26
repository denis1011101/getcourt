require "test_helper"

class Telegram::I18nTest < ActiveSupport::TestCase
  LIVE_KEYS = %i[
    back_to_game bot_moved_to_site coach_label coach_with court_label game_not_found guest_badge join leave
    open_in_browser owner player_stats_row players players_list_btn players_list_empty players_list_title request_sent
    request_to_join unknown_action weather_label spot_left spots_left spots_left_few sport_tennis sport_padel
    sport_table_tennis sport_squash invitation_title invitation_join invitation_decline invite_declined
    invite_declined_user invite_declined_owner invite_cancelled only_game_owner_can_invite invite_handles_invalid
    invitations_sent invitations_processed invite_not_found invite_skipped_self game_or_user_not_found joined_game
    join_request_already_sent already_joined_game join_request_sent join_failed approve_btn reject_btn
    join_request_owner_text not_a_participant left_game join_request_pending participation_request_not_found
    participation_no_permission participation_approved participation_rejected user_accepted user_rejected
    participation_request_approved_user participation_request_rejected_user participation_joined participation_left
    participation_requested participation_removed participation_guest_added participation_notification today tomorrow reminder_head
    reminder_head_training program_label coach_with_name coach_with_names
    training_invitation_title
    participants_label prebooking_request dates_label approve_all reject_all prebooking_request_approved_user
    prebooking_request_rejected_user post_game_stats_reminder fill_stats game_did_not_happen telegram_connected registration_invalid
    delete_game_no_permission user_fallback unknown_court game_invitation_from sport_any
    skill_any skill_beginner skill_intermediate skill_advanced skill_pro urgent_search_notification
    admin_partnership admin_court_pending admin_court_suggestion comment_label
  ].freeze

  test "returns Spanish translations" do
    assert_equal "Tiempo: ☀️ 24°", Telegram::I18n.t(:weather_label, locale: "es", value: "☀️ 24°")
    assert_equal "1 plaza libre", Telegram::I18n.spots_left_text(1, locale: "es")
    assert_equal "2 plazas libres", Telegram::I18n.spots_left_text(2, locale: "es")
  end

  test "falls back to English for a missing Spanish key" do
    assert_equal I18n.t("telegram.main_menu", locale: :en), Telegram::I18n.t(:main_menu, locale: "es")
  end

  test "all live keys exist in every supported dictionary" do
    Telegram::I18n::LOCALES.each do |locale|
      missing = LIVE_KEYS.reject { |key| I18n.exists?("telegram.#{key}", locale) }

      assert_empty missing, "Missing #{locale} Telegram translations: #{missing.join(', ')}"
    end
  end

  test "normalizes supported Telegram language codes" do
    assert_equal "es", Telegram::I18n.locale_from_language_code("es-ES")
    assert_nil Telegram::I18n.locale_from_language_code("de-DE")
  end

  test "localizes game sport and date" do
    game = games(:one)
    game.update_columns(date: Date.new(2026, 8, 2), recurring: false, sport: "Table Tennis")

    assert_equal "Tenis de mesa", Telegram::Helpers::GameFormatting.game_title(game, locale: "es")
    assert_includes Telegram::Helpers::GameFormatting.game_datetime(game, locale: "en"), "08/02/2026"
  end

  test "keeps the Rails short format separate from Telegram formats" do
    registered_at = Time.zone.local(2026, 8, 2, 23, 54)

    assert_equal "02 Aug 23:54", I18n.l(registered_at, format: :short, locale: :en)
    assert_equal "11:54 PM", Telegram::Helpers::GameFormatting.format_time_hhmm(registered_at, locale: "en")
  end

  test "lets the raw template through when an interpolation argument is missing" do
    I18n.backend.store_translations(:en, telegram: { i18n_test_plain: "hi %{who} and %{other}" })

    assert_equal "hi %{who} and %{other}", Telegram::I18n.t(:i18n_test_plain, locale: "en", who: "a")
    assert_equal "i18n_test_absent", Telegram::I18n.t(:i18n_test_absent, locale: "en", who: "a")
  end

  test "keeps an unknown sport readable" do
    game = games(:one)
    game.update_columns(sport: "Badminton")

    assert_equal "Badminton", Telegram::Helpers::GameFormatting.game_title(game, locale: "ru")
  end
end
