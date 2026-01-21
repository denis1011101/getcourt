module Telegram
  module Handlers
    class MenuCallbackHandler
      def self.process(callback_query)
        data  = (callback_query["data"] || "").to_s
        cb_id = callback_query["id"]
        chat_id = callback_query.dig("message", "chat", "id") || callback_query.dig("from", "id")
        msg_id = callback_query.dig("message", "message_id") || callback_query["inline_message_id"]
        return false if data.empty? || chat_id.nil?

        case data
        when "menu:main"
          Telegram::Api.answer_callback(cb_id, "") rescue nil
          Telegram::Handlers::MenuHandler.menu(chat_id, message_id: msg_id) rescue nil
          true

        when "menu:search"
          Telegram::Api.answer_callback(cb_id, "") rescue nil
          # если SearchHandler пока не умеет edit — будет просто новое сообщение
          Telegram::Handlers::SearchHandler.menu(chat_id) rescue nil
          true

        else
          false
        end
      rescue => e
        Rails.logger.error "[Telegram::Handlers::MenuCallbackHandler] #{e.class}: #{e.message}"
        false
      end
    end
  end
end
