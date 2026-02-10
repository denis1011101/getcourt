module Telegram
  module Handlers
    class GamesCallbackHandler
      def self.process(callback_query)
        cb = Telegram::Helpers::CallbackData.parse(callback_query)
        return false unless cb.chat_id.present? && cb.data.present?

        Rails.logger.debug "[Telegram::Handlers::GamesCallbackHandler] data=#{cb.data.inspect} chat_id=#{cb.chat_id}"

        # pagination/menu handled by GamesHandler
        if cb.data =~ /\Amenu:games:page:(\d+)\z/
          page = $1.to_i
          Telegram::Handlers::GamesHandler.list_page(cb.chat_id, page, message_id: cb.message_id) rescue nil
          Rails.logger.debug "[Telegram::Handlers::GamesCallbackHandler] handled by GamesHandler.list_page page=#{page}"
          return true
        end

        # delegate all game-related callbacks to GamesFlow
        if cb.data.start_with?("game:") || cb.data.start_with?("prebook:") || cb.data.start_with?("create_game_from_court")
          Rails.logger.debug "[Telegram::Handlers::GamesCallbackHandler] delegating to GamesFlow.handle_callback data=#{cb.data.inspect}"
          begin
            result = Telegram::Flows::GamesFlow.handle_callback(callback_query)
            Rails.logger.debug "[Telegram::Handlers::GamesCallbackHandler] GamesFlow.handle_callback returned=#{result.inspect}"
          rescue => e
            Rails.logger.error "[Telegram::Handlers::GamesCallbackHandler] flow error: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
            Telegram::Api.answer_callback(cb.cb_id, "Flow error: #{e.message}", show_alert: true) rescue nil
            return false
          end
          return true
        end

        Rails.logger.debug "[Telegram::Handlers::GamesCallbackHandler] unhandled callback data=#{cb.data.inspect}"
        true
      rescue => e
        Rails.logger.error "[Telegram::Handlers::GamesCallbackHandler] process error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        cb_id = callback_query["id"] rescue nil
        Telegram::Api.answer_callback(cb_id, "Games callback error.", show_alert: true) rescue nil
        false
      end
    end
  end
end
