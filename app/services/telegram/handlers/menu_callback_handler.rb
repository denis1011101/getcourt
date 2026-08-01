module Telegram
  module Handlers
    class MenuCallbackHandler
      def self.process(callback_query)
        cb = Telegram::Helpers::CallbackData.parse(callback_query)
        return false if cb.data.empty? || cb.chat_id.blank?

        # [bot-menu-off] Отключено намеренно: пользуемся сайтом getcourt.co,
        # бот оставлен только для приглашений и карточки игры.
        # Раскомментировать, если решим вернуть функциональность в бот.
        # case cb.data
        # when "menu:main"
        #   Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
        #   Telegram::Handlers::MenuHandler.menu(cb.chat_id, message_id: cb.message_id) rescue nil
        #   true
        # when "menu:search"
        #   Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
        #   Telegram::Handlers::SearchHandler.menu(cb.chat_id) rescue nil
        #   true
        # when /\Amenu:find_coach(?::page:(\d+))?\z/
        #   page = ($1 || 1).to_i
        #   Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
        #   Telegram::Handlers::FindCoachHandler.list_page(cb.chat_id, page, message_id: cb.message_id) rescue nil
        #   true
        # when /\Amenu:games_need_players(?::page:(\d+))?\z/
        #   page = ($1 || 1).to_i
        #   Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
        #   Telegram::Handlers::GamesNeedPlayersHandler.list_page(cb.chat_id, page, message_id: cb.message_id) rescue nil
        #   true
        # when /\Amenu:rating(?::page:(\d+))?\z/
        #   page = ($1 || 1).to_i
        #   Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
        #   Telegram::Handlers::RatingHandler.list_page(cb.chat_id, page, message_id: cb.message_id) rescue nil
        #   true
        # when "menu:tennis_life"
        #   Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
        #   Telegram::Handlers::TennisLifeMenuHandler.show(cb.chat_id, message_id: cb.message_id) rescue nil
        #   true
        # when "menu:ai_assistant"
        #   Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
        #   Telegram::Handlers::AiAssistantHandler.show(cb.chat_id, message_id: cb.message_id) rescue nil
        #   true
        # when /\Amenu:my_games(?::page:(\d+))?\z/
        #   page = ($1 || 1).to_i
        #   Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
        #   Telegram::Handlers::GamesHandler.my_games_page(cb.chat_id, page, message_id: cb.message_id) rescue nil
        #   true
        # when /\Amenu:my_tournaments(?::page:(\d+))?\z/
        #   page = ($1 || 1).to_i
        #   Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
        #   Telegram::Handlers::TournamentsHandler.my_tournaments_page(cb.chat_id, page, message_id: cb.message_id) rescue nil
        #   true
        # end
        false
      rescue => e
        Rails.logger.error "[Telegram::Handlers::MenuCallbackHandler] #{e.class}: #{e.message}"
        false
      end
    end
  end
end
