module Telegram
  module Chat
    # Входящее сообщение человека, у которого включён режим чата.
    module Relay
      # Telegram переотдаёт неподтверждённые обновления после рестарта поллера
      # (@offset живёт только в памяти процесса), а деплой ходит по крону. Без
      # этой отметки каждый рестарт рассылал бы чужие сообщения повторно.
      SEEN_TTL = 12.hours

      class << self
        # true — сообщение забрал чат, дальше по цепочке разбирать не нужно.
        def handle_message(message)
          chat_id = message.dig("chat", "id") || message.dig("from", "id")
          return false if chat_id.blank?

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          return false unless user

          game = Session.active_game(chat_id, user)
          return false unless game

          return true if duplicate?(chat_id, message["message_id"])

          media = Media.from(message)
          # У вложения текст лежит в подписи, а не в text.
          body = (media ? message["caption"] : message["text"]).to_s.strip
          if media.nil? && body.blank?
            # Гео, контакт, опрос — молча проглотить нельзя, человек ждёт, что
            # присланное увидят.
            Telegram::Api.send_simple(chat_id, t(user, :chat_unsupported), parse_mode: nil)
            return true
          end

          Telegram::RelayChatMessageJob.perform_later(game.id, user.id, body, media)
          true
        end

        private

        def duplicate?(chat_id, message_id)
          return false if message_id.blank?

          key = "tg:chat:seen:#{chat_id}:#{message_id}"
          !Rails.cache.write(key, true, expires_in: SEEN_TTL, unless_exist: true)
        end

        def t(user, key, **args)
          Telegram::I18n.t(key, locale: Telegram::I18n.locale_for(user), **args)
        end
      end
    end
  end
end
