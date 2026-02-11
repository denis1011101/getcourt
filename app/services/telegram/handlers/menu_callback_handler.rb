module Telegram
  module Handlers
    class MenuCallbackHandler
      def self.process(callback_query)
        cb = Telegram::Helpers::CallbackData.parse(callback_query)
        return false if cb.data.empty? || cb.chat_id.blank?

        case cb.data
        when "menu:main"
          Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
          Telegram::Handlers::MenuHandler.menu(cb.chat_id, message_id: cb.message_id) rescue nil
          true

        when "menu:search"
          Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
          Telegram::Handlers::SearchHandler.menu(cb.chat_id) rescue nil
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
