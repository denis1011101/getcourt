module Telegram
  module Handlers
    class GamesCallbackHandler
      def self.process(callback_query)
        data  = (callback_query["data"] || "").to_s
        cb_id = callback_query["id"]
        from  = callback_query["from"] || {}
        chat_id = (callback_query.dig("message","chat","id") || from["id"]).to_s
        msg_id = callback_query.dig("message","message_id") || callback_query["inline_message_id"]
        return false unless chat_id.present? && data.present?

        Rails.logger.debug "[Telegram::Handlers::GamesCallbackHandler] data=#{data.inspect} chat_id=#{chat_id}"
        Rails.logger.debug "[Telegram::Handlers::GamesCallbackHandler] cb_id=#{cb_id.inspect} msg_id=#{msg_id.inspect} from_id=#{from['id'].inspect} callback_keys=#{callback_query.keys.inspect}"

        # pagination/menu handled by GamesHandler
        if data =~ /\Amenu:games:page:(\d+)\z/
          page = $1.to_i
          Telegram::Handlers::GamesHandler.list_page(chat_id, page, message_id: msg_id) rescue nil
          Rails.logger.debug "[Telegram::Handlers::GamesCallbackHandler] handled by GamesHandler.list_page page=#{page}"
          return true
        end

        # delegate all game-related callbacks to GamesFlow
        if data.start_with?("game:") || data.start_with?("prebook:") || data.start_with?("create_game_from_court")
          Rails.logger.debug "[Telegram::Handlers::GamesCallbackHandler] delegating to GamesFlow.handle_callback data=#{data.inspect} chat_id=#{chat_id} cb_id=#{cb_id.inspect} msg_id=#{msg_id.inspect}"
          begin
            result = Telegram::Flows::GamesFlow.handle_callback(callback_query)
            Rails.logger.debug "[Telegram::Handlers::GamesCallbackHandler] GamesFlow.handle_callback returned=#{result.inspect}"
          rescue => e
            Rails.logger.error "[Telegram::Handlers::GamesCallbackHandler] flow error: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
            Telegram::Api.answer_callback(cb_id, "Flow error: #{e.message}", show_alert: true) rescue nil
            return false
          end
          return true
        end

        Rails.logger.debug "[Telegram::Handlers::GamesCallbackHandler] unhandled callback data=#{data.inspect}"
        true
      rescue => e
        Rails.logger.error "[Telegram::Handlers::GamesCallbackHandler] process error: #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        Telegram::Api.answer_callback(cb_id, "Games callback error.", show_alert: true) rescue nil
        false
      end
    end
  end
end
