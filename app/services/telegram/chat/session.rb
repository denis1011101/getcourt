module Telegram
  module Chat
    # Указатель «куда сейчас пишет человек». Лежит в кеше намеренно: потеря
    # указателя безопасна — бот просто снова спросит, в какую игру писать.
    # Опасен был бы неявный фолбэк, поэтому его здесь нет: нет указателя —
    # нет и рассылки.
    #
    # Право писать указатель не даёт: участие и открытость чата
    # перепроверяются на каждом сообщении, потому что человек мог выйти из
    # игры уже после того, как включил режим.
    module Session
      KEY_PREFIX = "tg:chat:active".freeze

      class << self
        def start(chat_id, game)
          closes_at = game&.chat_open_until
          return false unless closes_at

          ttl = [ closes_at - Time.current, 1.minute ].max
          Rails.cache.write(key(chat_id), game.id, expires_in: ttl)
          true
        end

        def stop(chat_id)
          Rails.cache.delete(key(chat_id))
        end

        def game_id(chat_id)
          Rails.cache.read(key(chat_id))
        end

        # Игра, в которую человек пишет прямо сейчас, — или nil, и тогда режим
        # гасится: игра прошла, человека вывели из состава, игру удалили.
        def active_game(chat_id, user)
          id = game_id(chat_id)
          return nil unless id && user

          game = Game.find_by(id: id)
          return game if game&.chat_open? && game.team_member_ids.include?(user.id)

          stop(chat_id)
          nil
        end

        # Человек вышел из игры (или его вывели) — гасим режим, но только если
        # он писал именно в эту игру.
        def stop_for(user, game)
          chat_id = user&.telegram_chat_id
          return false if chat_id.blank? || game.nil?
          return false unless game_id(chat_id).to_i == game.id

          stop(chat_id)
          true
        end

        def key(chat_id)
          "#{KEY_PREFIX}:#{chat_id}"
        end
      end
    end
  end
end
