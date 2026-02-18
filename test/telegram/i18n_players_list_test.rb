require "test_helper"

class TelegramI18nPlayersListTest < ActiveSupport::TestCase
  KEYS = %i[
    players_list_btn
    players_list_title
    players_list_empty
    player_stats_row
    back_to_game
  ].freeze

  def test_players_list_keys_present_for_ru_and_en
    KEYS.each do |key|
      assert_kind_of String, Telegram::I18n.t(key, locale: :ru, game_id: 12, name: "User", singles: 1, doubles: 2)
      assert_kind_of String, Telegram::I18n.t(key, locale: :en, game_id: 12, name: "User", singles: 1, doubles: 2)
    end
  end
end
