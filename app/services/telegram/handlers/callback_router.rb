module Telegram
  module Handlers
    class CallbackRouter
      # вернёт true если маршрут обработан
      def self.route(callback_query)
        data = (callback_query["data"] || "").to_s
        return false if data.empty?

        if data.match?(/\A(menu:courts|court:|create_game_from_court)/)
          Telegram::Handlers::CourtsCallbackHandler.process(callback_query)
          return true
        end

        if data.match?(/\A(menu:games|game:|prebook:)/)
          Telegram::Handlers::GamesCallbackHandler.process(callback_query)
          return true
        end

        # TG statistics flow (callbacks)
        if data.match?(/\Atg_fill(?::|_)/)
          Telegram::Flows::StatsFlow.handle_callback(callback_query)
          return true
        end

        # TG game result flow (callbacks)
        if data.match?(/\Atg_score(?::|_)/)
          Telegram::Flows::StatsScoreFlow.handle_callback(callback_query)
          return true
        end

        false
      rescue => e
        Rails.logger.error "[Telegram::Handlers::CallbackRouter] #{e.class}: #{e.message}"
        false
      end
    end
  end
end
