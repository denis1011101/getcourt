module Telegram
  module Handlers
    class CourtsCallbackHandler
      def self.process(callback_query)
        cb = Telegram::Helpers::CallbackData.parse(callback_query)
        return false unless cb.chat_id.present? && cb.data.present?

        Rails.logger.debug "[Telegram::Handlers::CourtsCallbackHandler] data=#{cb.data.inspect} chat_id=#{cb.chat_id}"

        case cb.data
        when /\Amenu:courts:page:(\d+)\z/
          page = Regexp.last_match(1).to_i
          Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
          Telegram::Handlers::CourtsHandler.list_page(cb.chat_id, page, message_id: cb.message_id)

        when /\Acourt:show:(\d+):(\d+)\z/
          court_id = Regexp.last_match(1).to_i
          page = Regexp.last_match(2).to_i
          Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
          Telegram::Handlers::CourtsHandler.show_court(cb.chat_id, court_id, page, message_id: cb.message_id)

        when /\Acreate_game_from_court:(\d+)\z/
          court_id = Regexp.last_match(1).to_i
          Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
          Telegram::Flows::CourtsFlow.start_create_game_from_court(cb.chat_id, court_id, cb_id: cb.cb_id, message_id: cb.message_id) rescue nil

        when /\Acourt:games:(\d+):(\d+)\z/
          Telegram::Api.answer_callback(cb.cb_id, "") rescue nil
          Telegram::Flows::CourtsFlow.handle_callback(callback_query) rescue nil

        when /\Acourt:create\z/
          Telegram::Flows::CourtCreateFlow.handle_callback(callback_query) rescue nil

        when /\Acourt:create:/
          Telegram::Flows::CourtCreateFlow.handle_callback(callback_query) rescue nil

        else
          Rails.logger.info "[Telegram::Handlers::CourtsCallbackHandler] unknown courts callback: #{cb.data.inspect}"
          Telegram::Api.answer_callback(cb.cb_id, "Unknown courts action.", show_alert: true) rescue nil
        end

        true
      rescue => e
        Rails.logger.error "[Telegram::Handlers::CourtsCallbackHandler] #{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        cb_id = callback_query["id"] rescue nil
        Telegram::Api.answer_callback(cb_id, "Courts callback error.", show_alert: true) rescue nil
        false
      end
    end
  end
end
