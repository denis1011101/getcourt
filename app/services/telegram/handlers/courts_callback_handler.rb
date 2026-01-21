module Telegram
  module Handlers
    class CourtsCallbackHandler
      def self.process(callback_query)
        data  = (callback_query["data"] || "").to_s
        cb_id = callback_query["id"]
        chat_id = callback_query.dig("message", "chat", "id") || callback_query.dig("from", "id")
        msg_id = callback_query.dig("message", "message_id") || callback_query["inline_message_id"]
        return false unless chat_id && data.present?

        Rails.logger.debug "[Telegram::Handlers::CourtsCallbackHandler] data=#{data.inspect} chat_id=#{chat_id}"

        case data
        when /\Amenu:courts:page:(\d+)\z/
          page = Regexp.last_match(1).to_i
          Telegram::Api.answer_callback(cb_id, "") rescue nil
          Telegram::Handlers::CourtsHandler.list_page(chat_id, page, message_id: msg_id)

        when /\Acourt:show:(\d+):(\d+)\z/
          court_id = Regexp.last_match(1).to_i
          page = Regexp.last_match(2).to_i
          Telegram::Api.answer_callback(cb_id, "") rescue nil
          Telegram::Handlers::CourtsHandler.show_court(chat_id, court_id, page, message_id: msg_id)

        when /\Acreate_game_from_court:(\d+)\z/
          court_id = Regexp.last_match(1).to_i
          Telegram::Api.answer_callback(cb_id, "") rescue nil
          # forward original message_id/inline_message_id so flows can edit the original message
          Telegram::Flows::CourtsFlow.start_create_game_from_court(chat_id, court_id, cb_id: cb_id, message_id: msg_id) rescue nil

        when /\Acourt:games:(\d+):(\d+)\z/
          court_id = Regexp.last_match(1).to_i
          page = Regexp.last_match(2).to_i
          Telegram::Api.answer_callback(cb_id, "") rescue nil
          Telegram::Flows::CourtsFlow.handle_callback(callback_query) rescue nil

        else
          Rails.logger.info "[Telegram::Handlers::CourtsCallbackHandler] unknown courts callback: #{data.inspect}"
          Telegram::Api.answer_callback(cb_id, "Unknown courts action.", show_alert: true) rescue nil
        end

        true
      rescue => e
        Rails.logger.error "[Telegram::Handlers::CourtsCallbackHandler] #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        Telegram::Api.answer_callback(cb_id, "Courts callback error.", show_alert: true) rescue nil
        false
      end
    end
  end
end
