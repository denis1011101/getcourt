require "test_helper"

class Telegram::Chat::MessageTest < ActiveSupport::TestCase
  test "label shows the nearest date of a weekly game in the locale format" do
    court = Court.create!(name: "Label Court", city_name: "Yekaterinburg")
    owner = User.create!(email: "chat_label_#{SecureRandom.hex(4)}@example.com", name: "Owner")
    game = Game.create!(court: court, user: owner, date: 3.weeks.ago.to_date, recurring: true)

    assert_equal "##{game.id} Yekaterinburg #{I18n.l(game.next_date, format: :telegram, locale: 'ru')}",
                 Telegram::Chat::Message.game_label(game)
    assert_equal "##{game.id} Yekaterinburg #{I18n.l(game.next_date, format: :telegram, locale: 'en')}",
                 Telegram::Chat::Message.game_label(game, locale: "en")
  end
end
