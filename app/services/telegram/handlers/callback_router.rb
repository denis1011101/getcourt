module Telegram
  module Handlers
    class CallbackRouter
      # вернёт true если маршрут обработан
      def self.route(callback_query)
        data = (callback_query["data"] || "").to_s
        return false if data.empty?

        # [bot-menu-off] Отключено намеренно: пользуемся сайтом getcourt.co,
        # бот оставлен только для приглашений и карточки игры.
        # Раскомментировать, если решим вернуть функциональность в бот.
        # if data.match?(/\A(menu:courts|court:|create_game_from_court)/)
        #   Telegram::Handlers::CourtsCallbackHandler.process(callback_query)
        #   return true
        # end

        if data.start_with?("chat:")
          Telegram::Chat::Flow.handle_callback(callback_query)
          return true
        end

        if data.start_with?("game:")
          Telegram::Handlers::GamesCallbackHandler.process(callback_query)
          return true
        end

        # [bot-menu-off] Отключено намеренно: пользуемся сайтом getcourt.co,
        # бот оставлен только для приглашений и карточки игры.
        # Раскомментировать, если решим вернуть функциональность в бот.
        # if data.match?(/\A(menu:tournaments|menu:my_tournaments|tournament:)/)
        #   Telegram::Handlers::TournamentsCallbackHandler.process(callback_query)
        #   return true
        # end
        # if data.match?(/\Acoach:show:/)
        #   cb = Telegram::Helpers::CallbackData.parse(callback_query)
        #   coach_id = data.split(":")[2].to_i
        #   Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
        #   Telegram::Handlers::FindCoachHandler.show_coach(cb.chat_id, coach_id, message_id: cb.message_id)
        #   return true
        # end
        # if data.match?(/\Atg_fill(?::|_)/)
        #   Telegram::Flows::StatsFlow.handle_callback(callback_query)
        #   return true
        # end
        # if data.match?(/\Atg_score(?::|_)/)
        #   Telegram::Flows::StatsScoreFlow.handle_callback(callback_query)
        #   return true
        # end
        # if data.match?(/\Aai:/)
        #   Telegram::Flows::AiAssistantFlow.handle_callback(callback_query)
        #   return true
        # end

        false
      rescue => e
        Rails.logger.error "[Telegram::Handlers::CallbackRouter] #{e.class}: #{e.message}"
        false
      end
    end
  end
end
