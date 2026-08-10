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
      %i[ru en].each do |locale|
        assert_kind_of String,
                       Telegram::I18n.t(key, locale: locale, game_id: 12, name: "User", games: 3, wins: 2, pct: 67)
      end
    end
  end
end
