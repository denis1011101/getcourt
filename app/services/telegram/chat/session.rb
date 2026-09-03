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
      CARD_LOCK_PREFIX = "tg:chat:card".freeze
      # Замок держим минуту: он нужен ровно против одновременных колбэков.
      # «Видел ли человек карточку раньше» отвечает automatic_start_needed?, и
      # долгий замок только пережил бы переключение на другую игру и не дал бы
      # прислать карточку при возвращении в эту.
      CARD_LOCK_TTL = 1.minute

      class << self
        # Явный выбор пользователя всегда имеет приоритет над автоматическим.
        def start(chat_id, game)
          closes_at = game&.chat_open_until
          return false unless closes_at

          Rails.cache.write(key(chat_id), game.id, expires_in: ttl(closes_at))
          Rails.cache.delete(automatic_key(chat_id))
          true
        end

        # Автоматические сессии сменяют друг друга, но лежат отдельно от явного
        # выбора и поэтому не могут его затереть даже при параллельной записи.
        def start_automatically(chat_id, user, game)
          closes_at = game&.chat_open_until
          return false unless closes_at

          Rails.cache.write(automatic_key(chat_id), game.id, expires_in: ttl(closes_at))

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

        # Право прислать карточку: вступают в состав параллельно, и два колбэка
        # успевают увидеть пустой указатель оба. unless_exist отдаёт false тому,
        # кто пришёл вторым, — атомарно, на стороне кеша, а не в проверке перед
        # записью. Открытие чата этот замок не решает и не должен: сначала
        # указатель, потом карточка.
        def claim_card(chat_id, game)
          return false if game.nil?

          Rails.cache.write(card_lock_key(chat_id, game.id), true, expires_in: CARD_LOCK_TTL, unless_exist: true)
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

        def card_lock_key(chat_id, game_id)
          "#{CARD_LOCK_PREFIX}:#{chat_id}:#{game_id}"
        end

        private

        # Указатель живёт ровно до закрытия чата, но не меньше минуты: за
        # секунды до сброса писать всё ещё можно.
        def ttl(closes_at)
          [ closes_at - Time.current, 1.minute ].max
        end

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
