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
      AUTOMATIC_KEY_PREFIX = "tg:chat:auto".freeze

      class << self
        # Явный выбор пользователя всегда имеет приоритет над автоматическим.
        def start(chat_id, game)
          closes_at = game&.chat_open_until
          return false unless closes_at

          ttl = [ closes_at - Time.current, 1.minute ].max
          Rails.cache.write(key(chat_id), game.id, expires_in: ttl)
          Rails.cache.delete(automatic_key(chat_id))
          true
        end

        # Автоматические сессии сменяют друг друга, но лежат отдельно от явного
        # выбора и поэтому не могут его затереть даже при параллельной записи.
        def start_automatically(chat_id, user, game)
          closes_at = game&.chat_open_until
          return false unless closes_at

          ttl = [ closes_at - Time.current, 1.minute ].max
          Rails.cache.write(automatic_key(chat_id), game.id, expires_in: ttl)

          # Явный выбор мог появиться, пока шла доставка. Он имеет приоритет;
          # автоматический указатель заодно убираем, чтобы тот не ожил после TTL.
          if active_game_for(explicit_game_id(chat_id), user)
            Rails.cache.delete(automatic_key(chat_id))
            return false
          end

          true
        end

        def automatic_start_needed?(chat_id, user, game)
          return false if active_game_for(explicit_game_id(chat_id), user)

          active_game_for(automatic_game_id(chat_id), user)&.id != game.id
        end

        def stop(chat_id)
          Rails.cache.delete(key(chat_id))
          Rails.cache.delete(automatic_key(chat_id))
        end

        def game_id(chat_id)
          explicit_game_id(chat_id) || automatic_game_id(chat_id)
        end

        # Игра, в которую человек пишет прямо сейчас. Протухшие указатели не
        # удаляем здесь: параллельный явный выбор мог уже записать в тот же ключ
        # новое значение. Они безвредны и исчезнут сами по TTL.
        def active_game(chat_id, user)
          return nil unless user

          active_game_for(explicit_game_id(chat_id), user) ||
            active_game_for(automatic_game_id(chat_id), user)
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

        def automatic_key(chat_id)
          "#{AUTOMATIC_KEY_PREFIX}:#{chat_id}"
        end

        private

        def explicit_game_id(chat_id)
          Rails.cache.read(key(chat_id))
        end

        def automatic_game_id(chat_id)
          Rails.cache.read(automatic_key(chat_id))
        end

        def active_game_for(id, user)
          return nil unless id && user

          game = Game.find_by(id: id)
          game if game&.chat_open? && game.team_member_ids.include?(user.id)
        end
      end
    end
  end
end
