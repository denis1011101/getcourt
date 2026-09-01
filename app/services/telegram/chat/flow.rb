module Telegram
  module Chat
    # Вход в режим чата, выбор игры и выход из него.
    #
    # Режим включается только явным нажатием: принятое приглашение само по себе
    # ничего не включает, иначе согласием оказывалось бы бездействие.
    module Flow
      class << self
        def handle_callback(callback)
          data = callback["data"].to_s
          return false unless data.start_with?("chat:")

          chat_id = (callback.dig("message", "chat", "id") || callback.dig("from", "id")).to_s
          cb_id = callback["id"]
          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          unless user
            Telegram::Api.answer_callback(cb_id, t(nil, :user_not_found))
            return true
          end

          case data
          when /\Achat:open:(\d+)\z/
            open(chat_id, user, Game.find_by(id: $1.to_i), cb_id: cb_id)
          when "chat:pick"
            Telegram::Api.answer_callback(cb_id)
            show_picker(chat_id, user)
          when "chat:exit"
            Session.stop(chat_id)
            Telegram::Api.answer_callback(cb_id)
            Telegram::Api.send_simple(chat_id, t(user, :chat_stopped), parse_mode: nil)
          else
            Telegram::Api.answer_callback(cb_id)
          end

          true
        end

        # Кнопка после принятия приглашения. Сам режим не включает.
        def offer(chat_id, game)
          return unless game&.chat_open?

          user = Telegram::Helpers::UserLookup.find_user(chat_id)
          Telegram::Api.send_with_buttons(
            chat_id,
            t(user, :chat_offer, game: Message.game_label(game)),
            [ [ { text: t(user, :chat_open_btn), callback_data: "chat:open:#{game.id}" } ] ],
            parse_mode: nil
          )
        end

        # Команда /chat: одна игра — подтверждаем её, несколько — спрашиваем.
        def start(chat_id, user)
          current = Session.active_game(chat_id, user)
          return show_status(chat_id, user, current) if current

          games = Game.with_open_chat_for(user)
          case games.size
          when 0 then Telegram::Api.send_simple(chat_id, t(user, :chat_none), parse_mode: nil)
          when 1 then open(chat_id, user, games.first)
          else show_picker(chat_id, user, games)
          end
        end

        def show_picker(chat_id, user, games = nil)
          games ||= Game.with_open_chat_for(user)
          if games.empty?
            Telegram::Api.send_simple(chat_id, t(user, :chat_none), parse_mode: nil)
            return
          end

          buttons = games.map { |game| [ { text: Message.game_label(game), callback_data: "chat:open:#{game.id}" } ] }
          Telegram::Api.send_with_buttons(chat_id, t(user, :chat_pick_prompt), buttons, parse_mode: nil)
        end

        def open(chat_id, user, game, cb_id: nil)
          unless game && game.chat_open? && game.team_member_ids.include?(user.id)
            Telegram::Api.answer_callback(cb_id, t(user, :chat_not_available)) if cb_id
            Telegram::Api.send_simple(chat_id, t(user, :chat_not_available), parse_mode: nil) unless cb_id
            return false
          end

          Session.start(chat_id, game)
          Telegram::Api.answer_callback(cb_id) if cb_id
          show_status(chat_id, user, game)
          true
        end

        def stop(chat_id, user)
          Session.stop(chat_id)
          Telegram::Api.send_simple(chat_id, t(user, :chat_stopped), parse_mode: nil)
        end

        # Индикатор: в какую игру уходят сообщения и кто их увидит.
        def show_status(chat_id, user, game)
          text = t(user, :chat_started, game: Message.game_label(game), count: game.chat_members.count)
          buttons = [ [
            { text: t(user, :chat_switch_btn), callback_data: "chat:pick" },
            { text: t(user, :chat_exit_btn), callback_data: "chat:exit" }
          ] ]
          Telegram::Api.send_with_buttons(chat_id, text, buttons, parse_mode: nil)
        end

        private

        def t(user, key, **args)
          Telegram::I18n.t(key, locale: Telegram::I18n.locale_for(user), **args)
        end
      end
    end
  end
end
