module Telegram
  # Включение режима чата после вступления в игру. Отдельной джобой, потому что
  # зовётся из колбэка Participation: вступают и с сайта, и по кнопке владельца,
  # и ждать там ответа телеграма нечему. Заодно появляется ретрай — иначе при
  # сетевой ошибке человек остался бы в чате без карточки с кнопками.
  class OpenGameChatJob < ApplicationJob
    queue_as :default

    def perform(game_id, user_id)
      game = Game.find_by(id: game_id)
      user = User.find_by(id: user_id)
      return unless game && user

      Telegram::Chat::Flow.enter(user, game)
    end
  end
end
